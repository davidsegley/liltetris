extends Control

@export var state: LoginState = null
@export var game_options: GameOptions = null

@onready var _alert := $Alert as Alert


func _ready() -> void:
	var mobile_oses: PackedStringArray = ["Android", "iOS"]
	var os_name: String = OS.get_name()
	print_debug(os_name)

	game_options.is_mobile = game_options.is_mobile or mobile_oses.has(os_name)

	if game_options.is_mobile:
		# No login required
		_go_to_title.call_deferred()
		return

	_connect_state.call_deferred()


func _connect_state() -> void:
	assert(state != null)
	state.changed.connect(_on_state_changed)
	state.alert_pushed.connect(_on_alert_pushed)
	state.current_screen = LoginState.USERNAME_INPUT


func _on_state_changed() -> void:
	if state.current_screen == LoginState.LOGIN_SUCCESS:
		game_options.username = state.username
		get_tree().change_scene_to_file("res://title/title.tscn")


func _go_to_title() -> void:
	get_tree().change_scene_to_file("res://title/title.tscn")


func _on_alert_pushed(text: String, icon: Texture) -> void:
	_alert.display(text, icon)

