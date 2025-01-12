@tool
class_name Shape
extends Sprite2D

## Tetris shape

@export var res: ShapeRes = null:
	set(value):
		res = value

		if value == null:
			return

		_build_shape()

var is_ghost := false:
	set(value):
		is_ghost = value
		_set_colors()

var locked := false
var _about_to_lock_tween: Tween = null
var _current_rot: float =  0

@onready var lock_shader: Shader = preload("res://shaders/lock.gdshader")
@onready var hard_drop_particles := $HardDropParticles as GPUParticles2D


func _ready() -> void:
	self_modulate = Color.TRANSPARENT


func rot() -> float:
	return _current_rot


func rotate_shape(clockwise := true) -> void:
	var angle := 90.0 if clockwise else -90.0
	_current_rot = (_current_rot + angle as int) % 360

	angle = deg_to_rad(angle)

	for child: Node in get_children():
		if child is not Sprite2D or child.is_queued_for_deletion():
			continue

		var pos: Vector2 = child.position.rotated(angle)
		child.position = pos.round()


func coords() -> Array[Vector2i]:
	var texture_size: Vector2 = texture.get_size()
	var result: Array[Vector2i] = []

	for child: Node in get_children():
		if not child is Sprite2D or child.is_queued_for_deletion():
			continue

		var pos: Vector2 = (position + child.position) / texture_size
		result.push_back(pos.floor() as Vector2i)

	return result


func blocks() -> Dictionary:
	var result := {}
	var texture_size: Vector2 = texture.get_size()

	for child: Node in get_children():
		if not child is Sprite2D or child.is_queued_for_deletion():
			continue

		var pos: Vector2 = (position + child.position) / texture_size
		result[child] = pos.floor() as Vector2i

	return result


func center() -> Vector2i:
	return (position / texture.get_size()).floor() as Vector2i


func min_pos() -> Vector2:
	var result: Vector2 = Vector2.ZERO

	for pos: Vector2i in res.coords:
		result.x = min(result.x, pos.x)
		result.y = min(result.y, pos.y)

	return result


func play_lock_animation() -> void:
	var prev_shader: Shader = material.shader
	material.shader = lock_shader

	for child: Node in get_children():
		if not child is Sprite2D:
			continue

		child.material = material

	var callback := \
		func(color: Color, sp: Shape) -> void:
			sp.material.set_shader_parameter("solid_color", color)

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var time: float = 0.04
	var flash_color := Color("#bac2de")

	tween.tween_method(callback.bind(self), Color.TRANSPARENT, flash_color, time)
	tween.tween_method(callback.bind(self), flash_color, Color.TRANSPARENT, time)
	tween.tween_callback(
			func() -> void:
				if locked and not (hard_drop_particles != null && hard_drop_particles.emitting):
					queue_free()
	)

	await tween.finished

	material.shader = prev_shader


func play_about_to_lock_animation() -> void:
	stop_about_to_lock_animation()

	_about_to_lock_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_about_to_lock_tween.tween_property(self, "modulate", res.color.darkened(0.2), 0.5).set_delay(0.1)
	_about_to_lock_tween.tween_callback(set.bind("modulate", Color.WHITE))


func stop_about_to_lock_animation() -> void:
	if _about_to_lock_tween != null:
		_about_to_lock_tween.kill()
		_about_to_lock_tween = null

	modulate = Color.WHITE


func lock() -> void:
	locked = true


func _create_block(p_position: Vector2i = Vector2i.ZERO) -> void:
	var texture_size: Vector2 = texture.get_size()
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = texture
	sp.material = material
	sp.position = p_position * 1.0 * texture_size

	add_child(sp)


func _build_shape() -> void:
	for child: Node in get_children():
		if child is Sprite2D:
			child.queue_free()

	var st := {
		Vector2i.ZERO: true
	}

	assert(res != null)

	_create_block()
	for s: Vector2i in res.coords:
		assert(not st.has(s))

		_create_block(s)
		st[s] = true

	_set_colors.call_deferred()


func _set_colors() -> void:
	if res == null:
		return

	if is_ghost:
		texture.gradient.set_color(0, Color.TRANSPARENT)
		texture.gradient.set_color(1, res.color)
		modulate = Color(1.0, 1.0, 1.0, 0.5)
	else:
		texture.gradient.set_color(0, res.color)
		texture.gradient.set_color(1, res.color.darkened(0.5))
		modulate = Color.WHITE

	if is_node_ready():
		hard_drop_particles.texture.gradient.set_color(0, res.color)
		hard_drop_particles.texture.gradient.set_color(1, res.color)


func _on_hard_drop_particles_finished() -> void:
	hard_drop_particles.queue_free()

	if locked:
		queue_free()

