defmodule Chirp.Engine do
  @moduledoc """
  Public API for the OTP engine: starts/wakes per-task servers.
  """

  alias Chirp.Reminders
  alias Chirp.Reminders.Task, as: ReminderTask
  alias Chirp.Engine.{TaskServer, Registry}

  @supervisor Chirp.Engine.Supervisor

  @doc "Start a TaskServer for every active task. Called on app boot."
  def start_all do
    Reminders.list_active_tasks()
    |> Enum.map(&start_task/1)
  end

  def start_task(%ReminderTask{id: id, active: true} = _task) do
    if Application.get_env(:noisy_chirp, :engine_autostart, true) do
      case DynamicSupervisor.start_child(@supervisor, {TaskServer, id}) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        err -> err
      end
    else
      {:ok, :disabled}
    end
  end

  def start_task(%ReminderTask{active: false}), do: {:error, :inactive}

  def stop_task(task_id) when is_integer(task_id) do
    case Registry.whereis(task_id) do
      :undefined -> :ignored
      pid -> DynamicSupervisor.terminate_child(@supervisor, pid)
    end
  end

  def wake(%ReminderTask{id: id}), do: wake(id)

  def wake(task_id) when is_integer(task_id) do
    if Application.get_env(:noisy_chirp, :engine_autostart, true) do
      TaskServer.wake(task_id)
    else
      :ignored
    end
  end

  def reschedule(%ReminderTask{} = task), do: wake(task)
end
