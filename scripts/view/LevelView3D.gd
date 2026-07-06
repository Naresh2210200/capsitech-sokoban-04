extends Node3D
# Pure rendering layer - reads GridManager's data and draws it in 3D.
# Never changes grid state, only reacts to signals and moves/creates meshes.
#
#   User Gesture -> InputController -> GridManager -> LevelView3D (this)

const CELL_SIZE: float = 1.0

@export var wall_scene: PackedScene
@export var floor_scene: PackedScene
@export var target_scene: PackedScene
@export var box_scene: PackedScene
@export var player_scene: PackedScene

@export var camera: Camera3D   # for the reject-shake below, optional

@export var player_hop_height: float = 0.35
@export var player_hop_duration: float = 0.14

@export var move_sound: AudioStream   # assign in Inspector, e.g. footstep.wav/ogg

@export var reject_shake_strength: float = 0.12
@export var reject_shake_duration: float = 0.18
@export var reject_vibration_ms: int = 60

# --- camera auto-fit ---------------------------------------------------
@export var camera_padding: float = 1.5     # extra "breathing room" cells around the level
@export var camera_fit_tween_time: float = 0.35   # set to 0.0 for an instant snap, no easing

var _box_instances: Array[Node3D] = []
var _player_instance: Node3D
var _static_root: Node3D
var _dynamic_root: Node3D
var _audio_player: AudioStreamPlayer
var _camera_base_position: Vector3


func _ready() -> void:
	_static_root = Node3D.new()
	_static_root.name = "StaticGeometry"
	add_child(_static_root)

	_dynamic_root = Node3D.new()
	_dynamic_root.name = "DynamicEntities"
	add_child(_dynamic_root)

	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "MoveAudioPlayer"
	add_child(_audio_player)

	GridManager.level_loaded.connect(_on_level_loaded)
	GridManager.state_changed.connect(_on_state_changed)
	GridManager.move_completed.connect(_on_move_completed)
	GridManager.level_won.connect(_on_level_won)
	GridManager.level_lost.connect(_on_level_lost)
	GridManager.move_rejected.connect(_on_move_rejected)

	if camera:
		_camera_base_position = camera.position

	# re-fit whenever the window/viewport is resized, so aspect changes
	# (e.g. rotating a device) don't leave the level mis-framed
	get_viewport().size_changed.connect(_fit_camera_to_level)

	_build_static_geometry()
	_build_dynamic_entities()
	_fit_camera_to_level(false)   # snap instantly on first load, no tween


static func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)


# ---------------------------------------------------------------------------
# static geometry - walls / floor / targets, only rebuilt on a new level
# ---------------------------------------------------------------------------

func _build_static_geometry() -> void:
	for child in _static_root.get_children():
		child.queue_free()

	for y in range(GridManager.height):
		for x in range(GridManager.width):
			_place_terrain_tile(Vector2i(x, y))

	for target_cell in GridManager.targets:
		_place_target_marker(target_cell)


func _place_terrain_tile(cell: Vector2i) -> void:
	var cell_type: int = GridManager.grid[cell.y][cell.x]
	var world_pos := grid_to_world(cell)

	if cell_type != GridManager.CellType.WALL and floor_scene:
		var floor_inst := floor_scene.instantiate()
		_static_root.add_child(floor_inst)
		floor_inst.position = world_pos

	if cell_type == GridManager.CellType.WALL and wall_scene:
		var wall_inst := wall_scene.instantiate()
		_static_root.add_child(wall_inst)
		wall_inst.position = world_pos + Vector3(0, 0.5, 0)


func _place_target_marker(cell: Vector2i) -> void:
	if not target_scene:
		return
	var target_inst := target_scene.instantiate()
	_static_root.add_child(target_inst)
	target_inst.position = grid_to_world(cell) + Vector3(0, 0.20, 0)


# ---------------------------------------------------------------------------
# dynamic entities - player + boxes, repositioned every move, not rebuilt
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
# camera auto-fit - re-centers & re-zooms the camera so the whole level
# (regardless of its width/height) always fits inside the frame, the way
# Fancade-style puzzle games frame each board.
# ---------------------------------------------------------------------------

