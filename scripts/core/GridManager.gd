extends Node
## GridManager
##
## Pure logical layer for the Sokoban grid. Holds ZERO references to
## Sprite2D, TileMap, or any visual node. Owns the grid data model,
## player/box positions, move history (for Undo), and win detection.
##
## View layer (LevelView3D.gd) listens to `state_changed` / `move_completed`
## / `level_won` signals and re-renders — it never mutates this data
## directly. This keeps state logic and UI rendering fully decoupled,
## per the architecture requirement in the technical spec.

enum Direction { UP, DOWN, LEFT, RIGHT }
enum CellType { WALL, FLOOR, TARGET }

const DIRECTION_VECTORS := {
	Direction.UP: Vector2i(0, -1),
	Direction.DOWN: Vector2i(0, 1),
	Direction.LEFT: Vector2i(-1, 0),
	Direction.RIGHT: Vector2i(1, 0),
}

signal state_changed
signal move_completed(move_count: int)
signal move_rejected(direction: Direction)
signal level_won(move_count: int)

var grid: Array = []          # Array[Array[CellType]] — grid[y][x]
var width: int = 0
var height: int = 0

var player_pos: Vector2i = Vector2i.ZERO
var boxes: Array[Vector2i] = []
var targets: Array[Vector2i] = []

var move_count: int = 0
var _history: Array[Dictionary] = []   # snapshots for Undo

## Path of the level loaded automatically on startup. Change this (or call
## load_level_from_file with a different path) to switch levels.
@export var default_level_path: String = "res://levels/level_01.txt"

## "Par" move count for this level — the target the star rating is measured
## against. Tune per level; has no effect on core logic, only scoring/UI.
@export var par_moves: int = 8


func _ready() -> void:
	load_level_from_file(default_level_path)


# ---------------------------------------------------------------------------
# Level loading
# ---------------------------------------------------------------------------

## Reads a level layout from a text file on disk and loads it.
func load_level_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("GridManager: level file not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var layout := file.get_as_text()
	file.close()
	load_level_from_text(layout)

## Loads a level from a simple text layout:
##   #  wall
##   .  floor
##   T  target marker
##   $  box (on floor)
##   B  box already on a target
##   @  player (on floor)
##   P  player already on a target
func load_level_from_text(layout: String) -> void:
	grid.clear()
	boxes.clear()
	targets.clear()
	_history.clear()
	move_count = 0

	var lines := layout.strip_edges().split("\n")
	height = lines.size()
	width = 0
	for line in lines:
		width = max(width, line.length())

	for y in range(height):
		var row: Array = []
		var line: String = lines[y]
		for x in range(width):
			var ch := " "
			if x < line.length():
				ch = line[x]
			var pos := Vector2i(x, y)
			match ch:
				"#":
					row.append(CellType.WALL)
				"T":
					row.append(CellType.TARGET)
					targets.append(pos)
				"$":
					row.append(CellType.FLOOR)
					boxes.append(pos)
				"B":
					row.append(CellType.TARGET)
					targets.append(pos)
					boxes.append(pos)
				"@":
					row.append(CellType.FLOOR)
					player_pos = pos
				"P":
					row.append(CellType.TARGET)
					targets.append(pos)
					player_pos = pos
				_:
					row.append(CellType.FLOOR)
		grid.append(row)

	state_changed.emit()


# ---------------------------------------------------------------------------
# Core movement logic
# ---------------------------------------------------------------------------

func try_move(direction: Direction) -> bool:
	var delta: Vector2i = DIRECTION_VECTORS[direction]
	var next_pos: Vector2i = player_pos + delta

	if not _is_walkable(next_pos):
		move_rejected.emit(direction)
		return false

	var box_index := boxes.find(next_pos)
	if box_index != -1:
		var box_next_pos: Vector2i = next_pos + delta
		if not _is_walkable(box_next_pos) or boxes.has(box_next_pos):
			move_rejected.emit(direction)
			return false
		_push_snapshot()
		boxes[box_index] = box_next_pos
		player_pos = next_pos
	else:
		_push_snapshot()
		player_pos = next_pos

	move_count += 1
	state_changed.emit()
	move_completed.emit(move_count)

	if is_win():
		level_won.emit(move_count)

	return true


func undo() -> bool:
	if _history.is_empty():
		return false
	var snapshot: Dictionary = _history.pop_back()
	player_pos = snapshot["player_pos"]
	boxes = snapshot["boxes"].duplicate()
	# Undo is itself treated as a move — it costs a step rather than
	# rolling the counter back, so move_count always reflects total
	# actions taken (forward moves + undos), matching the "rigid step
	# framework" requirement.
	move_count += 1
	state_changed.emit()
	move_completed.emit(move_count)
	return true


func is_win() -> bool:
	for box in boxes:
		if not targets.has(box):
			return false
	return true


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
		return false
	return grid[pos.y][pos.x] != CellType.WALL


func _push_snapshot() -> void:
	# Only player_pos + boxes are copied (small arrays) — avoids deep-copying
	# the whole grid on every move, keeping Undo memory-cheap.
	_history.append({
		"player_pos": player_pos,
		"boxes": boxes.duplicate(),
	})
