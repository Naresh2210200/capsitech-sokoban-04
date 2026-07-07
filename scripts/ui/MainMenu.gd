extends CanvasLayer
# Entry-point menu - just Start and Exit. Doesn't touch GridManager or
# LevelManager at all, only swaps scenes / quits the app.

@export var game_scene_path: String = "res://Scene/main.tscn"

@onready var _start_button: Button = $Menu/VBox/PlayButton
@onready var _exit_button: Button = $Menu/VBox/ExitButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(game_scene_path)


func _on_exit_pressed() -> void:
	get_tree().quit()