func _fit_camera_to_level(animate: bool = true) -> void:
	if not camera:
		return

	var grid_w := float(GridManager.width)
	var grid_h := float(GridManager.height)
	if grid_w <= 0.0 or grid_h <= 0.0:
		return

	# center of the grid in world space (grid_to_world uses cell * CELL_SIZE)
	var center := Vector3(
		(grid_w - 1) * CELL_SIZE * 0.5,
		0.0,
		(grid_h - 1) * CELL_SIZE * 0.5
	)

	var half_x := grid_w * CELL_SIZE * 0.5 + camera_padding
	var half_z := grid_h * CELL_SIZE * 0.5 + camera_padding

	var viewport_size := get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / max(viewport_size.y, 1.0)

	var target_position: Vector3

	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# orthogonal size defines the *vertical* half-extent visible on screen
		var size_for_z := half_z
		var size_for_x := half_x / aspect
		camera.size = max(size_for_z, size_for_x) * 2.0
		target_position = Vector3(center.x, camera.position.y, center.z)
	else:
		# perspective: solve for the camera height (distance straight down)
		# that lets both axes fit inside the field of view
		var vfov_rad := deg_to_rad(camera.fov)
		var hfov_rad := 2.0 * atan(tan(vfov_rad * 0.5) * aspect)

		var height_for_z := half_z / tan(vfov_rad * 0.5)
		var height_for_x := half_x / tan(hfov_rad * 0.5)

		var camera_height: float = max(height_for_z, height_for_x)
		target_position = Vector3(center.x, camera_height, center.z)

	if animate and camera_fit_tween_time > 0.0:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(camera, "position", target_position, camera_fit_tween_time)
		tween.finished.connect(func() -> void: _camera_base_position = camera.position)
	else:
		camera.position = target_position
		_camera_base_position = target_position


# ---------------------------------------------------------------------------
# signal handlers - just sync visuals, no decisions made here
# ---------------------------------------------------------------------------

func _on_level_loaded() -> void:
	_build_static_geometry()
	_build_dynamic_entities()
	_fit_camera_to_level()


func _on_state_changed() -> void:
	if _player_instance:
		var target_pos := grid_to_world(GridManager.player_pos) + Vector3(0, 0.5, 0)
		_hop_player(target_pos)

	for i in range(GridManager.boxes.size()):
		if i < _box_instances.size():
			var target_pos := grid_to_world(GridManager.boxes[i]) + Vector3(0, 0.5, 0)
			_tween_to(_box_instances[i], target_pos)
			_update_box_feedback(i)


func _on_move_completed(_move_count: int) -> void:
	if move_sound and _audio_player:
		_audio_player.stream = move_sound
		_audio_player.play()


func _on_level_won(_move_count: int) -> void:
	pass


func _on_level_lost(_move_count: int) -> void:
	pass


func _on_move_rejected(_direction: int) -> void:
	_shake_camera()
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(reject_vibration_ms)


func _tween_to(node: Node3D, target_pos: Vector3) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position", target_pos, 0.12)


func _hop_player(target_pos: Vector3) -> void:
	var start_pos: Vector3 = _player_instance.position
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(t: float) -> void:
			var pos := start_pos.lerp(target_pos, t)
			pos.y += sin(t * PI) * player_hop_height
			_player_instance.position = pos,
		0.0, 1.0, player_hop_duration
	)


func _shake_camera() -> void:
	if not camera:
		return

	var tween := create_tween()
	var shake_steps := 4
	var step_time := reject_shake_duration / (shake_steps + 1)

	for i in range(shake_steps):
		var offset := Vector3(
			randf_range(-reject_shake_strength, reject_shake_strength),
			randf_range(-reject_shake_strength, reject_shake_strength),
			0.0
		)
		tween.tween_property(camera, "position", _camera_base_position + offset, step_time)

	tween.tween_property(camera, "position", _camera_base_position, step_time)


func _update_box_feedback(index: int) -> void:
	var box_cell: Vector2i = GridManager.boxes[index]
	var on_target: bool = GridManager.targets.has(box_cell)
	var box_node := _box_instances[index]
	if box_node.has_method("set_on_target"):
		box_node.set_on_target(on_target)
