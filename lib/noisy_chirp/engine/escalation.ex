defmodule Chirp.Engine.Escalation do
  @moduledoc """
  Pure functions describing the chirp escalation.

  Given the current `reminder_count` (n >= 1) compute the next gap, the
  ntfy priority, the tag set, the text and a notification title.
  """

  @first_gap_ms 12 * 60 * 60 * 1000
  @min_gap_ms 5 * 60 * 1000

  @doc "Minimum (floor) gap between chirps, in ms."
  def min_gap_ms, do: @min_gap_ms

  @doc "Initial gap (between first and second chirp), in ms."
  def first_gap_ms, do: @first_gap_ms

  @doc """
  Returns the milliseconds until the next chirp for the given count.

  `gap(1)` is the gap from the first chirp to the second. Floored at
  `min_gap_ms/0`.
  """
  def gap(n) when is_integer(n) and n >= 1 do
    raw = div(@first_gap_ms, pow2(n - 1))
    max(@min_gap_ms, raw)
  end

  defp pow2(k) when k <= 0, do: 1
  defp pow2(k), do: :erlang.bsl(1, k)

  @doc "ntfy priority for the n-th chirp, 1..5."
  def priority(n) when is_integer(n) and n >= 1 do
    min(5, 2 + n)
  end

  @doc "ntfy tag list, escalating with n."
  def tags(n) when is_integer(n) and n >= 1 do
    cond do
      n <= 1 -> ["bell"]
      n <= 3 -> ["bell", "warning"]
      n <= 5 -> ["rotating_light", "warning"]
      true -> ["rotating_light", "skull", "scream"]
    end
  end

  @doc "Short notification title."
  def title(n) when n >= 6, do: "chirp chirp chirp"
  def title(n) when n >= 4, do: "🚨 JETZT"
  def title(n) when n >= 2, do: "Erinnerung"
  def title(_), do: "noisy-chirp"

  @doc """
  Renders the German escalation text. Takes the task's description (e.g.
  "Zahnbürstenkopf wechseln") and the chirp count.
  """
  def text(1, desc), do: "🐦 #{desc}?"
  def text(2, desc), do: "Hey. #{desc}. Du weißt schon."
  def text(3, desc), do: "Zum dritten Mal: #{desc}. 🙃"
  def text(4, desc), do: "#{desc}. JETZT."
  def text(5, desc), do: "Ich höre nicht auf. #{desc}. 🚨"
  def text(n, desc) when n >= 6, do: "chirp chirp chirp #{desc} 💀"

  @doc """
  Bundles all dispatch fields for a given chirp count.
  """
  def render(n, description) do
    %{
      priority: priority(n),
      tags: tags(n),
      title: title(n),
      message: text(n, description)
    }
  end
end
