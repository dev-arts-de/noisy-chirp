# Idempotent seeds. Runs on container boot when SEED_ON_BOOT=true.
#
#     mix run priv/repo/seeds.exs

alias Chirp.Reminders

if Reminders.list_tasks() == [] do
  topic = System.get_env("NTFY_TOPIC", "noisy-chirp-DEINGEHEIMESTOPIC")

  {:ok, _task} =
    Reminders.create_task(%{
      name: "Zahnbürstenkopf wechseln",
      verb: "",
      base_interval_seconds: 60 * 86_400,
      ntfy_topic: topic,
      next_fire_at:
        DateTime.utc_now()
        |> DateTime.add(60, :second)
        |> DateTime.truncate(:second)
    })

  IO.puts("Seeded default task with ntfy topic: #{topic}")
else
  IO.puts("Tasks already present, skipping seeds.")
end
