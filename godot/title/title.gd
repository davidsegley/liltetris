extends PanelContainer

const BOARD_SCN: PackedScene = preload("res://board/board.tscn")

@export var game_options: GameOptions = null

@onready var _menu := $"%Menu" as VBoxContainer
@onready var _new_game_menu := $"%NewGameMenu" as HBoxContainer
@onready var _new_game_button := $"%NewGameButton" as Button
@onready var _continue_button := $"%ContinueButton" as Button
@onready var _status_bar := $StatusBar as StatusBar
@onready var _top_scores_table := $"%TopScoresTable" as PanelContainer
@onready var _version_label := $MarginContainer/VersionLabel as Label
@onready var _normal_game_button := $CenterContainer/NewGameMenu/NormalMode as Button


func _ready() -> void:
	_continue_button.disabled = not FileAccess.file_exists("user://game.save")
	_setup_status_bar.call_deferred()
	_new_game_button.grab_focus()

	if not game_options.is_mobile:
		_continue_button.hide()

	_version_label.text = ProjectSettings.get_setting("application/config/version")


func _on_new_game_button_pressed() -> void:
	_menu.hide()
	_new_game_menu.show()

	_status_bar.add_back_action(
			func() -> void:
				_new_game_menu.hide()
				_menu.show()
	)

	_normal_game_button.grab_focus()


func _on_continue_button_pressed() -> void:
	assert(game_options != null)
	game_options.resume_last_game = true
	get_tree().change_scene_to_packed(BOARD_SCN)


func _setup_status_bar() -> void:
	if game_options.is_mobile:
		_top_scores_table.queue_free()
		return

	_status_bar.username = game_options.username


func _on_normal_mode_pressed() -> void:
	game_options.zen_mode = false
	get_tree().change_scene_to_packed(BOARD_SCN)


func _on_zen_mode_pressed() -> void:
	game_options.zen_mode = true
	get_tree().change_scene_to_packed(BOARD_SCN)

