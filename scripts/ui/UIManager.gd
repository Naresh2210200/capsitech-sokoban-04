extends CanvasLayer
## UIManager
##
## References UI nodes built manually in the scene tree. Listens to
## GridManager signals only — never touches grid data or 3D rendering

@onready var _move_label: Label = $HUD/MoveLabel
@onready var _undo_button: Button = $HUD/UndoButton

@onready var _win_overlay: Control = $WinOverlay
@onready var _win_stars: Label = $WinOverlay/Dim/WinPanel/VBox/StarsLabel
@onready var _win_moves_label: Label = $WinOverlay/Dim/WinPanel/VBox/MovesLabel
@onready var _restart_button: Button = $WinOverlay/Dim/WinPanel/VBox/RestartButton


func _ready() -> void:
	_win_overlay.visible = false

	_undo_button.pressed.connect(_on_undo_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)

	GridManager.move_completed.connect(_on_move_completed)
	GridManager.level_won.connect(_on_level_won)

	_update_move_label(GridManager.move_count)


func _on_undo_pressed() -> void:
	GridManager.undo()


func _on_move_completed(move_count: int) -> void:
	_update_move_label(move_count)


func _update_move_label(move_count: int) -> void:
	_move_label.text = "Moves: %d" % move_count


func _on_level_won(move_count: int) -> void:
	var stars := _calculate_stars(move_count)
	_win_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	_win_moves_label.text = "Solved in %d moves (par: %d)" % [move_count, GridManager.par_moves]
	_win_overlay.visible = true


func _on_restart_pressed() -> void:
	_win_overlay.visible = false
	GridManager.load_level_from_file(GridManager.default_level_path)


## 3 stars: at or under par. 2 stars: within 1.5x par. 1 star: solved at all.
func _calculate_stars(move_count: int) -> int:
	var par: int = GridManager.par_moves
	if move_count <= par:
		return 3
	elif move_count <= int(par * 1.5):
		return 2
	else:
		return 1
