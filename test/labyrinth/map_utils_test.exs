defmodule Labyrinth.MapUtilsTest do
  use ExUnit.Case, async: true
  alias Labyrinth.MapUtils

  describe "wall normalization" do
    test "normalizes coordinates so p1 <= p2" do
      assert MapUtils.normalize_wall({3, 2}, {1, 2}) == {{1, 2}, {3, 2}}
      assert MapUtils.normalize_wall({1, 2}, {3, 2}) == {{1, 2}, {3, 2}}

      assert MapUtils.normalize_wall(%{"x1" => 4, "y1" => 5, "x2" => 2, "y2" => 5}, nil) ==
               {{2, 5}, {4, 5}}

      assert MapUtils.normalize_wall([4, 5, 2, 5], nil) == {{2, 5}, {4, 5}}
    end

    test "normalizes a collection of walls into a MapSet" do
      raw_walls = [
        {{2, 1}, {1, 1}},
        %{"x1" => 3, "y1" => 3, "x2" => 3, "y2" => 2},
        [5, 5, 5, 4]
      ]

      normalized = MapUtils.normalize_walls(raw_walls)
      assert MapSet.size(normalized) == 3
      assert MapSet.member?(normalized, {{1, 1}, {2, 1}})
      assert MapSet.member?(normalized, {{3, 2}, {3, 3}})
      assert MapSet.member?(normalized, {{5, 4}, {5, 5}})
    end
  end

  describe "grid coordinates & distances" do
    test "checks boundary bounds correctly" do
      assert MapUtils.in_bounds?({0, 0}, 10, 10) == true
      assert MapUtils.in_bounds?({9, 9}, 10, 10) == true
      assert MapUtils.in_bounds?({-1, 5}, 10, 10) == false
      assert MapUtils.in_bounds?({10, 5}, 10, 10) == false
    end

    test "calculates Manhattan distance" do
      assert MapUtils.manhattan_distance({1, 1}, {4, 5}) == 7
      assert MapUtils.manhattan_distance({0, 0}, {0, 0}) == 0
    end

    test "returns cardinal neighbors" do
      assert MapUtils.neighbors({2, 2}) == [{2, 1}, {2, 3}, {1, 2}, {3, 2}]
    end
  end
end
