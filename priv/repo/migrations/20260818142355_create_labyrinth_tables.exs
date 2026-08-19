defmodule Labyrinth.Repo.Migrations.CreateLabyrinthTables do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :width, :integer, default: 10
      add :height, :integer, default: 10
      # lobby, in_progress, finished
      add :status, :string, default: "lobby"
      add :map_data, :map, null: false
      add :settings, :map, null: false
      add :winner_name, :string
      timestamps()
    end

    create table(:turns) do
      add :game_id, references(:games, type: :uuid, on_delete: :delete_all), null: false
      add :turn_number, :integer, null: false
      add :player_id, :string, null: false
      add :player_name, :string, null: false
      # move, shoot, pass
      add :action_type, :string, null: false
      add :direction, :string
      # moved, wall, pit, teleport, treasure, escaped, shot_hit, shot_miss, eliminated
      add :result, :string, null: false
      add :sound_effects, {:array, :string}, default: []
      add :position_before, :map
      add :position_after, :map
      timestamps()
    end

    create index(:turns, [:game_id])
    create index(:turns, [:game_id, :turn_number])

    create table(:post_its) do
      add :game_id, references(:games, type: :uuid, on_delete: :delete_all), null: false
      add :player_id, :string, null: false
      add :title, :string, default: "Note"
      add :color, :string, default: "yellow"
      add :x_pos, :integer, default: 20
      add :y_pos, :integer, default: 20
      add :width, :integer, default: 260
      add :height, :integer, default: 260
      add :text, :text, default: ""
      add :grid_marks, :map, default: "{}"
      timestamps()
    end

    create index(:post_its, [:game_id, :player_id])
  end
end
