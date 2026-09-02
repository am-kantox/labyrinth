defmodule Labyrinth.Ops.DeploymentConfigTest do
  @moduledoc """
  The ops artifacts (`ops/scripts/deploy-release.sh`, `rel/overlays/bin/server`,
  `systemd/labyrinth.*`, `.github/workflows/deploy.yml`) are plain text, not
  Elixir code exercised by the app's own test suite. These tests assert
  their content invariants directly so a future edit can't silently regress
  the loopback binding, the automatic migration hook, or the deploy
  workflow's version pins without a test failing.
  """

  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  describe "rel/overlays/bin/server" do
    setup do
      {:ok, path: Path.join(@root, "rel/overlays/bin/server")}
    end

    test "sets PHX_SERVER and execs the release start script", %{path: path} do
      content = File.read!(path)
      assert content =~ "PHX_SERVER=true"
      assert content =~ "exec bin/labyrinth start"
    end

    test "is executable", %{path: path} do
      import Bitwise

      assert (File.stat!(path).mode &&& 0o111) != 0
    end
  end

  describe "systemd/labyrinth.service" do
    setup do
      {:ok, content: File.read!(Path.join(@root, "systemd/labyrinth.service"))}
    end

    test "loads an EnvironmentFile, restarts on failure and drops privileges", %{
      content: content
    } do
      assert content =~ "EnvironmentFile=/etc/labyrinth/env"
      assert content =~ "Restart=on-failure"
      assert content =~ "User=labyrinth"
      assert content =~ "NoNewPrivileges=true"
      refute content =~ "User=root"
    end

    test "waits on postgresql", %{content: content} do
      assert content =~ "postgresql.service"
    end

    test "runs ecto migrations automatically before every start", %{content: content} do
      assert content =~ ~s(ExecStartPre=/opt/labyrinth/current/bin/labyrinth eval)
      assert content =~ "Labyrinth.Release.migrate()"
    end
  end

  describe "systemd/labyrinth.env.example" do
    setup do
      {:ok, content: File.read!(Path.join(@root, "systemd/labyrinth.env.example"))}
    end

    test "documents required vars without a real secret value", %{content: content} do
      assert content =~ "CHANGE_ME"
      refute content =~ ~r/SECRET_KEY_BASE=[A-Za-z0-9+\/]{20,}/
    end

    test "documents the real prod port", %{content: content} do
      assert content =~ "PORT=3060"
    end
  end

  describe ".github/workflows/deploy.yml" do
    setup do
      {:ok, content: File.read!(Path.join(@root, ".github/workflows/deploy.yml"))}
    end

    test "triggers on pushes to main", %{content: content} do
      assert content =~ "branches: [main]"
    end

    test "pins the same OTP/Elixir versions as the shared EC2 host", %{content: content} do
      assert content =~ ~s(otp-version: "29.0")
      assert content =~ ~s(elixir-version: "1.20.3")
    end

    test "builds a release and reaches the host only through GitHub secrets", %{
      content: content
    } do
      assert content =~ "mix release"
      assert content =~ "secrets.DEPLOY_SSH_HOST"
      assert content =~ "secrets.DEPLOY_SSH_PRIVATE_KEY"
      assert content =~ "secrets.DEPLOY_SSH_KNOWN_HOSTS"
      refute content =~ "StrictHostKeyChecking=no"
    end

    test "health-checks the labyrinth release on its real prod port", %{content: content} do
      assert content =~ "http://127.0.0.1:3060/healthz"
    end
  end

  describe "ops/scripts/deploy-release.sh" do
    setup do
      {:ok, path: Path.join(@root, "ops/scripts/deploy-release.sh")}
    end

    test "is executable", %{path: path} do
      import Bitwise

      assert (File.stat!(path).mode &&& 0o111) != 0
    end

    test "rolls back to the previous release on a failed health check", %{path: path} do
      content = File.read!(path)
      assert content =~ "previous_target"
      assert content =~ "rolling back"
    end

    test "tolerates a failed restart so a bad ExecStartPre migration triggers rollback too", %{
      path: path
    } do
      content = File.read!(path)
      assert content =~ ~s(systemctl restart "$service_name" || true)
    end
  end
end
