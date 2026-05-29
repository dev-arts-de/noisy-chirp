ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Chirp.Repo, :manual)

# Boot the in-memory test notifier so tests can publish without hitting ntfy.
Chirp.TestNotifier.ensure_started()
