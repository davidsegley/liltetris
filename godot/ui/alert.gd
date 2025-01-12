class_name Alert
extends PanelContainer

@export var default_icon: Texture = preload("res://assets/icons/warning_24dp.svg")

@onready var _icon := $MarginContainer/HBoxContainer/Icon as TextureRect
@onready var _text := $MarginContainer/HBoxContainer/Text as Label


func _ready() -> void:
	hide()


func display(msg: String, icon: Texture = null) -> void:
	_text.text = msg

	if icon != null:
		_icon.texture = icon
	else:
		_icon.texture = default_icon

	show()
	modulate = Color.WHITE

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	var delay: float = 2
	var time: float = 1

	tween.tween_property(self, "modulate", Color.TRANSPARENT, time).set_delay(delay)
	tween.tween_callback(hide)
