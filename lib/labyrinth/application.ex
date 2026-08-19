defmodule Labyrinth.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LabyrinthWeb.Telemetry,
      Labyrinth.Repo,
      {DNSCluster, query: Application.get_env(:labyrinth, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Labyrinth.PubSub},
      Labyrinth.Presence,
      {Registry, keys: :unique, name: Labyrinth.GameRegistry},
      {DynamicSupervisor, name: Labyrinth.GameSupervisor, strategy: :one_for_one},
      LabyrinthWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Labyrinth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LabyrinthWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
