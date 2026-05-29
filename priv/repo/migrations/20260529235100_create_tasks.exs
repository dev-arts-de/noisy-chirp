defmodule Chirp.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :token, :string, null: false
      add :name, :string, null: false
      add :verb, :string, null: false
      add :base_interval_seconds, :integer, null: false
      add :ntfy_topic, :string, null: false
      add :state, :string, null: false, default: "calm"
      add :reminder_count, :integer, null: false, default: 0
      add :next_fire_at, :utc_datetime, null: false
      add :last_confirmed_at, :utc_datetime
      add :lie_score, :integer, null: false, default: 0
      add :last_sent_at, :utc_datetime
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tasks, [:token])
    create index(:tasks, [:active])
    create index(:tasks, [:next_fire_at])
  end
end
