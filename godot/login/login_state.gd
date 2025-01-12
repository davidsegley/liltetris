class_name LoginState
extends Resource

signal alert_pushed(text: String, icon: Texture)

enum {
	USERNAME_INPUT = 0,
	PASSWORD_PROMPT,
	LOGIN_SUCCESS,

	WANT_TO_JOIN,
	REGISTER,
	OPT_INPUT,
	STAY_ANONYMOUS,

	NEW_PASSWORD_OTP,
	NEW_PASSWORD_INPUT,

	NONE,
}

var current_screen: int = NONE:
	set(value):
		if value == current_screen:
			return

		current_screen = value
		emit_changed()

var username: String:
	set(value):
		username = value
		emit_changed()

var _screen_stack: Array[int] = []


func go_to(screen: int) -> void:
	_screen_stack.push_back(current_screen)
	current_screen = screen


func go_back() -> void:
	if _screen_stack.is_empty():
		return

	current_screen = _screen_stack.pop_back()


func push_alert(msg: String, icon: Texture = null) -> void:
	alert_pushed.emit(msg, icon)

