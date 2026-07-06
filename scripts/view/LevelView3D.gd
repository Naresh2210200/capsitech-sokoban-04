extends Node3D

const CELL_SIZE: float = 1.0

@export var wall_scene: PackedScene
@export var floor_scene: PackedScene
@export var target_scene: PackedScene
@export var box_scene: PackedScene
@export var player_scene: PackedScene

var _box_instances: Array[Node3D] = []
var _player_instance: Node3D
var _static_root: Node3D
var _dynamic_root: Node3D


func _ready() -> void:
	_static_root = Node3D.new()
	_static_root.name = "StaticGeometry"
	add_child(_static_root)

	_dynamic_root = Node3D.new()
	_dynamic_root.name = "DynamicEntities"
	add_child(_dynamic_root)

	GridManager.level_loaded.connect(_on_level_loaded)
	GridManager.state_changed.connect(_on_state_changed)
	GridManager.level_won.connect(_on_level_won)
	GridManager.level_lost.connect(_on_level_lost)

	_build_static_geometry()
	_build_dynamic_entities()


## Converts a logical grid cell (column, row) to a 3D world position.
## Column -> X axis, Row -> Z axis, Y stays 0 (ground level).
static func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)


# ---------------------------------------------------------------------------
# Static geometry: walls, floor tiles, target markers — built once per level
# ---------------------------------------------------------------------------

func _build_static_geometry() -> void:
	for child in _static_root.get_children():
		child.queue_free()

	for y in range(GridManager.height):
		for x in range(GridManager.width):
			var cell := Vector2i(x, y)
			var cell_type: int = GridManager.grid[y][x]
			var world_pos := grid_to_world(cell)

			# Every walkable cell gets a floor tile underneath it.
			if cell_type != GridManager.CellType.WALL and floor_scene:
				var floor_inst := floor_scene.instantiate()
				_static_root.add_child(floor_inst)
				floor_inst.position = world_pos

			if cell_type == GridManager.CellType.WALL and wall_scene:
				var wall_inst := wall_scene.instantiate()
				_static_root.add_child(wall_inst)
				wall_inst.position = world_pos + Vector3(0, 0.5, 0)

	for target_cell in GridManager.targets:
		if target_scene:
			var target_inst := target_scene.instantiate()
			_static_root.add_child(target_inst)
			target_inst.position = grid_to_world(target_cell) + Vector3(0, 0.20	, 0)


# ---------------------------------------------------------------------------
# Dynamic entities: player + boxes — repositioned every move, not rebuilt
# ---------------------------------------------------------------------------

func _build_dynamic_entities() -> void:
	for child in _dynamic_root.get_children():
		child.queue_free()
	_box_instances.clear()

	if player_scene:
		_player_instance = player_scene.instantiate()
		_dynamic_root.add_child(_player_instance)
		_player_instance.position = grid_to_world(GridManager.player_pos) + Vector3(0, 0.5, 0)

	if box_scene:
		for box_cell in GridManager.boxes:
			var box_inst := box_scene.instantiate()
			_dynamic_root.add_child(box_inst)
			box_inst.position = grid_to_world(box_cell) + Vector3(0, 0.5, 0)
			_box_instances.append(box_inst)


# ---------------------------------------------------------------------------
# Signal handlers — sync visuals to logical state (no logic decisions here)
# ---------------------------------------------------------------------------

## Fired only when a whole new level has been loaded (initial load, Next
## Level, Restart, or jumping to an arbitrary level). The new level's grid
## can be a completely different shape/size than the previous one, so we
## tear down and rebuild everything from scratch — a tween can't fix a
## room that's the wrong shape.
func _on_level_loaded() -> void:
	_build_static_geometry()
	_build_dynamic_entities()


func _on_state_changed() -> void:
	if _player_instance:
		var target_pos := grid_to_world(GridManager.player_pos) + Vector3(0, 0.5, 0)
		_tween_to(_player_instance, target_pos)

	for i in range(GridManager.boxes.size()):
		if i < _box_instances.size():
			var target_pos := grid_to_world(GridManager.boxes[i]) + Vector3(0, 0.5, 0)
			_tween_to(_box_instances[i], target_pos)
			_update_box_feedback(i)


func _on_level_won(_move_count: int) -> void:
	# Hook for win-state visual feedback (particles, confetti, camera pan).
	# Kept intentionally empty here — wired up once the UI layer exists.
	pass


func _on_level_lost(_move_count: int) -> void:
	# Hook for deadlock visual feedback (shake, red tint, stuck-box glow).
	# Kept intentionally empty here — UIManager handles the overlay.
	pass


func _tween_to(node: Node3D, target_pos: Vector3) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position", target_pos, 0.12)


func _update_box_feedback(index: int) -> void:
	# Visual feedback when a box lands on a target (glow/color swap).
	# MeshInstance material swap goes here once box_scene defines the mesh.
	var box_cell: Vector2i = GridManager.boxes[index]
	var on_target: bool = GridManager.targets.has(box_cell)
	var box_node := _box_instances[index]
	if box_node.has_method("set_on_target"):
		box_node.set_on_target(on_target)
