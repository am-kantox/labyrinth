defmodule Labyrinth.Schema.PostIt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_its" do
    field :player_id, :string
    field :title, :string, default: "Note"
    field :color, :string, default: "yellow"
    field :x_pos, :integer, default: 20
    field :y_pos, :integer, default: 20
    field :width, :integer, default: 260
    field :height, :integer, default: 260
    field :text, :string, default: ""
    field :grid_marks, :map, default: %{}
    field :is_stuck, :boolean, default: false

    belongs_to :game, Labyrinth.Schema.Game, type: :binary_id

    timestamps()
  end

  def changeset(post_it, attrs) do
    post_it
    |> cast(attrs, [
      :game_id,
      :player_id,
      :title,
      :color,
      :x_pos,
      :y_pos,
      :width,
      :height,
      :text,
      :grid_marks,
      :is_stuck
    ])
    |> validate_required([:game_id, :player_id])
  end
end
