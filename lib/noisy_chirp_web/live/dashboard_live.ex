defmodule ChirpWeb.DashboardLive do
  @moduledoc """
  Admin overview with per-task actions: edit, pause/resume, delete.
  Behind auth via the `:admin` LiveView pipeline in the router.
  """
  use ChirpWeb, :live_view

  alias Chirp.{Cycles, Reminders}

  @refresh_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @refresh_ms)

    {:ok,
     socket
     |> assign(page_title: "Admin", confirming_delete: nil)
     |> load_tasks()}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @refresh_ms)
    {:noreply, load_tasks(socket)}
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    task = Reminders.get_task!(String.to_integer(id))
    {:ok, _} = Reminders.pause_task(task)
    {:noreply, load_tasks(socket)}
  end

  def handle_event("resume", %{"id" => id}, socket) do
    task = Reminders.get_task!(String.to_integer(id))
    {:ok, _} = Reminders.resume_task(task)
    {:noreply, load_tasks(socket)}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirming_delete: String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirming_delete: nil)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    task = Reminders.get_task!(String.to_integer(id))
    {:ok, _} = Reminders.delete_task(task)

    {:noreply,
     socket
     |> assign(confirming_delete: nil)
     |> put_flash(:info, "Gelöscht.")
     |> load_tasks()}
  end

  defp load_tasks(socket), do: assign(socket, tasks: Reminders.list_tasks())

  # ---- Render ----

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
          <li
            :for={task <- @tasks}
            class={[
              "card bg-base-100 shadow-sm",
              not task.active && "opacity-60"
            ]}
          >
            <div class="card-body py-3 px-4">
              <.task_row
                task={task}
                confirming_delete={@confirming_delete}
              />
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

  attr :task, :map, required: true
  attr :confirming_delete, :any, default: nil

  defp task_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3">
      <div class="min-w-0">
        <div class="font-medium truncate">{@task.name}</div>
        <div class="text-xs opacity-60 mt-0.5">
          {state_label(@task)} · {Cycles.label(@task.base_interval_seconds)} ·
          nächster Schuss {format_when(@task.next_fire_at)}
        </div>
      </div>

      <div class="flex items-center gap-1 shrink-0">
        <span
          :if={@task.lie_score >= 30 and @task.active}
          class={"badge badge-sm mr-1 " <> lie_badge(@task.lie_score)}
        >
          Lügenwert {@task.lie_score}
        </span>

        <%= if @confirming_delete == @task.id do %>
          <span class="text-xs opacity-70 mr-1">Sicher?</span>
          <button
            type="button"
            phx-click="confirm_delete"
            phx-value-id={@task.id}
            class="btn btn-error btn-xs"
          >
            Löschen
          </button>
          <button
            type="button"
            phx-click="cancel_delete"
            class="btn btn-ghost btn-xs"
          >
            Abbrechen
          </button>
        <% else %>
          <.link
            href={~p"/admin/#{@task.id}/edit"}
            class="btn btn-ghost btn-xs"
            title="Bearbeiten"
          >
            ✎
          </.link>

          <%= if @task.active do %>
            <button
              type="button"
              phx-click="pause"
              phx-value-id={@task.id}
              class="btn btn-ghost btn-xs"
              title="Pausieren"
            >
              ⏸
            </button>
          <% else %>
            <button
              type="button"
              phx-click="resume"
              phx-value-id={@task.id}
              class="btn btn-ghost btn-xs"
              title="Fortsetzen"
            >
              ▶
            </button>
          <% end %>

          <button
            type="button"
            phx-click="ask_delete"
            phx-value-id={@task.id}
            class="btn btn-ghost btn-xs text-error/80"
            title="Löschen"
          >
            🗑
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp state_label(%{active: false}), do: "pausiert"
  defp state_label(%{state: "calm"}), do: "ruhig"
  defp state_label(%{state: "nagging"}), do: "nervt gerade"
  defp state_label(%{state: "awaiting_oath"}), do: "Schwur ausstehend"
  defp state_label(%{state: s}), do: s

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
