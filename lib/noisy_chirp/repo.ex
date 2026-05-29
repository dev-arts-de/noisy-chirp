defmodule Chirp.Repo do
  use Ecto.Repo,
    otp_app: :noisy_chirp,
    adapter: Ecto.Adapters.SQLite3
end
