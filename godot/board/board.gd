class_name Board
extends PanelContainer

## Board

const SHAPE := preload("res://shapes/shape.tscn")
const ARROW_TEXTURE := preload("res://assets/play_arrow_24dp.svg")
const PAUSE_TEXTURE := preload("res://assets/pause_24dp.svg")

@export var game_options: GameOptions = null
@export var score_min_length: int = 6
@export var default_top_score: int = 1000
@export var preview_size: int = 5
@export var music_list: Array[AudioStream] = []
@export var input_delay: float = 0.2
@export var input_delay_decrease_ratio: float = 0.1
@export var min_input_delay: float = 0.02

var _input_timer: float = 0
var _input_delay: float = input_delay
var _direction_pressed := Vector2i.ZERO

var _top_score: int = default_top_score
var _low_health_tween: Tween = null
var _next_shapes: Array[Shape] = []
var _music_paused := false:
	set(value):
		if not is_node_ready():
			return

		_music_paused = value
		_bg_music.stream_paused = value

var _current_music_track: int = 0:
	set(value):
		_current_music_track = value % music_list.size()

		if music_list.is_empty() or _bg_music == null:
			return

		_bg_music.stream = music_list[_current_music_track]

@onready var _grid := $"%Grid" as Grid
@onready var _label_score := $"%LabelScore" as Label
@onready var _label_top_score := $"%LabelTop" as Label
@onready var _label_level := $"%LabelLevel" as Label
@onready var _panel := $MarginContainer/VBoxContainer/Panel as Panel
@onready var _pause_button := $"%PauseButton" as TextureButton
@onready var _lines_label := $"%LinesLabel" as Label
@onready var _grid_border := $"%GridBorder" as PanelContainer
@onready var _screen_message := $"%ScreenMessage" as Label
@onready var _screen_submessage := $"%ScreenSubMessage" as Label
@onready var _combo_container := $"%ComboContainer" as MarginContainer
@onready var _combo_label := $"%ComboLabel" as Label
@onready var _hold_shape := $"%HoldShape" as Shape
@onready var _next_pieces_box := $"%NextPiecesBox" as VBoxContainer
@onready var _game_over_screen := $"%GameOverScreen" as GameOverScreen
@onready var _hold_container := $"%HoldContainer" as CenterContainer
@onready var _bg_music := $BGMusic as AudioStreamPlayer
@onready var _desktop_menu := $DesktopMenu as MarginContainer

@onready var _left_button := $"%LeftButton" as TouchScreenButton
@onready var _right_button := $"%RightButton" as TouchScreenButton
@onready var _down_button := $"%DownButton" as TouchScreenButton

@onready var _post_score_request := $PostScoreRequest as APIRequest
@onready var _left_info := $"%LeftInfo" as VBoxContainer
@onready var _undo_button := $MarginContainer/VBoxContainer/VBoxContainer/MarginContainer/HBoxContainer/MobileMenu/UndoButton as TextureButton
@onready var _help_label := $MarginContainer/VBoxContainer/VBoxContainer/HelpLabel


