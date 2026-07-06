extends Node
# Autoload. Keeps track of WHICH level we're on and moves to the next one.
# Doesn't know anything about grid logic - just tells GridManager which
# file to load. Keeps this separate so GridManager doesn't need to care
# that levels 1-5 even exist.

signal level_changed(index: int, path: String)

@export var level_paths: Array[String] = [
	"res://levels/level_01.txt",
	"res://levels/level_02.txt",
	"res://levels/level_03.txt",
	"res://levels/level_04.txt",
	"res://levels/level_05.txt",
]

var current_index: int = 0


func _ready() -> void:
	load_current_level()


func load_current_level() -> void:
	current_index = clampi(current_index, 0, level_paths.size() - 1)  # just in case
	var path: String = level_paths[current_index]
	GridManager.load_level_from_file(path)
	level_changed.emit(current_index, path)


func restart_level() -> void:
	load_current_level()   # reloading the same index resets it


func has_next_level() -> bool:
	return current_index < level_paths.size() - 1


func next_level() -> void:
	if has_next_level():
		current_index += 1
		load_current_level()
	else:
		# ran out of levels - loop back to level 1 for now.
		# could swap this for a "you win the whole game" screen later
		current_index = 0
		load_current_level()


func go_to_level(index: int) -> void:
	if index >= 0 and index < level_paths.size():
		current_index = index
		load_current_level()
