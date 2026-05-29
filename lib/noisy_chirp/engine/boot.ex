defmodule Chirp.Engine.Boot do
  @moduledoc """
  Tiny worker that, once started, asks the engine to spin up a `TaskServer`
  for every active task. Disabled in test (sandbox would deadlock on first
  query).
  """

  use Task, restart: :transient

  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    if seed_on_boot?() do
      try do
        Chirp.Release.seed()
      rescue
        e ->
          require Logger
          Logger.error("seed-on-boot failed: #{Exception.message(e)}")
      end
    end

    if enabled?() do
      try do
        Chirp.Engine.start_all()
      rescue
        e ->
          require Logger
          Logger.error("engine boot failed: #{Exception.message(e)}")
      end
    end

    :ok
  end

  defp seed_on_boot? do
    Application.get_env(:noisy_chirp, :seed_on_boot, false)
  end

  defp enabled? do
    Application.get_env(:noisy_chirp, :engine_autostart, true)
  end
end
