defmodule Chirp.Engine.TaskServer do
  @moduledoc """
  One GenServer per active reminder task.

  Owns the scheduling timer. The database is the source of truth — on every
  fire we reload the task before deciding what to do. Crash-safe: when the
  DynamicSupervisor restarts us we rebuild state from the DB.
  """
  use GenServer
  require Logger

  alias Chirp.Reminders
  alias Chirp.Reminders.Task, as: ReminderTask
  alias Chirp.Engine.{Escalation, Registry}
  alias Chirp.Notifier

  # send_after accepts up to ~49 days; cap well below that and recheck.
  @max_timer_ms 24 * 60 * 60 * 1000

  # ---- Public API ----

  def start_link(task_id) when is_integer(task_id) do
    GenServer.start_link(__MODULE__, task_id, name: via(task_id))
  end

  @doc "Cancel current timer and re-plan based on fresh DB state."
  def wake(task_id) when is_integer(task_id) do
    case Registry.whereis(task_id) do
      :undefined -> :ignored
      pid when is_pid(pid) -> GenServer.cast(pid, :wake)
    end
  end

  defp via(task_id), do: {:via, Elixir.Registry, {Chirp.Engine.Registry, task_id}}

  # ---- Callbacks ----

  @impl true
  def init(task_id) do
    state = %{task_id: task_id, timer: nil}
    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_cast(:wake, state) do
    {:noreply, schedule_next(cancel_timer(state))}
  end

  @impl true
  def handle_info(:fire, state) do
    case Reminders.get_task!(state.task_id) do
      %ReminderTask{active: false} ->
        {:noreply, %{state | timer: nil}}

      %ReminderTask{state: "awaiting_oath"} = _task ->
        # Pause: wait for swear/confirm to wake us.
        {:noreply, %{state | timer: nil}}

      %ReminderTask{} = task ->
        {:noreply, fire(task, state)}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    # Long-wait checkpoint: re-evaluate scheduling.
    {:noreply, schedule_next(%{state | timer: nil})}
  end

  # ---- Internals ----

  defp fire(task, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    due? = DateTime.compare(now, task.next_fire_at) != :lt

    if due? do
      send_chirp(task)
    else
      schedule_next(state, task)
    end
  end

  defp send_chirp(task) do
    new_count =
      case task.state do
        "calm" -> 1
        "nagging" -> task.reminder_count + 1
        _ -> max(task.reminder_count, 1)
      end

    {:ok, task} =
      Reminders.update_task(task, %{state: "nagging", reminder_count: new_count})

    dispatch(task, new_count)
    task = Reminders.register_sent(task, Escalation.priority(new_count))
    schedule_next(%{task_id: task.id, timer: nil}, task)
  end

  defp dispatch(task, n) do
    rendered = Escalation.render(n, task.name, task.verb)

    Notifier.publish(task.ntfy_topic,
      title: rendered.title,
      message: rendered.message,
      priority: rendered.priority,
      tags: rendered.tags,
      click: click_url(task)
    )
  rescue
    e ->
      Logger.warning("dispatch crashed for task=#{task.id}: #{Exception.message(e)}")
  end

  defp click_url(task) do
    base = Application.get_env(:noisy_chirp, :public_base_url, "http://localhost:4000")
    "#{String.trim_trailing(base, "/")}/t/#{task.token}"
  end

  defp schedule_next(state, task \\ nil) do
    task = task || Reminders.get_task!(state.task_id)
    state = cancel_timer(state)

    cond do
      not task.active ->
        %{state | timer: nil}

      task.state == "awaiting_oath" ->
        %{state | timer: nil}

      task.state == "calm" ->
        delay = ms_until(task.next_fire_at)
        arm(state, delay)

      task.state == "nagging" ->
        # Already in escalation: gap from the last reminder_count.
        delay = Escalation.gap(max(task.reminder_count, 1))
        arm(state, delay)

      true ->
        %{state | timer: nil}
    end
  end

  defp ms_until(%DateTime{} = at) do
    now = DateTime.utc_now()
    diff = DateTime.diff(at, now, :millisecond)
    if diff < 0, do: 0, else: diff
  end

  defp arm(state, delay_ms) when delay_ms <= @max_timer_ms do
    timer = Process.send_after(self(), :fire, max(delay_ms, 0))
    %{state | timer: timer}
  end

  defp arm(state, delay_ms) do
    # Wake earlier than needed to re-check (within send_after's range).
    timer = Process.send_after(self(), :tick, @max_timer_ms)

    Logger.debug(
      "task #{state.task_id} long-wait #{delay_ms}ms, checkpoint in #{@max_timer_ms}ms"
    )

    %{state | timer: timer}
  end

  defp cancel_timer(%{timer: nil} = s), do: s

  defp cancel_timer(%{timer: ref} = s) do
    Process.cancel_timer(ref)
    %{s | timer: nil}
  end
end
