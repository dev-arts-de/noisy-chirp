defmodule Chirp.RemindersTest do
  use Chirp.DataCase, async: true

  alias Chirp.Reminders
  alias Chirp.Reminders.Task, as: ReminderTask

  defp build_attrs(overrides) do
    %{
      name: "Zahnbürstenkopf",
      verb: "gewechselt",
      base_interval_seconds: 60,
      ntfy_topic: "test-topic",
      next_fire_at: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
    }
    |> Map.merge(overrides)
  end

  defp create_task!(attrs \\ %{}) do
    {:ok, task} = Reminders.create_task(build_attrs(attrs))
    task
  end

  describe "lie_delta/2" do
    test "very fast (<8s) adds 30+10 = 40, plus first-reminder bonus +10" do
      # latency 5_000 ms, reminder_count 1 → +30 (<8s) +10 (<30s) +10 (n<=1 & <15s) = 50
      assert Reminders.lie_delta(5_000, 1) == 50
    end

    test "instant (<8s) on later reminder still bumps but no first-shot bonus" do
      assert Reminders.lie_delta(5_000, 5) == 40
    end

    test "1–15 min latency gives -15 honesty discount" do
      assert Reminders.lie_delta(120_000, 3) == -15
    end

    test "no last_sent_at → 0" do
      assert Reminders.lie_delta(nil, 1) == 0
    end
  end

  describe "create_task/1" do
    test "auto-generates a unique token" do
      task = create_task!()
      assert is_binary(task.token)
      assert String.length(task.token) >= 24
    end
  end

  describe "confirm_task/1" do
    test "releases when score stays under threshold" do
      task = create_task!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      task =
        task
        |> Ecto.Changeset.change(%{
          last_sent_at: DateTime.add(now, -120, :second),
          reminder_count: 2,
          state: "nagging"
        })
        |> Chirp.Repo.update!()

      assert {:ok, :calm, updated} = Reminders.confirm_task(task)
      assert updated.state == "calm"
      assert updated.reminder_count == 0
      assert DateTime.diff(updated.next_fire_at, now, :second) >= task.base_interval_seconds - 5
    end

    test "tipps over into awaiting_oath when score >= 60" do
      task = create_task!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 3 quick-confirms simulated by pre-loading score to 20, then a fast tap.
      task =
        task
        |> Ecto.Changeset.change(%{
          last_sent_at: DateTime.add(now, -3, :second),
          reminder_count: 1,
          state: "nagging",
          lie_score: 20
        })
        |> Chirp.Repo.update!()

      assert {:ok, :awaiting_oath, updated} = Reminders.confirm_task(task)
      assert updated.state == "awaiting_oath"
      assert updated.lie_score >= 60
    end
  end

  describe "swear_task/1" do
    test "halves the lie score and releases back to calm" do
      task = create_task!()

      task =
        task
        |> Ecto.Changeset.change(%{
          state: "awaiting_oath",
          lie_score: 80
        })
        |> Chirp.Repo.update!()

      assert {:ok, updated} = Reminders.swear_task(task)
      assert updated.state == "calm"
      assert updated.lie_score == 40
      assert updated.reminder_count == 0
    end
  end

  describe "register_sent/2" do
    test "sets last_sent_at and creates a 'sent' event" do
      task = create_task!()
      updated = Reminders.register_sent(task, 4)
      assert %ReminderTask{} = updated
      assert updated.last_sent_at

      [event] = Reminders.list_events_for(updated.id)
      assert event.kind == "sent"
      assert event.priority == 4
    end
  end
end
