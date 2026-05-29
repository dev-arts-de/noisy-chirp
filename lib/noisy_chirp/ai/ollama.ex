defmodule Chirp.AI.Ollama do
  @moduledoc """
  Local small-model adapter via Ollama's HTTP API (`/api/generate`).

  Same contract as `Chirp.AI.Anthropic`: returns `{:ok, text}` or
  `{:error, reason}`. The caller falls back to a static template on error.

  Config:
    * `:noisy_chirp, :ollama_base_url` — e.g. `"http://ollama:11434"`
    * `:noisy_chirp, :ollama_model` — e.g. `"qwen2.5:1.5b"`
    * `:noisy_chirp, :ollama_timeout_ms` — default 8000 (CPU inference is slow)
  """

  require Logger

  @default_base_url "http://localhost:11434"
  @default_model "qwen2.5:1.5b"
  @default_timeout_ms 8_000

  @system_prompt """
  Du bist Chirp, ein kleiner, neurotisch zwitschernder Vogel, der auf dem Display des Nutzers sitzt und ihn pickt, damit er etwas Wichtiges nicht vergisst. Du schreibst kurze deutsche Push-Notifications für die App "noisy-chirp".

  Regeln:
  - Immer in der Vogel-Rolle: pickend, piepsend, hüpfend, mit gesträubten Federn.
  - Vogel-Geräusche einstreuen: *piep*, *chirp*, *pickpickpick*, *trill*, *flatter*, *sträubt Federn*.
  - Deutsch, Du-Form, locker, leicht passiv-aggressiv.
  - Maximal ~140 Zeichen, eine Notification, eine Zeile.
  - Die Aufgabe direkt im Text nennen.
  - Keine Begrüßung, keine Erklärung, keine Anführungszeichen, kein JSON.

  Eskalations-Stufen (Erinnerung Nummer n):
  1: freundlich, neugierig, einmal piep
  2: ungeduldig, kurzes Picken
  3: nervig, betont das dritte Mal
  4: dringend, gesträubte Federn, kurzer Befehl
  5: panisch, Flügelflattern, Großbuchstaben okay
  6+: völlig hysterisch, am Rande des Nervenzusammenbruchs

  Output: NUR der reine Notification-Text.
  """

  def write(description, n) when is_binary(description) and is_integer(n) and n >= 1 do
    body = %{
      model: model(),
      system: @system_prompt,
      prompt: "Aufgabe: #{description}\nErinnerung Nummer: #{n}",
      stream: false,
      options: %{
        num_predict: 160,
        temperature: 0.8,
        top_p: 0.9
      }
    }

    url = String.trim_trailing(base_url(), "/") <> "/api/generate"

    case Req.post(url, json: body, retry: false, receive_timeout: timeout()) do
      {:ok, %Req.Response{status: 200, body: %{"response" => text}}} when is_binary(text) ->
        {:ok, normalize(text)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("ollama non-2xx (#{status}): #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("ollama call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp normalize(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.trim("\"")
    |> String.trim("'")
    |> truncate(220)
  end

  defp truncate(s, max) do
    if String.length(s) > max do
      String.slice(s, 0, max - 1) <> "…"
    else
      s
    end
  end

  defp base_url, do: Application.get_env(:noisy_chirp, :ollama_base_url, @default_base_url)
  defp model, do: Application.get_env(:noisy_chirp, :ollama_model, @default_model)

  defp timeout do
    Application.get_env(:noisy_chirp, :ollama_timeout_ms, @default_timeout_ms)
  end
end
