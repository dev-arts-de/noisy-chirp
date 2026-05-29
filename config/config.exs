# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :noisy_chirp,
  namespace: Chirp,
  ecto_repos: [Chirp.Repo],
  generators: [timestamp_type: :utc_datetime],
  ntfy_base_url: "https://ntfy.sh",
  public_base_url: "http://localhost:4000",
  notifier: Chirp.Ntfy,
  chirp_writer: Chirp.AI.Anthropic,
  anthropic_model: "claude-haiku-4-5"

# Configure the endpoint
config :noisy_chirp, ChirpWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ChirpWeb.ErrorHTML, json: ChirpWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Chirp.PubSub,
  live_view: [signing_salt: "aMEXi+AD"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  noisy_chirp: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  noisy_chirp: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Use Tzdata as the timezone database so DateTime can shift across zones.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
