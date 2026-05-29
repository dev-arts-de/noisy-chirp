defmodule Chirp.Reminders.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(calm nagging awaiting_oath)

  schema "tasks" do
    field :token, :string
    field :name, :string
    field :verb, :string
    field :base_interval_seconds, :integer
    field :ntfy_topic, :string
    field :state, :string, default: "calm"
    field :reminder_count, :integer, default: 0
    field :next_fire_at, :utc_datetime
    field :last_confirmed_at, :utc_datetime
    field :lie_score, :integer, default: 0
    field :last_sent_at, :utc_datetime
    field :active, :boolean, default: true

    has_many :events, Chirp.Reminders.Event

    timestamps(type: :utc_datetime)
  end

  @castable ~w(name verb base_interval_seconds ntfy_topic state reminder_count
               next_fire_at last_confirmed_at lie_score last_sent_at active token)a

  def changeset(task, attrs) do
    task
    |> cast(attrs, @castable)
    |> ensure_token()
    |> validate_required([:name, :verb, :base_interval_seconds, :ntfy_topic, :next_fire_at])
    |> validate_inclusion(:state, @states)
    |> validate_number(:base_interval_seconds, greater_than: 0)
    |> validate_number(:lie_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:reminder_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:token)
  end

  defp ensure_token(changeset) do
    case get_field(changeset, :token) do
      nil -> put_change(changeset, :token, generate_token())
      "" -> put_change(changeset, :token, generate_token())
      _ -> changeset
    end
  end

  def generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end
end
