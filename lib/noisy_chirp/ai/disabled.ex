defmodule Chirp.AI.Disabled do
  @moduledoc """
  AI writer that's deliberately turned off — every call returns
  `{:error, :disabled}` so the engine falls back to static bird-themed
  templates. Useful when you want zero external/local dependencies.
  """

  def write(_description, _n), do: {:error, :disabled}
end
