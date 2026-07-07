extends CanvasLayer
# All the on-screen UI - move counter, level label, undo, and the three
# overlays (win / lose / end-credits). Only listens to GridManager and
# LevelManager signals, never touches grid data or the 3D view directly.

@onready var _move_label: Label = $HUD/MoveLabel
@onready var _level_label: Label = $HUD/Level
@onready var _undo_button: Button = $HUD/UndoButton
@onready var _exit_button: Button = $HUD/Exit

@onready var _win_overlay: Control = $WinOverlay
@onready var _win_stars: Label = $WinOverlay/Dim/WinPanel/VBox/StarsLabel
@onready var _win_moves_label: Label = $WinOverlay/Dim/WinPanel/VBox/MovesLabel
@onready var _restart_button: Button = $WinOverlay/Dim/WinPanel/VBox/RestartButton

@onready var _lose_overlay: Control = $LoseOverlay
@onready var _lose_moves_label: Label = $LoseOverlay/Dim/LosePanel/VBox/LoseMovesLabel
@onready var _try_again_button: Button = $LoseOverlay/Dim/LosePanel/VBox/TryAgainButton

@onready var _credits_overlay: Control = $CreditsOverlay
@onready var _main_menu_button: Button = $CreditsOverlay/Dim/VBox/MainMenuButton

@export var main_menu_scene_path: String = "res://Scene/ui/main_menu.tscn"

## Star rating cutoffs: solve in <= this many moves for 3 stars, <= this
## many for 2 stars, anything above that is 1 star. Fixed numbers rather
## than a per-level "par" - same bar for every level, easy to tune here
## without touching GridManager.
@export var three_star_moves: int = 10
@export var two_star_moves: int = 15

## How long to wait before an overlay starts fading in - gives the last
## box's slide-into-place tween (in LevelView3D) time to actually finish,
## instead of the screen slamming down mid-animation.
@export var overlay_delay: float = 0.2
## How long the fade-in itself takes once it starts.
@export var overlay_fade_time: float = 0.35


func _ready() -> void:
	_win_overlay.visible = false
	_lose_overlay.visible = false
	_credits_overlay.visible = false

	_undo_button.pressed.connect(_on_undo_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_try_again_button.pressed.connect(_on_try_again_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)

	GridManager.move_completed.connect(_on_move_completed)
	GridManager.level_won.connect(_on_level_won)
	GridManager.level_lost.connect(_on_level_lost)
	LevelManager.level_changed.connect(_on_level_changed)

	_update_move_label(GridManager.move_count)
	_update_level_label(LevelManager.current_index)


# ---------------------------------------------------------------------------
# HUD - move counter, level label, undo, exit
# ---------------------------------------------------------------------------

func _on_undo_pressed() -> void:
	GridManager.undo()


## Takes the player back to the main menu instead of quitting the app -
## same as the Main Menu button on the credits screen, so it also resets
## progress back to level 1 for a clean restart later.
func _on_exit_pressed() -> void:
	_on_main_menu_pressed()


func _on_move_completed(move_count: int) -> void:
	_update_move_label(move_count)


func _update_move_label(move_count: int) -> void:
	_move_label.text = "Moves: %d" % move_count


func _update_level_label(index: int) -> void:
	_level_label.text = "Level: %d" % (index + 1)


func _on_level_changed(index: int, _path: String) -> void:
	_update_level_label(index)
	_update_move_label(GridManager.move_count)
	_hide_win_and_lose_overlays()


# ---------------------------------------------------------------------------
# win screen
# ---------------------------------------------------------------------------

func _on_level_won(move_count: int) -> void:
	if not LevelManager.has_next_level():
		_show_overlay(_credits_overlay)
		return

	var stars := _calculate_stars(move_count)
	_win_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	_win_moves_label.text = "Solved in %d moves" % move_count
	_restart_button.text = "Next Level"
	_show_overlay(_win_overlay)


func _on_restart_pressed() -> void:
	_win_overlay.visible = false
	LevelManager.next_level()


func _calculate_stars(move_count: int) -> int:
	if move_count <= three_star_moves:
		return 3
	elif move_count <= two_star_moves:
		return 2
	else:
		return 1


# ---------------------------------------------------------------------------
# lose / deadlock screen
# ---------------------------------------------------------------------------

func _on_level_lost(_move_count: int) -> void:
	_lose_moves_label.text = "No box can reach a target."
	_show_overlay(_lose_overlay)


func _on_try_again_pressed() -> void:
	_lose_overlay.visible = false
	LevelManager.restart_level()


# ---------------------------------------------------------------------------
# end credits
# ---------------------------------------------------------------------------

func _on_main_menu_pressed() -> void:
	_credits_overlay.visible = false
	LevelManager.go_to_level(0)
	get_tree().change_scene_to_file(main_menu_scene_path)


func _hide_win_and_lose_overlays() -> void:
	_win_overlay.visible = false
	_lose_overlay.visible = false


# ---------------------------------------------------------------------------
# shared overlay transition - waits a beat for the last move's animation to
# land, then fades the overlay in instead of snapping it on top of the scene
# ---------------------------------------------------------------------------

func _show_overlay(overlay: Control) -> void:
	overlay.modulate.a = 0.0
	overlay.visible = true

	if overlay_delay > 0.0:
		await get_tree().create_timer(overlay_delay).timeout

	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0, overlay_fade_time)
