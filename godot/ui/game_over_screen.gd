class_name GameOverScreen
extends VBoxContainer

@onready var _mx_combo_label := $"%MxComboLabel" as Label
@onready var _mx_b2b_label := $"%MxB2BLabel" as Label
@onready var _tetrises_label := $"%TetrisesLabel" as Label
@onready var _t_spins_label := $"%TSpinsLabel" as Label
@onready var _reload_button := $ReloadButton as TextureButton


func display(combo: int, b2b: int, tetrises: int, t_spins: int) -> void:
	_mx_combo_label.text = str(combo)
	_mx_b2b_label.text = str(b2b)
	_tetrises_label.text = str(tetrises)
	_t_spins_label.text = str(t_spins)

	show()
	_reload_button.grab_focus()


func _on_texture_button_pressed() -> void:
	hide()

