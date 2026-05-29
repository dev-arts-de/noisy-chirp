defmodule Chirp.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :priority, :integer
      add :reaction_latency_ms, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:events, [:task_id])
    create index(:events, [:kind])
  end
end
