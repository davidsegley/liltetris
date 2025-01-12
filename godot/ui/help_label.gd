class_name HelpLabel
extends MarginContainer


var undo_visible := true:
	set(value):
		if value == undo_visible or not is_node_ready():
			return

		undo_visible = value
		_undo.visible = value

@onready var  _undo := $VBoxContainer/HBoxContainer2/Undo
