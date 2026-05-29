defmodule Chirp.Engine.Registry do
  @moduledoc """
  Lookup helper for the engine `Registry` (keyed by `task_id`).
  """

  def whereis(task_id) when is_integer(task_id) do
    case Elixir.Registry.lookup(__MODULE__, task_id) do
      [{pid, _}] -> pid
      [] -> :undefined
    end
  end
end
