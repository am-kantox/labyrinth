defmodule Labyrinth.Repo.Migrations.AddIsStuckToPostIts do
  use Ecto.Migration

  def change do
    alter table(:post_its) do
      add :is_stuck, :boolean, default: false
    end
  end
end
