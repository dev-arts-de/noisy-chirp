defmodule Chirp.Reminders do
  @moduledoc """
  Context for recurring reminder tasks and their audit events.

  Owns persistence and the lie-factor logic; defers timing to `Chirp.Engine`
  and message dispatch to a notifier module.
  """

  import Ecto.Query
  alias Chirp.Repo
  alias Chirp.Reminders.{Task, Event}

  @oath_threshold 60

  # ----- Queries -----

  def list_tasks do
    Repo.all(from t in Task, order_by: [asc: t.next_fire_at])
  end

  def list_active_tasks do
    Repo.all(from t in Task, where: t.active == true)
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def get_task_by_token(token) when is_binary(token) do
    Repo.get_by(Task, token: token)
  end

  def list_events_for(task_id, limit \\ 50) do
    Repo.all(
      from e in Event,
        where: e.task_id == ^task_id,
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  # ----- Mutations -----

  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> maybe_start_engine()
  end

  defp maybe_start_engine({:ok, %Task{} = task} = result) do
    if Code.ensure_loaded?(Chirp.Engine) and function_exported?(Chirp.Engine, :start_task, 1) do
      Chirp.Engine.start_task(task)
    end

    result
  end

  defp maybe_start_engine(other), do: other

  @doc """
  Records that a notification was sent: bumps `last_sent_at`, stores a `sent`
  event with the priority. Returns the updated task.
  """
  def register_sent(%Task{} = task, priority) when is_integer(priority) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, updated} =
      task
      |> Task.changeset(%{last_sent_at: now})
      |> Repo.update()

    %Event{}
    |> Event.changeset(%{task_id: task.id, kind: "sent", priority: priority})
    |> Repo.insert!()

    updated
  end

  @doc """
  User confirmed the chore via the Confirm page. Returns:

    * `{:ok, :calm, task}` — released, task is back to calm with new `next_fire_at`
    * `{:ok, :awaiting_oath, task}` — lie threshold exceeded, oath required

  Runs the lie-factor evaluation atomically.
  """
  def confirm_task(%Task{} = task) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    latency_ms = latency_ms(task.last_sent_at, now)
    delta = lie_delta(latency_ms, task.reminder_count)
    new_score = clamp(task.lie_score + delta, 0, 100)

    Repo.transaction(fn ->
      %Event{}
      |> Event.changeset(%{
        task_id: task.id,
        kind: "confirmed",
        reaction_latency_ms: latency_ms
      })
      |> Repo.insert!()

      if new_score >= @oath_threshold do
        {:ok, updated} =
          task
          |> Task.changeset(%{state: "awaiting_oath", lie_score: new_score})
          |> Repo.update()

        %Event{}
        |> Event.changeset(%{task_id: updated.id, kind: "oath_sent", priority: 5})
        |> Repo.insert!()

        {:awaiting_oath, updated}
      else
        next = DateTime.add(now, task.base_interval_seconds, :second)

        {:ok, updated} =
          task
          |> Task.changeset(%{
            state: "calm",
            reminder_count: 0,
            lie_score: new_score,
            last_confirmed_at: now,
            next_fire_at: next
          })
          |> Repo.update()

        {:calm, updated}
      end
    end)
    |> case do
      {:ok, {:calm, task}} ->
        wake(task)
        {:ok, :calm, task}

      {:ok, {:awaiting_oath, task}} ->
        # Engine pauses naturally; the oath notification is dispatched by the
        # caller (LiveView) so we keep the context side-effect-free over HTTP.
        {:ok, :awaiting_oath, task}
    end
  end

  @doc """
  User swore the oath. Halve lie_score, release back to calm.
  """
  def swear_task(%Task{} = task) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    latency_ms = latency_ms(task.last_sent_at, now)
    new_score = clamp(div(task.lie_score, 2), 0, 100)
    next = DateTime.add(now, task.base_interval_seconds, :second)

    Repo.transaction(fn ->
      %Event{}
      |> Event.changeset(%{
        task_id: task.id,
        kind: "sworn",
        reaction_latency_ms: latency_ms
      })
      |> Repo.insert!()

      {:ok, updated} =
        task
        |> Task.changeset(%{
          state: "calm",
          reminder_count: 0,
          lie_score: new_score,
          last_confirmed_at: now,
          next_fire_at: next
        })
        |> Repo.update()

      updated
    end)
    |> case do
      {:ok, updated} ->
        wake(updated)
        {:ok, updated}
    end
  end

  @doc """
  Updates task state during escalation (called by the TaskServer after firing).
  """
  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Admin edit — same as `update_task/2` but also tells the engine to
  re-plan with the new state.
  """
  def update_task_and_wake(%Task{} = task, attrs) do
    with {:ok, updated} <- update_task(task, attrs) do
      wake(updated)
      {:ok, updated}
    end
  end

  @doc """
  Snooze: push `next_fire_at` forward by `seconds`, reset the escalation,
  release back to calm. Does *not* touch `lie_score`.
  """
  def snooze_task(%Task{} = task, seconds) when is_integer(seconds) and seconds > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    next = DateTime.add(now, seconds, :second)

    with {:ok, updated} <-
           update_task(task, %{
             state: "calm",
             reminder_count: 0,
             next_fire_at: next
           }) do
      wake(updated)
      {:ok, updated}
    end
  end

  @doc """
  Snooze to "tomorrow morning" at a wall-clock hour in the app's timezone.
  Defaults to 08:00.
  """
  def snooze_until_tomorrow(%Task{} = task, hour \\ 8) when hour in 0..23 do
    tz = Application.get_env(:noisy_chirp, :timezone, "Europe/Berlin")
    now = DateTime.utc_now()

    now_local = DateTime.shift_zone!(now, tz)

    tomorrow_local =
      now_local
      |> DateTime.add(86_400, :second)
      |> Map.merge(%{hour: hour, minute: 0, second: 0, microsecond: {0, 0}})

    target_utc = DateTime.shift_zone!(tomorrow_local, "Etc/UTC")
    seconds = DateTime.diff(target_utc, now, :second) |> max(60)

    snooze_task(task, seconds)
  end

  @doc "Pause: deactivate and stop the engine process."
  def pause_task(%Task{} = task) do
    with {:ok, updated} <- update_task(task, %{active: false}) do
      stop_engine(updated)
      {:ok, updated}
    end
  end

  @doc "Resume: re-activate and (re-)start the engine process."
  def resume_task(%Task{} = task) do
    with {:ok, updated} <- update_task(task, %{active: true}) do
      start_engine(updated)
      {:ok, updated}
    end
  end

  @doc "Delete: stop engine then remove from DB. Events cascade."
  def delete_task(%Task{} = task) do
    stop_engine(task)
    Repo.delete(task)
  end

  defp stop_engine(%Task{id: id}) do
    if Code.ensure_loaded?(Chirp.Engine) and function_exported?(Chirp.Engine, :stop_task, 1) do
      Chirp.Engine.stop_task(id)
    end

    :ok
  end

  defp start_engine(%Task{} = task) do
    if Code.ensure_loaded?(Chirp.Engine) and function_exported?(Chirp.Engine, :start_task, 1) do
      Chirp.Engine.start_task(task)
    end

    :ok
  end

  # ----- Internals -----

  defp latency_ms(nil, _now), do: nil

  defp latency_ms(%DateTime{} = sent, now) do
    DateTime.diff(now, sent, :millisecond)
  end

  @doc false
  def lie_delta(nil, _reminder_count), do: 0

  def lie_delta(latency_ms, reminder_count) when is_integer(latency_ms) do
    delta = 0
    delta = if latency_ms < 8_000, do: delta + 30, else: delta
    delta = if latency_ms < 30_000, do: delta + 10, else: delta

    delta =
      if latency_ms >= 60_000 and latency_ms <= 900_000,
        do: delta - 15,
        else: delta

    delta =
      if reminder_count <= 1 and latency_ms < 15_000,
        do: delta + 10,
        else: delta

    delta
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  defp wake(%Task{} = task) do
    if Code.ensure_loaded?(Chirp.Engine) and function_exported?(Chirp.Engine, :wake, 1) do
      Chirp.Engine.wake(task)
    end

    :ok
  end

  def oath_threshold, do: @oath_threshold
end
