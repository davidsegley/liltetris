class_name FormUsername
extends MarginContainer

# Username input

@export var state: LoginState = null

@onready var _username_field := $VBoxContainer/UsernameField as LineEdit


func _ready() -> void:
	_connect_state.call_deferred()


func _on_join_button_pressed() -> void:
	var username: String = _username_field.text.strip_edges()

	if username.count(" ") > 0:
		state.push_alert("Username must not contain spaces")
		return

	if username.is_empty():
		return

	if username.length() < 3:
		state.push_alert("Username must be at least 3 characters long")
		return

	state.username = _username_field.text
	state.go_to(LoginState.LOGIN_SUCCESS)


func _connect_state() -> void:
	state.changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	visible = state.current_screen == LoginState.USERNAME_INPUT
	_username_field.text = state.username

	if visible:
		_username_field.grab_focus()


func _on_username_field_text_submitted(_new_text: String) -> void:
	_on_join_button_pressed()

