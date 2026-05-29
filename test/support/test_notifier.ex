defmodule Chirp.TestNotifier do
  @moduledoc """
  In-memory notifier used in tests. Stores every call in an Agent so tests
  can assert against it.
  """
  @behaviour Chirp.Notifier

  @agent __MODULE__

  def start_link do
    Agent.start_link(fn -> [] end, name: @agent)
  end

  def ensure_started do
    case Process.whereis(@agent) do
      nil -> start_link()
      _ -> :ok
    end
  end

  def reset do
    ensure_started()
    Agent.update(@agent, fn _ -> [] end)
  end

  def calls do
    ensure_started()
    Agent.get(@agent, &Enum.reverse/1)
  end

  @impl true
  def publish(topic, opts) do
    ensure_started()
    Agent.update(@agent, fn list -> [{topic, opts} | list] end)
    {:ok, %{topic: topic, opts: opts}}
  end
end
