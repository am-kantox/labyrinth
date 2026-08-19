defmodule Labyrinth.Schema.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    field :name, :string
    field :width, :integer, default: 10
    field :height, :integer, default: 10
    field :status, :string, default: "lobby"
    field :map_data, :map
    field :settings, :map
    field :winner_name, :string

    has_many :turns, Labyrinth.Schema.Turn
    has_many :post_its, Labyrinth.Schema.PostIt

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:id, :name, :width, :height, :status, :map_data, :settings, :winner_name])
    |> validate_required([:name, :map_data, :settings])
  end
end
