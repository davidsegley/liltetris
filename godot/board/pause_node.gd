extends Node

# Board pause node

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().paused = false
		get_tree().set_group(Grid.BLOCKS_GROUP, "visible", true)
		get_tree().set_group(Grid.SHAPES_GROUP, "visible", true)
		get_tree().set_group("visible_when_paused", "visible", false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	pass
