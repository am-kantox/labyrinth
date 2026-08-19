% Labyrinth Prolog Validation Rules
% Validates that a labyrinth layout is solvable and all open cells are reachable.

:- dynamic cell/2.
:- dynamic wall/4.
:- dynamic teleport_pair/4.
:- dynamic width/1.
:- dynamic height/1.

% Check if two cells are strictly adjacent in 2D grid
adjacent(X1, Y1, X2, Y2) :-
    X2 is X1 + 1, Y2 is Y1.
adjacent(X1, Y1, X2, Y2) :-
    X2 is X1 - 1, Y2 is Y1.
adjacent(X1, Y1, X2, Y2) :-
    X2 is X1, Y2 is Y1 + 1.
adjacent(X1, Y1, X2, Y2) :-
    X2 is X1, Y2 is Y1 - 1.

% Check if a cell is inside the maze boundary
in_bounds(X, Y) :-
    width(W), height(H),
    X >= 0, X < W,
    Y >= 0, Y < H.

% Two cells are connected if they are adjacent and no wall blocks them
connected(X1, Y1, X2, Y2) :-
    in_bounds(X1, Y1),
    in_bounds(X2, Y2),
    adjacent(X1, Y1, X2, Y2),
    \+ wall(X1, Y1, X2, Y2),
    \+ wall(X2, Y1, X1, Y2).

% Teleport portals connect instantly
connected(X1, Y1, X2, Y2) :-
    teleport_pair(X1, Y1, X2, Y2).
connected(X1, Y1, X2, Y2) :-
    teleport_pair(X2, Y2, X1, Y1).

% Path finding between Start and End using Depth-First Search
path(X, Y, X, Y, _Visited).
path(X1, Y1, TargetX, TargetY, Visited) :-
    connected(X1, Y1, NextX, NextY),
    \+ member(cell(NextX, NextY), Visited),
    path(NextX, NextY, TargetX, TargetY, [cell(NextX, NextY) | Visited]).

% Reachable helper
reachable(StartX, StartY, TargetX, TargetY) :-
    path(StartX, StartY, TargetX, TargetY, [cell(StartX, StartY)]).

% Main Validation Predicate: valid_maze(EntX, EntY, TrsX, TrsY, ExitX, ExitY)
valid_maze(EntX, EntY, TrsX, TrsY, ExitX, ExitY) :-
    reachable(EntX, EntY, TrsX, TrsY),
    reachable(TrsX, TrsY, ExitX, ExitY).
