defmodule ChirpWeb.DashboardLive do
  @moduledoc """
  Read-only overview of all reminder tasks.
  """
  use ChirpWeb, :live_view

  alias Chirp.Reminders

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @refresh_ms)
    {:ok, assign(socket, tasks: Reminders.list_tasks(), page_title: "noisy-chirp")}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @refresh_ms)
    {:noreply, assign(socket, tasks: Reminders.list_tasks())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-3xl">
        <header class="mb-8 flex items-center gap-3">
          <span class="text-2xl">🐦</span>
          <div>
            <h1 class="text-2xl font-bold">noisy-chirp</h1>
            <p class="text-sm opacity-70">
              {length(@tasks)} Pflicht{if length(@tasks) == 1, do: "", else: "en"} ·
              Auto-Refresh alle 5s
            </p>
          </div>
        </header>

        <div :if={@tasks == []} class="card bg-base-100 shadow">
          <div class="card-body items-center text-center">
            <p>Keine Tasks angelegt.</p>
          </div>
        </div>

        <ul class="space-y-3">
          <li :for={task <- @tasks} class="card bg-base-100 shadow-sm">
            <div class="card-body py-4">
              <div class="flex flex-wrap items-baseline justify-between gap-3">
                <div>
                  <h2 class="card-title text-lg">{task.name}</h2>
                  <p class="text-xs opacity-60">{task.verb} · {task.ntfy_topic}</p>
                </div>
                <span class={"badge " <> state_badge(task.state)}>{task.state}</span>
              </div>

              <div class="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
                <div>
                  <div class="opacity-60">nächster Schuss</div>
                  <div class="font-mono">{format_when(task.next_fire_at)}</div>
                </div>
                <div>
                  <div class="opacity-60">reminders</div>
                  <div class="font-mono">{task.reminder_count}</div>
                </div>
                <div>
                  <div class="opacity-60">lie score</div>
                  <div class={"font-mono " <> lie_color(task.lie_score)}>{task.lie_score}</div>
                </div>
                <div>
                  <div class="opacity-60">last confirmed</div>
                  <div class="font-mono">{format_when(task.last_confirmed_at)}</div>
                </div>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </main>
    """
  end

  defp state_badge("calm"), do: "badge-success"
  defp state_badge("nagging"), do: "badge-warning"
  defp state_badge("awaiting_oath"), do: "badge-error"
  defp state_badge(_), do: "badge-neutral"

  defp lie_color(score) when score >= 60, do: "text-error"
  defp lie_color(score) when score >= 30, do: "text-warning"
  defp lie_color(_), do: ""

  defp format_when(nil), do: "—"

  defp format_when(%DateTime{} = dt) do
    diff = DateTime.diff(dt, DateTime.utc_now(), :second)

    cond do
      diff > 86_400 -> "in #{div(diff, 86_400)}d"
      diff > 3_600 -> "in #{div(diff, 3_600)}h"
      diff > 60 -> "in #{div(diff, 60)}m"
      diff > 0 -> "in #{diff}s"
      diff > -60 -> "vor #{-diff}s"
      diff > -3_600 -> "vor #{div(-diff, 60)}m"
      diff > -86_400 -> "vor #{div(-diff, 3_600)}h"
      true -> "vor #{div(-diff, 86_400)}d"
    end
  end
end
