defmodule Chirp.AI do
  @moduledoc """
  Dispatcher for AI-generated notification texts. The actual implementation
  is configurable via `:noisy_chirp, :chirp_writer` (defaults to
  `Chirp.AI.Anthropic`). Tests swap in a stub.
  """

  @doc """
  Returns `{:ok, text}` with an AI-written chirp text in the bird voice,
  or `{:error, reason}` if generation failed.

  Callers should fall back to a static template on error so notifications
  never block on API issues.
  """
  def write(description, n) when is_binary(description) and is_integer(n) and n >= 1 do
    impl().write(description, n)
  rescue
    e -> {:error, e}
  end

  defp impl do
    Application.get_env(:noisy_chirp, :chirp_writer, Chirp.AI.Anthropic)
  end
end
