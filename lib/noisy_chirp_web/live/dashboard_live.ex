defmodule ChirpWeb.DashboardLive do
  @moduledoc """
  Admin overview of all reminder tasks. Behind auth via the `:admin`
  LiveView pipeline in the router.
  """
  use ChirpWeb, :live_view

  alias Chirp.Reminders

  @refresh_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @refresh_ms)
    {:ok, assign(socket, tasks: Reminders.list_tasks(), page_title: "Admin")}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @refresh_ms)
    {:noreply, assign(socket, tasks: Reminders.list_tasks())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 px-4 py-8">
      <div class="mx-auto max-w-2xl">
        <.toolbar />

        <div :if={@tasks == []} class="card bg-base-100 shadow-sm">
          <div class="card-body items-center text-center py-12 gap-3">
            <img src={~p"/images/logo.png"} class="w-16 opacity-60" alt="" />
            <p class="opacity-70">Noch keine Chirps.</p>
            <.link href={~p"/admin/new"} class="btn btn-primary btn-sm mt-2">
              Ersten anlegen
            </.link>
          </div>
        </div>

        <ul class="space-y-2">
          <li :for={task <- @tasks} class="card bg-base-100 shadow-sm">
            <div class="card-body py-3 px-4">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="font-medium truncate">{task.name}</div>
                  <div class="text-xs opacity-60 mt-0.5">
                    {state_label(task.state)} · nächster Schuss {format_when(task.next_fire_at)}
                  </div>
                </div>
                <div class="flex items-center gap-2 shrink-0">
                  <span
                    :if={task.lie_score >= 30}
                    class={"badge badge-sm " <> lie_badge(task.lie_score)}
                  >
                    Lügenwert {task.lie_score}
                  </span>
                </div>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </main>
    """
  end

  defp toolbar(assigns) do
    ~H"""
    <header class="flex items-center justify-between mb-6">
      <div class="flex items-center gap-2">
        <img src={~p"/images/logo.png"} alt="" class="w-9" />
        <h1 class="text-lg font-semibold">Admin</h1>
      </div>

      <div class="flex items-center gap-2">
        <.link href={~p"/admin/new"} class="btn btn-primary btn-sm">+ Neu</.link>
        <.link
          href={~p"/logout"}
          method="delete"
          class="btn btn-ghost btn-sm"
        >
          Logout
        </.link>
      </div>
    </header>
    """
  end

  defp state_label("calm"), do: "ruhig"
  defp state_label("nagging"), do: "nervt gerade"
  defp state_label("awaiting_oath"), do: "Schwur ausstehend"
  defp state_label(other), do: other

  defp lie_badge(s) when s >= 60, do: "badge-error"
  defp lie_badge(s) when s >= 30, do: "badge-warning"
  defp lie_badge(_), do: "badge-ghost"

  defp format_when(nil), do: "—"

  defp format_when(%DateTime{} = dt) do
    diff = DateTime.diff(dt, DateTime.utc_now(), :second)

    cond do
      diff > 86_400 -> "in #{div(diff, 86_400)} Tagen"
      diff > 3_600 -> "in #{div(diff, 3_600)} h"
      diff > 60 -> "in #{div(diff, 60)} min"
      diff > 0 -> "in #{diff} s"
      diff > -60 -> "jetzt"
      diff > -3_600 -> "vor #{div(-diff, 60)} min"
      true -> "überfällig"
    end
  end
end
