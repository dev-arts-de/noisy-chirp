defmodule Chirp.Reminders.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(sent confirmed oath_sent sworn)

  schema "events" do
    field :kind, :string
    field :priority, :integer
    field :reaction_latency_ms, :integer

    belongs_to :task, Chirp.Reminders.Task

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:task_id, :kind, :priority, :reaction_latency_ms])
    |> validate_required([:task_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> assoc_constraint(:task)
  end
end
