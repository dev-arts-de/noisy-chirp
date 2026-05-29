# Script for populating the database. Idempotent: only inserts the default
# Zahnbürstenkopf task when there is no task yet.
#
#     mix run priv/repo/seeds.exs

alias Chirp.Reminders

if Reminders.list_tasks() == [] do
  topic = System.get_env("NTFY_TOPIC", "noisy-chirp-DEINGEHEIMESTOPIC")

  {:ok, _task} =
    Reminders.create_task(%{
      name: "Zahnbürstenkopf",
      verb: "gewechselt",
      # ~60 Tage
      base_interval_seconds: 5_184_000,
      ntfy_topic: topic,
      # erster Schuss in 1 min zum Testen
      next_fire_at:
        DateTime.utc_now()
        |> DateTime.add(60, :second)
        |> DateTime.truncate(:second)
    })

  IO.puts("Seeded default task with ntfy topic: #{topic}")
else
  IO.puts("Tasks already present, skipping seeds.")
end
