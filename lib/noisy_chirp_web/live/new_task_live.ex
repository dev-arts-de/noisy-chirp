defmodule ChirpWeb.NewTaskLive do
  @moduledoc """
  Admin form to create a new reminder task. Exactly three fields:

    * Beschreibung (z. B. "Zahnbürstenkopf wechseln")
    * Erste Erinnerung (datetime-local)
    * Zyklus (Preset-Select)

  Everything else (ntfy topic, name/verb splitting, token generation) is
  derived sensibly from app config + defaults.
  """
  use ChirpWeb, :live_view

  alias Chirp.Reminders

  @cycle_options [
    {"daily", "Täglich", 86_400},
    {"every_3_days", "Alle 3 Tage", 3 * 86_400},
    {"weekly", "Wöchentlich", 7 * 86_400},
    {"biweekly", "Alle 2 Wochen", 14 * 86_400},
    {"monthly", "Monatlich (30 Tage)", 30 * 86_400},
    {"bimonthly", "Alle 2 Monate (60 Tage)", 60 * 86_400},
    {"quarterly", "Alle 3 Monate (90 Tage)", 90 * 86_400},
    {"half_yearly", "Halbjährlich (180 Tage)", 180 * 86_400},
    {"yearly", "Jährlich (365 Tage)", 365 * 86_400}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Neuer Chirp",
       form: empty_form(),
       error: nil,
       cycle_options: @cycle_options
     )}
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    {:noreply, assign(socket, form: params, error: nil)}
  end

  def handle_event("save", %{"task" => params}, socket) do
    case build_attrs(params) do
      {:ok, attrs} ->
        case Reminders.create_task(attrs) do
          {:ok, _task} ->
            {:noreply,
             socket
             |> put_flash(:info, "Chirp angelegt.")
             |> push_navigate(to: ~p"/admin")}

          {:error, changeset} ->
            {:noreply,
             assign(socket,
               form: params,
               error: changeset_error(changeset)
             )}
        end

      {:error, message} ->
        {:noreply, assign(socket, form: params, error: message)}
    end
  end

  # ---- Internals ----

  defp empty_form do
    %{
      "description" => "",
      "first_fire_local" => default_first_fire(),
      "cycle" => "bimonthly"
    }
  end

  defp default_first_fire do
    DateTime.utc_now()
    |> DateTime.add(60 * 60, :second)
    |> DateTime.shift_zone!(app_timezone())
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp build_attrs(%{
         "description" => description,
         "first_fire_local" => first_fire_str,
         "cycle" => cycle
       }) do
    with {:ok, desc} <- validate_description(description),
         {:ok, first_fire} <- parse_local_datetime(first_fire_str),
         {:ok, interval} <- lookup_cycle(cycle) do
      {:ok,
       %{
         name: desc,
         verb: "",
         base_interval_seconds: interval,
         ntfy_topic: default_topic(),
         next_fire_at: DateTime.truncate(first_fire, :second),
         state: "calm",
         reminder_count: 0,
         active: true
       }}
    end
  end

  defp build_attrs(_), do: {:error, "Ungültige Eingabe."}

  defp validate_description(desc) when is_binary(desc) do
    trimmed = String.trim(desc)

    cond do
      trimmed == "" -> {:error, "Beschreibung darf nicht leer sein."}
      String.length(trimmed) > 140 -> {:error, "Beschreibung max. 140 Zeichen."}
      true -> {:ok, trimmed}
    end
  end

  defp validate_description(_), do: {:error, "Beschreibung fehlt."}

  # HTML datetime-local sends "YYYY-MM-DDTHH:MM" — local browser time, no TZ.
  # We interpret it in the app's configured timezone (default Europe/Berlin)
  # and store in UTC.
  defp parse_local_datetime(str) when is_binary(str) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(ensure_seconds(str)),
         {:ok, dt} <- DateTime.from_naive(naive, app_timezone()) do
      utc = DateTime.shift_zone!(dt, "Etc/UTC")
      now = DateTime.utc_now()

      if DateTime.compare(utc, now) == :gt do
        {:ok, utc}
      else
        {:error, "Zeitpunkt muss in der Zukunft liegen."}
      end
    else
      _ -> {:error, "Ungültiges Datum."}
    end
  end

  defp parse_local_datetime(_), do: {:error, "Datum fehlt."}

  defp ensure_seconds(str) do
    case String.split(str, "T") do
      [_date, time] when byte_size(time) == 5 -> str <> ":00"
      _ -> str
    end
  end

  defp app_timezone do
    Application.get_env(:noisy_chirp, :timezone, "Europe/Berlin")
  end

  defp lookup_cycle(value) do
    case Enum.find(@cycle_options, fn {key, _, _} -> key == value end) do
      {_, _, seconds} -> {:ok, seconds}
      nil -> {:error, "Unbekannter Zyklus."}
    end
  end

  defp default_topic do
    System.get_env("NTFY_TOPIC") ||
      Application.get_env(:noisy_chirp, :default_ntfy_topic) ||
      "noisy-chirp-default"
  end

  defp changeset_error(%Ecto.Changeset{} = cs) do
    cs.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  # ---- Render ----

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 px-4 py-10">
      <div class="mx-auto max-w-md">
        <.page_header />

        <form
          phx-change="validate"
          phx-submit="save"
          class="card bg-base-100 shadow-sm"
        >
          <div class="card-body gap-5">
            <label class="form-control">
              <span class="label-text mb-1">Beschreibung</span>
              <input
                type="text"
                name="task[description]"
                value={@form["description"]}
                placeholder="z. B. Zahnbürstenkopf wechseln"
                autofocus
                required
                maxlength="140"
                class="input input-bordered w-full"
              />
              <span class="label-text-alt mt-1 opacity-60">
                Wird so in der Push-Nachricht stehen.
              </span>
            </label>

            <label class="form-control">
              <span class="label-text mb-1">Erste Erinnerung</span>
              <input
                type="datetime-local"
                name="task[first_fire_local]"
                value={@form["first_fire_local"]}
                required
                class="input input-bordered w-full"
              />
            </label>

            <label class="form-control">
              <span class="label-text mb-1">Zyklus</span>
              <select
                name="task[cycle]"
                class="select select-bordered w-full"
              >
                <option
                  :for={{key, label, _} <- @cycle_options}
                  value={key}
                  selected={@form["cycle"] == key}
                >
                  {label}
                </option>
              </select>
              <span class="label-text-alt mt-1 opacity-60">
                Abstand zwischen Bestätigung und nächster Mahnung.
              </span>
            </label>

            <div :if={@error} class="text-sm text-error">{@error}</div>

            <div class="flex items-center justify-between pt-2">
              <.link
                href={~p"/admin"}
                class="btn btn-ghost"
              >
                Abbrechen
              </.link>
              <button type="submit" class="btn btn-primary">
                Anlegen
              </button>
            </div>
          </div>
        </form>
      </div>
    </main>
    """
  end

  defp page_header(assigns) do
    ~H"""
    <header class="flex items-center justify-between mb-6">
      <h1 class="text-xl font-semibold">Neuer Chirp</h1>
      <.link href={~p"/admin"} class="text-sm opacity-70 hover:opacity-100">
        ← Admin
      </.link>
    </header>
    """
  end
end
