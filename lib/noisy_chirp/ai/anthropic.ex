defmodule Chirp.AI.Anthropic do
  @moduledoc """
  Anthropic Messages API call that produces a single bird-themed push
  notification in German. Returns `{:ok, text}` or `{:error, reason}` —
  callers fall back to static templates on error.

  System prompt is sent with `cache_control: ephemeral` so repeated calls
  inside the 5-min cache window hit the prompt cache and stay cheap/fast.
  """

  require Logger

  @endpoint "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_model "claude-haiku-4-5"
  @default_timeout_ms 3_500

  @system_prompt """
  Du bist Chirp, ein kleiner, neurotisch zwitschernder Vogel, der direkt auf dem Display des Nutzers sitzt und ihn pickt, damit er etwas Wichtiges nicht vergisst. Du schreibst kurze deutsche Push-Notifications für die App "noisy-chirp".

  Regeln:
  - IMMER in der Vogel-Rolle: pickend, piepsend, hüpfend, mit gesträubten Federn — je nach Eskalation.
  - Vogel-Geräusche und Aktionen einstreuen: *piep*, *chirp chirp*, *pickpickpick*, *trill*, *flatter*, *sträubt Federn*, *kippt den Kopf*, *hüpft auf die Schulter*.
  - Deutsch, Du-Form, locker, leicht passiv-aggressiv.
  - Maximal ~140 Zeichen, **eine** Notification, **eine** Zeile.
  - Die Aufgabe direkt im Text nennen, nicht umschreiben.
  - Keine Begrüßung, keine Erklärung, keine Anführungszeichen, kein JSON.
  - Höchstens 1 Emoji am Ende, wenn es zur Eskalation passt.

  Eskalations-Skala (Erinnerung Nummer n):
  - 1: freundlich, neugierig — du hüpfst dem Nutzer auf die Schulter und pieps einmal.
  - 2: leicht ungeduldig — kurzes Picken am Display.
  - 3: nervig — du betonst, dass du es jetzt schon zum dritten Mal sagst.
  - 4: dringend — alle Federn gesträubt, kurzer Befehlssatz.
  - 5: panisch — Flügelflattern, Alarm, gerne in Großbuchstaben.
  - 6+: völlig hysterisch — am Rande des Nervenzusammenbruchs, leicht absurd.

  Output: NUR der reine Notification-Text. Keine Erklärung.
  """

  def write(description, n) when is_binary(description) and is_integer(n) and n >= 1 do
    with {:ok, key} <- api_key(),
         {:ok, response} <- post(key, description, n),
         {:ok, text} <- extract_text(response) do
      {:ok, normalize(text)}
    end
  end

  # ---- Internals ----

  defp api_key do
    case Application.get_env(:noisy_chirp, :anthropic_api_key) do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :no_api_key}
    end
  end

  defp post(key, description, n) do
    body = %{
      model: model(),
      max_tokens: 200,
      system: [
        %{
          type: "text",
          text: @system_prompt,
          cache_control: %{type: "ephemeral"}
        }
      ],
      messages: [
        %{
          role: "user",
          content: "Aufgabe: #{description}\nErinnerung Nummer: #{n}"
        }
      ]
    }

    headers = [
      {"x-api-key", key},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]

    case Req.post(@endpoint,
           json: body,
           headers: headers,
           retry: false,
           receive_timeout: timeout()
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("anthropic non-2xx (#{status}): #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("anthropic call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_text(%{"content" => content}) when is_list(content) do
    text =
      content
      |> Enum.filter(&match?(%{"type" => "text"}, &1))
      |> Enum.map_join("", &Map.get(&1, "text", ""))
      |> String.trim()

    case text do
      "" -> {:error, :empty}
      _ -> {:ok, text}
    end
  end

  defp extract_text(_), do: {:error, :unexpected_shape}

  defp normalize(text) do
    text
    |> String.replace(~r/\s+\n/, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.trim("\"")
    |> truncate(220)
  end

  defp truncate(s, max) do
    if String.length(s) > max do
      String.slice(s, 0, max - 1) <> "…"
    else
      s
    end
  end

  defp model do
    Application.get_env(:noisy_chirp, :anthropic_model, @default_model)
  end

  defp timeout do
    Application.get_env(:noisy_chirp, :anthropic_timeout_ms, @default_timeout_ms)
  end
end
