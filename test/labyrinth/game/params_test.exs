defmodule Labyrinth.Game.ParamsTest do
  use ExUnit.Case, async: true

  alias Labyrinth.Game.Params

  describe "defaults/0" do
    test "returns documented defaults" do
      assert Params.defaults() == %{
               width: 10,
               height: 10,
               bot_count: 1,
               pit_count: 3,
               teleport_count: 1,
               wall_density: 70,
               difficulty: :normal
             }
    end
  end

  describe "parse/1 with empty input" do
    test "returns all defaults" do
      assert Params.parse(%{}) == [
               width: 10,
               height: 10,
               bot_count: 1,
               pit_count: 3,
               teleport_count: 1,
               wall_density: 70,
               difficulty: :normal
             ]
    end

    test "accepts atom-keyed maps too" do
      assert Params.parse(%{width: 8, difficulty: :hard})[:width] == 8
      assert Params.parse(%{width: 8, difficulty: :hard})[:difficulty] == :hard
    end
  end

  describe "parse/1 clamping" do
    test "clamps width and height to 5..20" do
      assert Params.parse(%{"width" => "1"})[:width] == 5
      assert Params.parse(%{"width" => "50"})[:width] == 20
      assert Params.parse(%{"height" => "-3"})[:height] == 5
      assert Params.parse(%{"height" => "999"})[:height] == 20
    end

    test "clamps wall_density to 0..100" do
      assert Params.parse(%{"wall_density" => "-10"})[:wall_density] == 0
      assert Params.parse(%{"wall_density" => "150"})[:wall_density] == 100
    end

    test "clamps pit_count, teleport_count, bot_count to safe upper bounds" do
      assert Params.parse(%{"pit_count" => "1000000"})[:pit_count] == 30
      assert Params.parse(%{"teleport_count" => "99999"})[:teleport_count] == 20
      assert Params.parse(%{"bot_count" => "100"})[:bot_count] == 8
    end

    test "clamps negative counts to zero" do
      assert Params.parse(%{"pit_count" => "-5"})[:pit_count] == 0
      assert Params.parse(%{"bot_count" => "-1"})[:bot_count] == 0
    end
  end

  describe "parse/1 difficulty handling" do
    test "accepts all allowed difficulties" do
      assert Params.parse(%{"difficulty" => "easy"})[:difficulty] == :easy
      assert Params.parse(%{"difficulty" => "normal"})[:difficulty] == :normal
      assert Params.parse(%{"difficulty" => "hard"})[:difficulty] == :hard
    end

    test "falls back to :normal for unknown or malicious difficulty strings" do
      assert Params.parse(%{"difficulty" => "EVIL"})[:difficulty] == :normal

      assert Params.parse(%{"difficulty" => ":erlang.atom_exhaustion_attack"})[:difficulty] ==
               :normal

      assert Params.parse(%{"difficulty" => ""})[:difficulty] == :normal
    end

    test "does not create new atoms from untrusted input" do
      malicious = "not_a_real_difficulty_#{System.unique_integer([:positive])}"

      # The malicious string must not exist as an atom before parsing.
      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(malicious) end

      assert Params.parse(%{"difficulty" => malicious})[:difficulty] == :normal

      # And it must still not exist as an atom after parsing.
      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(malicious) end
    end
  end

  describe "parse_difficulty/1" do
    test "handles string, atom, nil and unexpected types" do
      assert Params.parse_difficulty("easy") == :easy
      assert Params.parse_difficulty(:hard) == :hard
      assert Params.parse_difficulty(nil) == :normal
      assert Params.parse_difficulty(123) == :normal
      assert Params.parse_difficulty("HARD") == :hard
    end
  end
end
