import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :noisy_chirp, Chirp.Repo,
  database: Path.expand("../noisy_chirp_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :noisy_chirp, ChirpWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ffEsQ5ps1NNG2l+VGmI8luvMUSM0lps660q1rYMRQSRmjdGPNExDS5ZaI53nqYDL",
  server: false

# Use the in-memory test notifier instead of hitting ntfy.sh in tests.
config :noisy_chirp,
  notifier: Chirp.TestNotifier,
  engine_autostart: false,
  ntfy_base_url: "http://test.invalid",
  public_base_url: "http://test.invalid",
  chirp_writer: Chirp.AI.Disabled,
  admin_password: "test"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
