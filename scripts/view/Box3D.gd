extends Node3D
## Box3D
##
## Attach this to the root of your box scene (box_scene in LevelView3D).
## Purely visual — swaps material color when GridManager reports the box
## is sitting on a target. Never reads/writes grid logic directly.

@export var mesh_instance: MeshInstance3D
@export var default_color: Color = Color(0.85, 0.55, 0.25)   # tan/wood
@export var on_target_color: Color = Color(0.25, 0.85, 0.4)  # green

var _material: StandardMaterial3D


func _ready() -> void:
	if mesh_instance == null:
		mesh_instance = _find_first_mesh_instance(self)
	if mesh_instance:
		_material = StandardMaterial3D.new()
		_material.albedo_color = default_color
		mesh_instance.material_override = _material


func set_on_target(is_on_target: bool) -> void:
	if _material == null:
		return
	_material.albedo_color = on_target_color if is_on_target else default_color


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found:
			return found
	return null
