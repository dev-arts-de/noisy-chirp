defmodule ChirpWeb.OathLive do
  @moduledoc """
  Dramatic page: the user must swear the oath before being released.

  Also dispatches the oath notification on first mount (idempotent — only once
  while the task is in `awaiting_oath` and we haven't dispatched yet this
  session).
  """
  use ChirpWeb, :live_view

  alias Chirp.Reminders

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

      %{state: "awaiting_oath"} = task ->
        {:ok,
         assign(socket,
           page_title: "SCHWÖRE",
           task: task,
           status: :pending,
           checked: false
         )}

      task ->
        {:ok,
         assign(socket,
           page_title: "Schwur erledigt",
           task: task,
           status: :already_done,
           checked: false
         )}
    end
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, checked: !socket.assigns.checked)}
  end

  def handle_event("swear", %{"oath" => "on"}, socket) do
    {:ok, updated} = Reminders.swear_task(socket.assigns.task)
    {:noreply, assign(socket, task: updated, status: :done)}
  end

  def handle_event("swear", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-gradient-to-b from-red-950 via-red-900 to-black text-red-50 px-4 py-12 flex items-center justify-center">
      <div class="w-full max-w-md">
        <.not_found :if={@status == :not_found} />
        <.pending :if={@status == :pending} task={@task} checked={@checked} />
        <.done :if={@status == :done} />
        <.already :if={@status == :already_done} />
      </div>
    </main>
    """
  end

  attr :task, :map, required: true
  attr :checked, :boolean, required: true

  defp pending(assigns) do
    ~H"""
    <div class="rounded-2xl border border-red-500/40 bg-black/40 backdrop-blur p-8 shadow-2xl text-center space-y-6">
      <.icon name="hero-exclamation-triangle" class="size-12 text-red-400 mx-auto" />
      <h1 class="text-2xl font-bold leading-snug">
        Schwöre mir,<br />
        dass du das wirklich erledigt hast:<br />
        <span class="text-red-300">{@task.name}</span>!!
      </h1>

      <form phx-submit="swear" class="space-y-6">
        <label class="flex items-center justify-center gap-3 text-lg">
          <input
            type="checkbox"
            name="oath"
            class="checkbox checkbox-lg checkbox-error"
            checked={@checked}
            phx-click="toggle"
          />
          <span>Ich schwöre</span>
        </label>

        <button
          type="submit"
          disabled={not @checked}
          class="w-full py-3 rounded-xl bg-red-600 hover:bg-red-500 disabled:opacity-40 text-white font-bold text-lg shadow-lg shadow-red-900/50"
        >
          Schwören
        </button>
      </form>
    </div>
    """
  end

  defp done(assigns) do
    ~H"""
    <div class="rounded-2xl border border-red-500/30 bg-black/40 p-10 text-center space-y-3">
      <.icon name="hero-check-badge" class="size-14 text-red-200 mx-auto" />
      <h1 class="text-2xl font-bold">Geschworen.</h1>
      <p class="opacity-80">Mögen die Götter dir glauben.</p>
    </div>
    """
  end

  defp already(assigns) do
    ~H"""
    <div class="rounded-2xl border border-red-500/30 bg-black/40 p-10 text-center space-y-3">
      <h1 class="text-xl font-bold">Kein Schwur nötig.</h1>
      <p class="opacity-80">Dieser Task ist nicht im Oath-Zustand.</p>
    </div>
    """
  end

  defp not_found(assigns) do
    ~H"""
    <div class="rounded-2xl border border-red-500/30 bg-black/40 p-10 text-center space-y-3">
      <h1 class="text-xl font-bold">Token unbekannt.</h1>
    </div>
    """
  end
end
