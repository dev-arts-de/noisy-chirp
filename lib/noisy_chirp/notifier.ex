defmodule Chirp.Notifier do
  @moduledoc """
  Behaviour for outbound notifications. The active implementation is read at
  call time from application config (`:noisy_chirp, :notifier`), defaulting to
  `Chirp.Ntfy`. Tests can swap in a stub.
  """

  @callback publish(topic :: String.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc "Publish via the configured notifier module."
  def publish(topic, opts) do
    impl().publish(topic, opts)
  end

  defp impl do
    Application.get_env(:noisy_chirp, :notifier, Chirp.Ntfy)
  end
end