func _ready() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	print_debug("safe area:", safe_area)
	_panel.custom_minimum_size = safe_area.position

	_post_score_request.request_completed.connect(_on_post_scores_completed)

	if not game_options.is_mobile:
		get_tree().call_group("mobile_controls", "hide")
		$MarginContainer/VBoxContainer/VBoxContainer/MarginContainer2.size_flags_vertical = SIZE_SHRINK_CENTER | SIZE_EXPAND

	_load_top_score()
	_top_score = maxi(_top_score, default_top_score)
	_label_score.text = str(0).pad_zeros(score_min_length)
	_label_top_score.text = str(_top_score).pad_zeros(score_min_length)

	_screen_message.hide()
	_screen_submessage.hide()
	_combo_container.hide()
	_hold_shape.hide()

	for child: Node in _next_pieces_box.get_children():
		if child is CenterContainer:
			child.queue_free()

	var preview_scale := Vector2(0.5, 0.5) if game_options.is_mobile else Vector2(0.8, 0.8)
	var preview_min_size := Vector2(150, 100) if game_options.is_mobile else Vector2(220, 150.0)

	for i: int in preview_size:
		var container := CenterContainer.new()
		container.custom_minimum_size = preview_min_size

		var control := Control.new()
		var shape := SHAPE.instantiate()

		shape.scale = preview_scale

		_next_shapes.push_back(shape)

		control.add_child(shape)
		container.add_child(control)

		_next_pieces_box.add_child(container)

	_hold_container.custom_minimum_size = preview_min_size
	_hold_shape.scale = preview_scale

	_game_over_screen.set_block_signals(true)
	_game_over_screen.hide()
	_game_over_screen.set_block_signals(false)

	if game_options.is_mobile:
		_init_music_list.call_deferred()
		_desktop_menu.hide()
		_help_label.hide()

	_grid.initial_level = game_options.initial_level

	if game_options.zen_mode:
		_grid.zen_mode = true
		_help_label.undo_visible = true
		_left_info.hide()
	else:
		_undo_button.hide()
		_help_label.undo_visible = false

	if game_options.resume_last_game:
		game_options.resume_last_game = false
		load_game.call_deferred()
	else:
		_grid.start()
		get_tree().paused = false

func _process(delta: float) -> void:
	var velocity := Vector2i.ZERO

	if Input.is_action_pressed("ui_right") or _right_button.is_pressed():
		velocity.x += 1
	if Input.is_action_pressed("ui_left") or _left_button.is_pressed():
		velocity.x -= 1
	if Input.is_action_pressed("ui_down") or _down_button.is_pressed():
		velocity.y += 1

	# Nothing pressed
	if velocity == Vector2i.ZERO:
		_input_timer = 0
		_input_delay = 0
		_direction_pressed = Vector2i.ZERO
		return

	_input_timer += delta
	if _input_timer < _input_delay:
		return

	# If first press: delay == 0 so act immediately
	_grid.move_shape(velocity, velocity.y > 0)
	_input_timer = 0

	if _input_delay == 0:
		# The next press will have delay
		_input_delay = input_delay
		_direction_pressed = velocity
	elif _direction_pressed.x == velocity.x:
		# If the button is still being pressed at the same direction
		# then the delay will decrease until reach the minimum
		_input_delay = max(min_input_delay, _input_delay - input_delay_decrease_ratio)
	elif _direction_pressed.x != velocity.x and velocity.y == 0:
		# Direction change reset input delay
		_input_delay = input_delay
		_direction_pressed = velocity


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().set_group(Grid.BLOCKS_GROUP, "visible", false)
		get_tree().set_group(Grid.SHAPES_GROUP, "visible", false)
		get_tree().set_group("visible_when_paused", "visible", true)

		save_game()
		get_tree().paused = true
		return

	if event.is_action_pressed("ui_undo") and game_options.zen_mode:
		_grid.undo()
		return

	if event.is_action_pressed("ui_up"):
		_grid.rotate_shape()
		return

	if event.is_action_pressed("rot_right"):
		_grid.rotate_shape(false)
		return

	if event.is_action_pressed("ui_page_up"):
		_grid.increase_level()
		return

	if event.is_action_pressed("ui_accept"):
		_grid.hard_drop()
		return

	if event.is_action_pressed("hold_piece"):
		_grid.hold_piece_swap()
		return


func _exit_tree() -> void:
	_save_top_score()


func save_game() -> void:
	if game_options.zen_mode:
		return

	_save_top_score()

	var state: Dictionary = _grid.save()
	var save_file: FileAccess = FileAccess.open("user://game.save", FileAccess.WRITE)

	if save_file == null:
		return

	var line: String = JSON.stringify(state)
	save_file.store_line(line)


func load_game() -> void:
	var success: bool = _try_load_game()
	if not success:
		_grid.restart()

	var paused: bool = get_tree().paused
	_pause_button.texture_normal = ARROW_TEXTURE if paused else PAUSE_TEXTURE


func _save() -> Dictionary:
	return {}


func _load(_state: Dictionary) -> void:
	pass


