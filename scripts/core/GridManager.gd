extends Node
# Autoload. Holds all the grid data (walls, boxes, targets, player pos).
# No visual stuff in here at all - LevelView3D just reads this and draws it.

enum Direction { UP, DOWN, LEFT, RIGHT }
enum CellType { WALL, FLOOR, TARGET }

# quick lookup so try_move doesn't need a match statement every call
const DIRECTION_VECTORS := {
	Direction.UP: Vector2i(0, -1),
	Direction.DOWN: Vector2i(0, 1),
	Direction.LEFT: Vector2i(-1, 0),
	Direction.RIGHT: Vector2i(1, 0),
}

signal state_changed          # fires on every move/undo - view layer tweens to new positions
signal level_loaded           # fires when a whole new level comes in - view layer rebuilds everything
signal move_completed(move_count: int)
signal move_rejected(direction: Direction)
signal level_won(move_count: int)
signal level_lost(move_count: int)   # deadlock, not literally "lost" the app, just stuck

var grid: Array = []          # grid[y][x] -> CellType
var width: int = 0
var height: int = 0

var player_pos: Vector2i = Vector2i.ZERO
var boxes: Array[Vector2i] = []
var targets: Array[Vector2i] = []

var move_count: int = 0
var _history: Array[Dictionary] = []   # undo stack, just player pos + boxes each entry

# true once level_won/level_lost fires - blocks further moves/undo until the
# next level loads. Without this, keyboard/swipe input still reaches try_move
# even while the win/lose overlay is fading in on top (Control mouse_filter
# on the overlay doesn't stop keyboard input, only mouse/touch on the UI).
var _game_over: bool = false

@export var default_level_path: String = "res://levels/level_01.txt"  # loaded on startup
@export var par_moves: int = 8   # used for star rating, doesn't affect gameplay


func _ready() -> void:
	load_level_from_file(default_level_path)


# loading a level

func load_level_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("GridManager: level file not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var layout := file.get_as_text()
	file.close()
	load_level_from_text(layout)


# text format:
#   #  wall     .  floor
#   T  target   $  box       B  box already sitting on a target
#   @  player   P  player standing on a target
func load_level_from_text(layout: String) -> void:
	_reset_state()

	var lines := layout.strip_edges().split("\n")
	height = lines.size()
	width = _longest_line(lines)

	for y in range(height):
		grid.append(_parse_row(lines[y], y))

	level_loaded.emit()


func _reset_state() -> void:
	grid.clear()
	boxes.clear()
	targets.clear()
	_history.clear()
	move_count = 0
	_game_over = false


func _longest_line(lines: Array) -> int:
	var longest := 0
	for line in lines:
		longest = max(longest, line.length())
	return longest


# builds one row of the grid and records any box/player/target found in it.
# terrain (grid) and occupants (boxes/player) are handled by two separate
# helpers below so a "B" doesn't need to repeat "this is a target" logic.
func _parse_row(line: String, y: int) -> Array:
	var row: Array = []
	for x in range(width):
		var ch := " " if x >= line.length() else line[x]
		var pos := Vector2i(x, y)

		var cell_type := _cell_type_for_char(ch)
		row.append(cell_type)
		if cell_type == CellType.TARGET:
			targets.append(pos)

		_apply_entity_for_char(ch, pos)
	return row


# just answers "what's the floor here" - wall, floor, or target square
func _cell_type_for_char(ch: String) -> CellType:
	match ch:
		"#":
			return CellType.WALL
		"T", "B", "P":
			return CellType.TARGET
		_:
			return CellType.FLOOR


# separate from the above - this only cares about what's STANDING there
func _apply_entity_for_char(ch: String, pos: Vector2i) -> void:
	match ch:
		"$", "B":
			boxes.append(pos)
		"@", "P":
			player_pos = pos


# movement

func try_move(direction: Direction) -> bool:
	if _game_over:
		return false   # level already won/lost - board is frozen until the next one loads

	var delta: Vector2i = DIRECTION_VECTORS[direction]
	var next_pos: Vector2i = player_pos + delta

	if not _is_walkable(next_pos):
		move_rejected.emit(direction)
		return false

	var box_index := boxes.find(next_pos)
	if box_index != -1:
		# there's a box in front of us - try to push it
		if not _push_box(box_index, next_pos, delta):
			move_rejected.emit(direction)
			return false
	else:
		# nothing in the way, just walk
		_push_snapshot()
		player_pos = next_pos

	_finish_move()
	return true


# handles the actual box-pushing part of a move. returns false if the box
# can't go anywhere (wall behind it, or another box already there).
func _push_box(box_index: int, box_pos: Vector2i, delta: Vector2i) -> bool:
	var box_next_pos: Vector2i = box_pos + delta
	if not _is_walkable(box_next_pos) or boxes.has(box_next_pos):
		return false

	_push_snapshot()
	boxes[box_index] = box_next_pos
	player_pos = box_pos
	return true


# common bit after any successful move - bump counter, tell everyone,
# check if that move ended the level one way or another
func _finish_move() -> void:
	move_count += 1
	state_changed.emit()
	move_completed.emit(move_count)

	if is_win():
		_game_over = true
		level_won.emit(move_count)
	elif is_deadlocked():
		_game_over = true
		level_lost.emit(move_count)


func undo() -> bool:
	if _game_over:
		return false   # same freeze as try_move - no editing a finished board

	if _history.is_empty():
		return false

	var snapshot: Dictionary = _history.pop_back()
	player_pos = snapshot["player_pos"]
	boxes = snapshot["boxes"].duplicate()

	# undo counts as a move too (costs a step) instead of rolling the
	# counter back - keeps move_count = total actions taken, not "progress"
	move_count += 1
	state_changed.emit()
	move_completed.emit(move_count)
	return true


func is_win() -> bool:
	for box in boxes:
		if not targets.has(box):
			return false
	return true


# only catches the simple case: a box jammed into a real corner (wall on
# one side + wall on an adjacent side). doesn't catch every deadlock
# pattern (two boxes freezing each other along a wall, etc) but that
# needs a lot more analysis for not much practical benefit here.
func is_deadlocked() -> bool:
	for box in boxes:
		if targets.has(box):
			continue   # already solved, skip it
		if _is_corner_stuck(box):
			return true
	return false


func _is_corner_stuck(box: Vector2i) -> bool:
	var blocked_left := not _is_walkable(box + Vector2i(-1, 0))
	var blocked_right := not _is_walkable(box + Vector2i(1, 0))
	var blocked_up := not _is_walkable(box + Vector2i(0, -1))
	var blocked_down := not _is_walkable(box + Vector2i(0, 1))

	# stuck if pinned on one horizontal side AND one vertical side
	return (blocked_left or blocked_right) and (blocked_up or blocked_down)


# helpers
func _is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
		return false
	return grid[pos.y][pos.x] != CellType.WALL


func _push_snapshot() -> void:
	# only copying player pos + boxes (small arrays), not the whole grid -
	# keeps undo cheap even on bigger levels
	_history.append({
		"player_pos": player_pos,
		"boxes": boxes.duplicate(),
	})
