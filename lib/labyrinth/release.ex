defmodule Labyrinth.Release do
  @moduledoc """
  Ecto migration tasks callable from a compiled Mix release, where `Mix`
  itself isn't available at runtime (`mix ecto.migrate` doesn't exist in a
  release).

  Invoked automatically on every restart via `ExecStartPre` in
  `systemd/labyrinth.service`:

      bin/labyrinth eval "Labyrinth.Release.migrate()"

  Combined with `ops/scripts/deploy-release.sh` tolerating a failed
  restart (falling through into its health-check retry loop instead of
  hard-exiting), a migration failure here causes the same
  rollback-to-previous-release behavior as any other unhealthy restart.
  """

  @app :labyrinth

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
