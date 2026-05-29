defmodule ChirpWeb.ConfirmLive do
  @moduledoc """
  The page opened from the ntfy notification: one question, one checkbox,
  one button — plus two snooze shortcuts ("+1h", "Morgen früh") for when
  the user genuinely can't deal with it right now.
  """
  use ChirpWeb, :live_view

  alias Chirp.Reminders
  alias Chirp.Notifier

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Reminders.get_task_by_token(token) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "nicht gefunden",
           task: nil,
           status: :not_found,
           checked: false
         )}

      task ->
        {:ok,
         assign(socket,
           page_title: "Bestätigen",
           task: task,
           status: status_from_task(task),
           checked: false
         )}
    end
  end

  defp status_from_task(%{state: "awaiting_oath"}), do: :awaiting_oath
  defp status_from_task(_), do: :pending

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, checked: !socket.assigns.checked)}
  end

  def handle_event("confirm", %{"ack" => "on"}, socket) do
    task = socket.assigns.task

    case Reminders.confirm_task(task) do
      {:ok, :calm, updated} ->
        {:noreply, assign(socket, task: updated, status: :done)}

      {:ok, :awaiting_oath, updated} ->
        send_oath_notification(updated)
        {:noreply, push_navigate(socket, to: ~p"/oath/#{updated.token}")}
    end
  end

  def handle_event("confirm", _params, socket), do: {:noreply, socket}

  def handle_event("snooze", %{"amount" => "1h"}, socket) do
    {:ok, updated} = Reminders.snooze_task(socket.assigns.task, 60 * 60)
    {:noreply, assign(socket, task: updated, status: :snoozed, snoozed_to: updated.next_fire_at)}
  end

  def handle_event("snooze", %{"amount" => "tomorrow"}, socket) do
    {:ok, updated} = Reminders.snooze_until_tomorrow(socket.assigns.task)
    {:noreply, assign(socket, task: updated, status: :snoozed, snoozed_to: updated.next_fire_at)}
  end

  defp send_oath_notification(task) do
    base = Application.get_env(:noisy_chirp, :public_base_url, "http://localhost:4000")
    click = "#{String.trim_trailing(base, "/")}/oath/#{task.token}"

    Notifier.publish(task.ntfy_topic,
      title: "Schwur erforderlich",
      message: "Schwöre mir, dass du das wirklich erledigt hast: #{task.name}!!",
      priority: 5,
      tags: ["pray", "skull"],
      click: click
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-300 px-4 py-10 flex items-center justify-center">
      <div class="w-full max-w-md">
        <.not_found :if={@status == :not_found} />
        <.pending_card :if={@status == :pending} task={@task} checked={@checked} />
        <.awaiting :if={@status == :awaiting_oath} task={@task} />
        <.done :if={@status == :done} task={@task} />
        <.snoozed :if={@status == :snoozed} task={@task} snoozed_to={@snoozed_to} />
      </div>
    </main>
    """
  end

  attr :task, :map, required: true
  attr :checked, :boolean, required: true

  defp pending_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body items-center text-center gap-6 py-10">
        <span class="text-4xl">🐦</span>
        <h1 class="text-2xl font-bold leading-tight px-2">
          {@task.name}?
        </h1>

        <form phx-submit="confirm" class="w-full space-y-5">
          <label class="label cursor-pointer justify-center gap-3 text-base">
            <input
              type="checkbox"
              name="ack"
              class="checkbox checkbox-primary checkbox-lg"
              checked={@checked}
              phx-click="toggle"
            />
            <span>Ja, erledigt.</span>
          </label>

          <button
            type="submit"
            disabled={not @checked}
            class="btn btn-primary btn-block btn-lg"
          >
            Bestätigen
          </button>
        </form>

        <div class="w-full pt-2">
          <div class="text-xs opacity-60 mb-2">Gerade keine Zeit?</div>
          <div class="flex gap-2 justify-center">
            <button
              type="button"
              phx-click="snooze"
              phx-value-amount="1h"
              class="btn btn-ghost btn-sm"
            >
              +1 Stunde
            </button>
            <button
              type="button"
              phx-click="snooze"
              phx-value-amount="tomorrow"
              class="btn btn-ghost btn-sm"
            >
              Morgen früh
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :task, :map, required: true

  defp done(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body items-center text-center gap-4 py-12">
        <span class="text-5xl">🤫</span>
        <h1 class="text-2xl font-bold">Erledigt.</h1>
        <p class="opacity-80">Ruhe.</p>
      </div>
    </div>
    """
  end

  attr :task, :map, required: true
  attr :snoozed_to, :any, required: true

  defp snoozed(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body items-center text-center gap-4 py-12">
        <span class="text-5xl">💤</span>
        <h1 class="text-2xl font-bold">Vertagt.</h1>
        <p class="opacity-80">Ich melde mich {format_snooze(@snoozed_to)} wieder.</p>
      </div>
    </div>
    """
  end

  attr :task, :map, required: true

  defp awaiting(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl border border-error/40">
      <div class="card-body items-center text-center gap-4 py-10">
        <span class="text-4xl">😬</span>
        <h1 class="text-xl font-bold">Schwur ausstehend.</h1>
        <p class="opacity-80">Du musst erst schwören.</p>
        <a class="btn btn-error btn-block" href={~p"/oath/#{@task.token}"}>Zum Schwur</a>
      </div>
    </div>
    """
  end

  defp not_found(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body items-center text-center gap-2 py-12">
        <span class="text-4xl">🤷</span>
        <h1 class="text-xl font-bold">Token unbekannt.</h1>
        <p class="opacity-70">Vielleicht eine alte Notification?</p>
      </div>
    </div>
    """
  end

  defp format_snooze(%DateTime{} = dt) do
    diff = DateTime.diff(dt, DateTime.utc_now(), :second)

    cond do
      diff < 60 -> "gleich"
      diff < 3600 -> "in #{div(diff, 60)} Minuten"
      diff < 86_400 -> "in #{div(diff, 3600)} Stunden"
      true -> "morgen früh"
    end
  end

  defp format_snooze(_), do: "bald"
end
