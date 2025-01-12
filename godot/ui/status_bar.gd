class_name StatusBar
extends PanelContainer

# Status bar

var username: String:
	set(value):
		assert(is_node_ready())
		_user_button.text = value

	get:
		assert(is_node_ready())
		return _user_button.text


var username_visible: bool:
	set(value):
		assert(is_node_ready())
		_back_button.visible = value

	get:
		assert(is_node_ready())
		return _back_button.visible

var _back_hist: Array[Callable] = []


@onready var _user_button := $MarginContainer/HBoxContainer/UserButton as Button
@onready var _back_button := $MarginContainer/HBoxContainer/BackButton as Button


func _ready() -> void:
	_back_button.hide()


func add_back_action(callback: Callable) -> void:
	_back_hist.push_back(callback)

	if not _back_button.visible:
		_back_button.show()


func _on_back_button_pressed() -> void:
	assert(_back_hist.size() > 0)

	var c: Callable = _back_hist.pop_back()
	c.call()

	if _back_hist.is_empty():
		_back_button.hide()

