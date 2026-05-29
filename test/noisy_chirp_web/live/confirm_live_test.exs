defmodule ChirpWeb.ConfirmLiveTest do
  use ChirpWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Chirp.Reminders

  defp seed_task!(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Zahnbürstenkopf",
          verb: "gewechselt",
          base_interval_seconds: 60,
          ntfy_topic: "test-topic",
          next_fire_at:
            DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
        },
        overrides
      )

    {:ok, task} = Reminders.create_task(attrs)
    task
  end

  test "shows the question and the checkbox", %{conn: conn} do
    task = seed_task!()

    {:ok, _view, html} = live(conn, ~p"/t/#{task.token}")

    assert html =~ "Zahnbürstenkopf"
    assert html =~ "gewechselt"
    assert html =~ "Bestätigen"
  end

  test "404-ish view for unknown token", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/t/does-not-exist")
    assert html =~ "Token unbekannt"
  end

  test "confirming releases the task to calm", %{conn: conn} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    task = seed_task!()

    {:ok, _} =
      task
      |> Ecto.Changeset.change(%{
        last_sent_at: DateTime.add(now, -120, :second),
        reminder_count: 2,
        state: "nagging"
      })
      |> Chirp.Repo.update()

    {:ok, view, _} = live(conn, ~p"/t/#{task.token}")

    rendered =
      view
      |> element("form")
      |> render_submit(%{"ack" => "on"})

    assert rendered =~ "Erledigt"

    reloaded = Reminders.get_task_by_token(task.token)
    assert reloaded.state == "calm"
    assert reloaded.reminder_count == 0
  end
end