func _try_load_game() -> bool:
	if not FileAccess.file_exists("user://game.save"):
		return false

	var save_file: FileAccess = FileAccess.open("user://game.save", FileAccess.READ)
	while save_file.get_position() < save_file.get_length():
		var json_string: String = save_file.get_line()

		var json := JSON.new()
		var parse_result: int = json.parse(json_string)

		if parse_result != OK:
			print("JSON Parse Error: ", json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
			return false

		var data: Variant = json.data
		if typeof(data) != TYPE_DICTIONARY:
			return false

		print_debug(data)

		_grid.load(data)
		return true

	return false


func _init_music_list() -> void:
	if music_list.is_empty():
		return

	music_list.shuffle()
	_current_music_track = 0
	_bg_music.play()


func _save_top_score() -> void:
	print_debug("saving top score")

	var save_file: FileAccess = FileAccess.open("user://savegame.save", FileAccess.WRITE)
	var data := {
		top_score = _top_score
	}

	save_file.store_line(JSON.stringify(data))


func _load_top_score() -> void:
	print_debug("loading top score")

	if not FileAccess.file_exists("user://savegame.save"):
		return

	var save_file: FileAccess = FileAccess.open("user://savegame.save", FileAccess.READ)
	while save_file.get_position() < save_file.get_length():
		var json_string: String = save_file.get_line()
		var json := JSON.new()
		var parse_result: int = json.parse(json_string)

		if parse_result != OK:
			print("JSON Parse Error: ", json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
			return

		var data: Variant = json.data
		if typeof(data) != TYPE_DICTIONARY:
			return

		print_debug(data)
		_top_score = data.get("top_score", default_top_score)


func _on_grid_score_changed(score: int) -> void:
	if game_options.zen_mode:
		return

	_top_score = maxi(score, _top_score)
	_label_top_score.text = str(_top_score).lpad(score_min_length, "0")
	_label_score.text = str(score).lpad(score_min_length, "0")


func _on_grid_game_over() -> void:
	if game_options.zen_mode:
		await get_tree().create_timer(1.0).timeout
		_grid.restart()
		return

	_save_top_score()

	var stats: Dictionary = _grid.stats()
	_game_over_screen.display(stats.mx_combo, stats.mx_b2b, stats.tetrises, stats.t_spins)

	if not game_options.is_mobile:
		_post_score_request.post_score(_grid.score(), game_options.username)


func _on_grid_level_changed(level: int) -> void:
	_label_level.text = str(level)


func _on_pause_button_pressed() -> void:
	var paused: bool = get_tree().paused
	_pause_button.texture_normal = ARROW_TEXTURE if not paused else PAUSE_TEXTURE

	save_game()

	get_tree().paused = not paused
	_bg_music.stream_paused = _music_paused or not paused


func _on_grid_total_lines_cleared_changed(lines: int) -> void:
	_lines_label.text = str(lines)


func _on_grid_piece_locked(lines_cleared: int, is_perfect_clear: bool, t_spin: int) -> void:
	var messages: Array[String] = []

	if t_spin != Grid.NO_T_SPIN:
		var msg: String = "T SPIN MINI" if t_spin == Grid.T_SPIN_MINI else "T SPIN"

		if lines_cleared == 2:
			msg += " DOUBLE"
		elif lines_cleared == 3:
			msg += " TRIPLE"

		msg += "!"
		messages.push_back(msg)

	if t_spin == Grid.NO_T_SPIN and lines_cleared > 1:
		var words := ["DOUBLE", "TRIPLE", "TETRIS"]
		messages.push_back(words[lines_cleared - 2] + "!")

	if lines_cleared > 0 and _grid.back_to_back():
		_screen_submessage.text = "BACK 2 BACK"
		_screen_submessage.show()
		get_tree().create_timer(0.5).timeout.connect(_screen_submessage.hide)

	if is_perfect_clear:
		messages.push_back("PERFECT CLEAR!")

	if lines_cleared == 4:
		if _low_health_tween != null:
			_low_health_tween.kill()
			_low_health_tween = null

		var style: StyleBoxFlat = _grid_border.get_theme_stylebox("panel")
		var original_color: Color = Color("#585b70")
		var loops: int = 4

		var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_loops(loops)
		tween.tween_property(style, "border_color", Color("#cdd6f4"), 0.1)
		tween.tween_property(style, "border_color", original_color, 0.1)

	if messages.is_empty():
		return

	_screen_message.show()

	var tree: SceneTree = get_tree()
	for msg: String in messages:
		_screen_message.text = msg
		await tree.create_timer(0.5).timeout

	_screen_message.hide()


func _on_up_pressed() -> void:
	_grid.rotate_shape()


func _on_hard_drop_pressed() -> void:
	_grid.hard_drop()


func _on_grid_highest_row_changed(n: int) -> void:
	if game_options.zen_mode:
		return

	var style: StyleBoxFlat = _grid_border.get_theme_stylebox("panel")
	var original_color: Color = Color("#585b70")

	if n < 18:
		if _low_health_tween != null:
			_low_health_tween.kill()
			_low_health_tween = null

		if style.border_color != original_color:
			style.border_color = original_color
		return

	if _low_health_tween != null:
		return

	_low_health_tween = _grid_border.create_tween().set_trans(Tween.TRANS_CUBIC).set_loops()
	_low_health_tween.tween_property(style, "border_color", Color("#f38ba8"), 0.1).set_delay(0.1)
	_low_health_tween.tween_property(style, "border_color", original_color, 0.1).set_delay(0.1)


func _on_grid_combo_changed(n: int) -> void:
	_combo_label.text = str(n) + "!"
	_combo_container.visible = n > 0


func _on_grid_next_shapes_queue_changed(shapes: Array[ShapeRes]) -> void:
	for i: int in range(_next_shapes.size()):
		var curr: Shape = _next_shapes[i]
		var curr_res: ShapeRes = shapes[i]

		curr.hide()

		if i > shapes.size() - 1:
			break

		curr.res = curr_res
		_hack_shape_position(curr, curr_res)
		curr.show()


func _on_grid_hold_piece_changed(res: ShapeRes) -> void:
	_hold_shape.hide()

	if res == null:
		return

	_hold_shape.res = res
	_hack_shape_position(_hold_shape, res)
	_hold_shape.show()

	if not ["O", "I"].has(res.name) and not game_options.is_mobile:
		_hold_shape.position.y = 0
		_hold_shape.position.y += _grid.block_size.y / 2


func _hack_shape_position(instance: Shape, res: ShapeRes):
	var inst_scale: Vector2 = instance.scale
	instance.position = Vector2.ZERO

	if res.name == "O":
		instance.position -= (_grid.block_size / 2.0) * inst_scale
	elif res.name == "I":
		instance.position.x -= (_grid.block_size.x / 2.0) * inst_scale.x
	elif game_options.is_mobile:
		instance.position.y = (_grid.block_size.y / 2) * inst_scale.y


func _on_grid_can_swap_with_hold_changed(flag: bool) -> void:
	if not _hold_shape.visible:
		return

	await get_tree().process_frame

	if _grid.hold_piece() == null:
		return

	var color := _grid.hold_piece().color if flag else Color.GRAY
	_hold_shape.texture.gradient.set_color(0, color)
	_hold_shape.texture.gradient.set_color(1, color.darkened(0.5))


func _on_hold_pressed() -> void:
	_grid.hold_piece_swap()


func _on_game_over_screen_hidden() -> void:
	_grid.restart()


func _on_bg_music_finished() -> void:
	_bg_music.playing = true
	_current_music_track += 1
	_bg_music.play()


func _on_skip_previous_pressed() -> void:
	_bg_music.stop()
	_current_music_track -= 1
	_bg_music.play()


func _on_pause_play_pressed() -> void:
	_music_paused = not _music_paused


func _on_skip_next_pressed() -> void:
	_bg_music.stop()
	_current_music_track += 1
	_bg_music.play()


func _on_home_button_pressed() -> void:
	save_game()
	get_tree().change_scene_to_file("res://title/title.tscn")


func _on_exit_button_pressed() -> void:
	save_game()
	get_tree().change_scene_to_file("res://title/title.tscn")


func _on_post_scores_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug(result)
		return

	print_debug("post score status:", code)


func _on_undo_button_pressed() -> void:
	_grid.undo()

