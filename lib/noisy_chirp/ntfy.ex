defmodule Chirp.Ntfy do
  @moduledoc """
  ntfy.sh client. `POST <base_url>/<topic>` with the message in the body and
  metadata in headers (Title, Priority, Tags, Click, Actions).
  """

  @behaviour Chirp.Notifier

  require Logger

  @impl true
  def publish(topic, opts) when is_binary(topic) and is_list(opts) do
    base = Application.fetch_env!(:noisy_chirp, :ntfy_base_url)
    url = "#{String.trim_trailing(base, "/")}/#{topic}"

    headers =
      []
      |> put_header("Title", opts[:title])
      |> put_header("Priority", opts[:priority] && to_string(opts[:priority]))
      |> put_header("Tags", join_tags(opts[:tags]))
      |> put_header("Click", opts[:click])
      |> put_header("Actions", opts[:actions])

    body = opts[:message] || ""

    case Req.post(url, headers: headers, body: body, retry: false, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        {:ok, resp}

      {:ok, %Req.Response{status: status} = resp} ->
        Logger.warning("ntfy non-2xx for topic=#{topic}: #{status}")
        {:error, resp}

      {:error, reason} = err ->
        Logger.warning("ntfy publish failed for topic=#{topic}: #{inspect(reason)}")
        err
    end
  end

  defp put_header(headers, _key, nil), do: headers
  defp put_header(headers, _key, ""), do: headers
  defp put_header(headers, key, value), do: [{key, value} | headers]

  defp join_tags(nil), do: nil
  defp join_tags([]), do: nil
  defp join_tags(tags) when is_list(tags), do: Enum.join(tags, ",")
end
