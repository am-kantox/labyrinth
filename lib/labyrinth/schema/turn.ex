defmodule Labyrinth.Schema.Turn do
  use Ecto.Schema
  import Ecto.Changeset

  schema "turns" do
    field :turn_number, :integer
    field :player_id, :string
    field :player_name, :string
    field :action_type, :string
    field :direction, :string
    field :result, :string
    field :sound_effects, {:array, :string}, default: []
    field :position_before, :map
    field :position_after, :map

    belongs_to :game, Labyrinth.Schema.Game, type: :binary_id

    timestamps()
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [
      :game_id,
      :turn_number,
      :player_id,
      :player_name,
      :action_type,
      :direction,
      :result,
      :sound_effects,
      :position_before,
      :position_after
    ])
    |> validate_required([
      :game_id,
      :turn_number,
      :player_id,
      :player_name,
      :action_type,
      :result
    ])
  end
end
