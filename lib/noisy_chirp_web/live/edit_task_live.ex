defmodule ChirpWeb.EditTaskLive do
  @moduledoc """
  Admin edit form for an existing task. Pre-filled. Submits via
  `Reminders.update_task_and_wake/2` so the engine re-plans.
  """
  use ChirpWeb, :live_view

  alias Chirp.{Cycles, Reminders}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {task_id, ""} ->
        task = Reminders.get_task!(task_id)

        {:ok,
         assign(socket,
           page_title: "Chirp bearbeiten",
           task: task,
           form: form_for(task),
           error: nil
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Task nicht gefunden.")
         |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    {:noreply, assign(socket, form: params, error: nil)}
  end

  def handle_event("save", %{"task" => params}, socket) do
    case build_attrs(params) do
      {:ok, attrs} ->
        case Reminders.update_task_and_wake(socket.assigns.task, attrs) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Geändert.")
             |> push_navigate(to: ~p"/admin")}

          {:error, changeset} ->
            {:noreply, assign(socket, form: params, error: changeset_error(changeset))}
        end

      {:error, message} ->
        {:noreply, assign(socket, form: params, error: message)}
    end
  end

  # ---- Form ----

  defp form_for(%{base_interval_seconds: seconds} = task) do
    {cycle, custom_days} =
      case Cycles.from_seconds(seconds) do
        {:preset, key} -> {key, "30"}
        {:custom, days} -> {"custom", Integer.to_string(days)}
      end

    %{
      "description" => task.name,
      "first_fire_local" => ChirpWeb.TaskForm.datetime_to_local_input(task.next_fire_at),
      "cycle" => cycle,
      "custom_days" => custom_days
    }
  end

  defp build_attrs(%{"description" => desc, "first_fire_local" => dt} = params) do
    cycle = params["cycle"] || ""
    custom_days = params["custom_days"] || ""

    with {:ok, description} <- ChirpWeb.TaskForm.validate_description(desc),
         {:ok, first_fire} <- ChirpWeb.TaskForm.parse_local_datetime(dt),
         {:ok, interval} <- Cycles.from_input(cycle, custom_days) do
      {:ok,
       %{
         name: description,
         base_interval_seconds: interval,
         next_fire_at: DateTime.truncate(first_fire, :second),
         # Editing implies a fresh start — back to calm.
         state: "calm",
         reminder_count: 0
       }}
    end
  end

  defp build_attrs(_), do: {:error, "Ungültige Eingabe."}

  defp changeset_error(%Ecto.Changeset{} = cs) do
    cs.errors
    |> Enum.map_join(", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  # ---- Render ----

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 px-4 py-10">
      <div class="mx-auto max-w-md">
        <header class="flex items-center justify-between mb-6">
          <h1 class="text-xl font-semibold">Bearbeiten</h1>
          <.link href={~p"/admin"} class="text-sm opacity-70 hover:opacity-100">← Admin</.link>
        </header>

        <form phx-change="validate" phx-submit="save" class="card bg-base-100 shadow-sm">
          <div class="card-body gap-5">
            <ChirpWeb.TaskForm.description_field value={@form["description"]} />
            <ChirpWeb.TaskForm.first_fire_field value={@form["first_fire_local"]} />
            <ChirpWeb.TaskForm.cycle_field
              cycle={@form["cycle"]}
              custom_days={@form["custom_days"]}
            />

            <div :if={@error} class="text-sm text-error">{@error}</div>

            <div class="flex items-center justify-between pt-2">
              <.link href={~p"/admin"} class="btn btn-ghost">Abbrechen</.link>
              <button type="submit" class="btn btn-primary">Speichern</button>
            </div>
          </div>
        </form>
      </div>
    </main>
    """
  end
end
