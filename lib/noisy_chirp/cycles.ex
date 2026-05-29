defmodule Chirp.Cycles do
  @moduledoc """
  Single source of truth for the reminder cycle presets the admin form
  offers. A cycle is identified by its key (string) and resolves to a
  duration in seconds.

  The special key `"custom"` doesn't resolve directly — pair it with a
  user-supplied days value via `from_input/2`.
  """

  @presets [
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

  @max_days 3650

  def presets, do: @presets

  @doc "All keys including the custom marker."
  def all_keys, do: Enum.map(@presets, fn {k, _, _} -> k end) ++ ["custom"]

  @doc """
  Resolves a form submission (cycle key + optional days) to seconds.

  Returns `{:ok, seconds}` or `{:error, message}`.
  """
  def from_input("custom", days_str) when is_binary(days_str) do
    case Integer.parse(days_str) do
      {n, ""} when n >= 1 and n <= @max_days ->
        {:ok, n * 86_400}

      _ ->
        {:error, "Eigene Dauer: 1 bis #{@max_days} Tage."}
    end
  end

  def from_input("custom", _), do: {:error, "Eigene Dauer fehlt."}

  def from_input(key, _days) when is_binary(key) do
    case Enum.find(@presets, fn {k, _, _} -> k == key end) do
      {_, _, seconds} -> {:ok, seconds}
      nil -> {:error, "Unbekannter Zyklus."}
    end
  end

  @doc """
  Reverse lookup: from an existing `base_interval_seconds`, find which
  preset (if any) matches — used to pre-select the form on edit.

  Returns `{:preset, key}` if a preset matches, `{:custom, days}`
  otherwise.
  """
  def from_seconds(seconds) when is_integer(seconds) do
    case Enum.find(@presets, fn {_, _, s} -> s == seconds end) do
      {key, _, _} -> {:preset, key}
      nil -> {:custom, max(div(seconds, 86_400), 1)}
    end
  end

  @doc "Human-readable label for an existing interval."
  def label(seconds) when is_integer(seconds) do
    case from_seconds(seconds) do
      {:preset, key} ->
        @presets
        |> Enum.find(fn {k, _, _} -> k == key end)
        |> elem(1)

      {:custom, days} ->
        "Alle #{days} Tage"
    end
  end
end
