defmodule ChirpWeb.TaskForm do
  @moduledoc """
  Shared form components + parse helpers used by New and Edit LiveViews.

  Three fields, exactly: Beschreibung, Erste Erinnerung, Zyklus (with an
  optional days input revealed when cycle == "custom").
  """
  use Phoenix.Component

  alias Chirp.Cycles

  # ---- Field components ----

  attr :value, :string, required: true

  def description_field(assigns) do
    ~H"""
    <label class="form-control">
      <span class="label-text mb-1">Beschreibung</span>
      <input
        type="text"
        name="task[description]"
        value={@value}
        placeholder="z. B. Zahnbürstenkopf wechseln"
        required
        autofocus
        maxlength="140"
        class="input input-bordered w-full"
      />
      <span class="label-text-alt mt-1 opacity-60">
        Wird so in der Push stehen (der Vogel zitiert dich).
      </span>
    </label>
    """
  end

  attr :value, :string, required: true

  def first_fire_field(assigns) do
    ~H"""
    <label class="form-control">
      <span class="label-text mb-1">Erste Erinnerung</span>
      <input
        type="datetime-local"
        name="task[first_fire_local]"
        value={@value}
        required
        class="input input-bordered w-full"
      />
    </label>
    """
  end

  attr :cycle, :string, required: true
  attr :custom_days, :string, default: "30"

  def cycle_field(assigns) do
    ~H"""
    <div class="form-control space-y-2">
      <label class="form-control">
        <span class="label-text mb-1">Zyklus</span>
        <select name="task[cycle]" class="select select-bordered w-full">
          <option
            :for={{key, label, _} <- Cycles.presets()}
            value={key}
            selected={@cycle == key}
          >
            {label}
          </option>
          <option value="custom" selected={@cycle == "custom"}>Eigene Dauer …</option>
        </select>
        <span class="label-text-alt mt-1 opacity-60">
          Abstand zwischen Bestätigung und nächster Mahnung.
        </span>
      </label>

      <label :if={@cycle == "custom"} class="form-control">
        <span class="label-text mb-1">Eigene Dauer (Tage)</span>
        <input
          type="number"
          name="task[custom_days]"
          value={@custom_days}
          min="1"
          max="3650"
          required
          class="input input-bordered w-full"
        />
      </label>
    </div>
    """
  end

  # ---- Parse helpers ----

  def default_first_fire do
    DateTime.utc_now()
    |> DateTime.add(60 * 60, :second)
    |> DateTime.shift_zone!(app_timezone())
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  def datetime_to_local_input(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(app_timezone())
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  def datetime_to_local_input(_), do: default_first_fire()

  def validate_description(desc) when is_binary(desc) do
    trimmed = String.trim(desc)

    cond do
      trimmed == "" -> {:error, "Beschreibung darf nicht leer sein."}
      String.length(trimmed) > 140 -> {:error, "Beschreibung max. 140 Zeichen."}
      true -> {:ok, trimmed}
    end
  end

  def validate_description(_), do: {:error, "Beschreibung fehlt."}

  def parse_local_datetime(str) when is_binary(str) do
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

  def parse_local_datetime(_), do: {:error, "Datum fehlt."}

  defp ensure_seconds(str) do
    case String.split(str, "T") do
      [_, time] when byte_size(time) == 5 -> str <> ":00"
      _ -> str
    end
  end

  def default_topic do
    System.get_env("NTFY_TOPIC") ||
      Application.get_env(:noisy_chirp, :default_ntfy_topic) ||
      "noisy-chirp-default"
  end

  def app_timezone do
    Application.get_env(:noisy_chirp, :timezone, "Europe/Berlin")
  end
end
