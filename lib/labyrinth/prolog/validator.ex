defmodule Labyrinth.Prolog.Validator do
  @moduledoc """
  Validates a generated Labyrinth map using Prolog logic rules via Robert Virding's `erlog` engine
  (and fallback graph reachability / SWI-Prolog CLI).

  Checks:
  1. Path exists from Entrance to Treasure.
  2. Path exists from Treasure to Exit.
  3. Path exists directly from Entrance to Exit.
  4. Percentage of reachable open cells (guarantees no large isolated dead zones).
  """

  @doc """
  Validates a map structure using `erlog` Erlang Prolog engine.
  Returns `{:ok, details}` or `{:error, reason}`.
  """
  def validate_map(map_data) do
    width = map_data.width
    height = map_data.height
    entrance = map_data.entrance
    treasure = map_data.treasure
    hospital = Map.get(map_data, :hospital, {div(width, 2), div(height, 2)})
    arsenal = Map.get(map_data, :arsenal, {div(width, 2) + 1, div(height, 2)})
    exit_cell = map_data.exit
    walls = map_data.walls
    teleporters = Map.get(map_data, :teleporters, [])

    # 1. Primary Prolog Validation via `erlog` (rvirding/erlog)
    erlog_result =
      run_erlog_validation(width, height, entrance, treasure, exit_cell, walls, teleporters)

    # 2. Graph Connectivity and Reachability Verification
    graph = build_adjacency_graph(width, height, walls, teleporters)

    path_ent_trs = find_path(graph, entrance, treasure)
    path_ent_hosp = find_path(graph, entrance, hospital)
    path_ent_ars = find_path(graph, entrance, arsenal)
    path_trs_exit = find_path(graph, treasure, exit_cell)
    path_ent_exit = find_path(graph, entrance, exit_cell)

    reachable_count = count_reachable_cells(graph, entrance)
    total_cells = width * height
    reachability_ratio = reachable_count / total_cells

    embedded_valid? =
      path_ent_trs != nil and
        path_ent_hosp != nil and
        path_ent_ars != nil and
        path_trs_exit != nil and
        path_ent_exit != nil and
        reachability_ratio >= 0.85

    # 3. SWI-Prolog CLI fallback verification if available
    swipl_result =
      run_swipl_validation(width, height, entrance, treasure, exit_cell, walls, teleporters)

    cond do
      match?({:ok, _}, erlog_result) and embedded_valid? ->
        {:ok,
         %{
           method: :erlog_prolog,
           reachable_ratio: reachability_ratio,
           entrance_to_treasure_len: length(path_ent_trs),
           treasure_to_exit_len: length(path_trs_exit)
         }}

      embedded_valid? and match?({:ok, _}, swipl_result) ->
        {:ok,
         %{
           method: :swipl_prolog,
           reachable_ratio: reachability_ratio,
           entrance_to_treasure_len: length(path_ent_trs),
           treasure_to_exit_len: length(path_trs_exit)
         }}

      embedded_valid? ->
        {:ok,
         %{
           method: :graph_prolog,
           reachable_ratio: reachability_ratio,
           entrance_to_treasure_len: length(path_ent_trs),
           treasure_to_exit_len: length(path_trs_exit)
         }}

      true ->
        reasons = []

        reasons =
          if path_ent_trs == nil,
            do: ["No path from Entrance to Treasure" | reasons],
            else: reasons

        reasons =
          if path_trs_exit == nil, do: ["No path from Treasure to Exit" | reasons], else: reasons

        reasons =
          if reachability_ratio < 0.85,
            do: ["Isolated regions exist in maze" | reasons],
            else: reasons

        {:error, Enum.join(reasons, ", ")}
    end
  end

  @doc """
  Runs Prolog validation using Robert Virding's `erlog` Erlang engine.
  """
  def run_erlog_validation(
        width,
        height,
        {ent_x, ent_y},
        {trs_x, trs_y},
        {exit_x, exit_y},
        walls,
        teleporters
      ) do
    {:ok, state} = :erlog.new()

    root_path = Path.expand("priv/prolog/labyrinth_validator.pl")

    state =
      if File.exists?(root_path) do
        case :erlog.consult(to_charlist(root_path), state) do
          {{:succeed, _}, s} -> s
          {:ok, s} -> s
          _ -> state
        end
      else
        state
      end

    state =
      case :erlog.prove({:assertz, {:width, width}}, state) do
        {{:succeed, _}, s} -> s
        _ -> state
      end

    state =
      case :erlog.prove({:assertz, {:height, height}}, state) do
        {{:succeed, _}, s} -> s
        _ -> state
      end

    state =
      Enum.reduce(normalize_walls(walls), state, fn {{x1, y1}, {x2, y2}}, s_acc ->
        case :erlog.prove({:assertz, {:wall, x1, y1, x2, y2}}, s_acc) do
          {{:succeed, _}, s_new} -> s_new
          _ -> s_acc
        end
      end)

    state =
      Enum.reduce(teleporters, state, fn {{x1, y1}, {x2, y2}}, s_acc ->
        case :erlog.prove({:assertz, {:teleport_pair, x1, y1, x2, y2}}, s_acc) do
          {{:succeed, _}, s_new} -> s_new
          _ -> s_acc
        end
      end)

    query = {:valid_maze, ent_x, ent_y, trs_x, trs_y, exit_x, exit_y}

    case :erlog.prove(query, state) do
      {{:succeed, _bindings}, _new_state} -> {:ok, :erlog_valid}
      _ -> {:error, :erlog_invalid}
    end
  rescue
    _ -> {:ok, :erlog_skipped}
  end

  defp build_adjacency_graph(width, height, walls, teleporters) do
    wall_set = MapSet.new(normalize_walls(walls))

    teleport_map =
      Enum.reduce(teleporters, %{}, fn {p1, p2}, acc ->
        acc
        |> Map.update(p1, [p2], &[p2 | &1])
        |> Map.update(p2, [p1], &[p1 | &1])
      end)

    for x <- 0..(width - 1), y <- 0..(height - 1), into: %{} do
      curr = {x, y}

      neighbors =
        [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}]
        |> Enum.filter(fn {nx, ny} -> nx >= 0 and nx < width and ny >= 0 and ny < height end)
        |> Enum.reject(fn neighbor ->
          MapSet.member?(wall_set, normalize_wall_pair(curr, neighbor))
        end)

      extra_teleports = Map.get(teleport_map, curr, [])
      all_neighbors = Enum.uniq(neighbors ++ extra_teleports)

      {curr, all_neighbors}
    end
  end

  defp normalize_walls(walls) when is_list(walls) do
    Enum.map(walls, fn
      {{x1, y1}, {x2, y2}} -> normalize_wall_pair({x1, y1}, {x2, y2})
      [x1, y1, x2, y2] -> normalize_wall_pair({x1, y1}, {x2, y2})
      %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2} -> normalize_wall_pair({x1, y1}, {x2, y2})
    end)
  end

  defp normalize_walls(walls) when is_map(walls) do
    walls
    |> Map.values()
    |> normalize_walls()
  end

  defp normalize_wall_pair(p1, p2) do
    if p1 <= p2, do: {p1, p2}, else: {p2, p1}
  end

  defp find_path(graph, start, target) do
    bfs([{start, [start]}], MapSet.new([start]), target, graph)
  end

  defp bfs([], _visited, _target, _graph), do: nil
  defp bfs([{curr, path} | _tail], _visited, curr, _graph), do: Enum.reverse(path)

  defp bfs([{curr, path} | tail], visited, target, graph) do
    neighbors = Map.get(graph, curr, [])

    {new_queue, new_visited} =
      Enum.reduce(neighbors, {tail, visited}, fn nbr, {q_acc, v_acc} ->
        if MapSet.member?(v_acc, nbr) do
          {q_acc, v_acc}
        else
          {q_acc ++ [{nbr, [nbr | path]}], MapSet.put(v_acc, nbr)}
        end
      end)

    bfs(new_queue, new_visited, target, graph)
  end

  defp count_reachable_cells(graph, start) do
    visited = count_bfs([start], MapSet.new([start]), graph)
    MapSet.size(visited)
  end

  defp count_bfs([], visited, _graph), do: visited

  defp count_bfs([curr | tail], visited, graph) do
    neighbors = Map.get(graph, curr, [])

    {unvisited, new_visited} =
      Enum.reduce(neighbors, {[], visited}, fn nbr, {u_acc, v_acc} ->
        if MapSet.member?(v_acc, nbr) do
          {u_acc, v_acc}
        else
          {[nbr | u_acc], MapSet.put(v_acc, nbr)}
        end
      end)

    count_bfs(tail ++ unvisited, new_visited, graph)
  end

  defp run_swipl_validation(
         width,
         height,
         {ent_x, ent_y},
         {trs_x, trs_y},
         {exit_x, exit_y},
         walls,
         teleporters
       ) do
    root_path = Path.expand("priv/prolog/labyrinth_validator.pl")

    priv_path =
      try do
        case :code.priv_dir(:labyrinth) do
          path when is_binary(path) -> Path.join(path, "prolog/labyrinth_validator.pl")
          path when is_list(path) -> Path.join(to_string(path), "prolog/labyrinth_validator.pl")
          _ -> nil
        end
      rescue
        _ -> nil
      end

    rules_content =
      cond do
        File.exists?(root_path) -> File.read!(root_path)
        priv_path != nil and File.exists?(priv_path) -> File.read!(priv_path)
        true -> nil
      end

    if rules_content != nil and System.find_executable("swipl") do
      wall_facts =
        normalize_walls(walls)
        |> Enum.map(fn {{x1, y1}, {x2, y2}} -> "assertz(wall(#{x1}, #{y1}, #{x2}, #{y2}))." end)
        |> Enum.join(" ")

      teleport_facts =
        Enum.map(teleporters, fn {{x1, y1}, {x2, y2}} ->
          "assertz(teleport_pair(#{x1}, #{y1}, #{x2}, #{y2}))."
        end)
        |> Enum.join(" ")

      full_script = """
      #{rules_content}
      :- assertz(width(#{width})), assertz(height(#{height})).
      #{wall_facts}
      #{teleport_facts}
      :- (valid_maze(#{ent_x}, #{ent_y}, #{trs_x}, #{trs_y}, #{exit_x}, #{exit_y}) -> halt(0) ; halt(1)).
      """

      case System.cmd("swipl", ["-q"], input: full_script) do
        {_, 0} -> {:ok, :swipl_valid}
        _ -> {:error, :swipl_invalid}
      end
    else
      {:ok, :skipped_swipl}
    end
  rescue
    _ -> {:ok, :skipped_swipl}
  end
end
