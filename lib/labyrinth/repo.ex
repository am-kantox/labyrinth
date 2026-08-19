defmodule Labyrinth.Repo do
  use Ecto.Repo,
    otp_app: :labyrinth,
    adapter: Ecto.Adapters.Postgres
end
