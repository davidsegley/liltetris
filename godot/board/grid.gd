class_name Grid
extends PanelContainer

# Main play field

signal next_shapes_queue_changed(shapes: Array[ShapeRes])
signal score_changed(score: int)
signal level_changed(level: int)
signal total_lines_cleared_changed(lines: int)
signal piece_locked(n: int, is_perfect_clear: bool, t_spin: int)
signal combo_changed(n: int)
signal highest_row_changed(n: int)
signal hold_piece_changed(res: ShapeRes)
signal can_swap_with_hold_changed(flag: bool)
signal game_over

enum {
	NO_T_SPIN = 0,
	T_SPIN = 1,
	T_SPIN_MINI = 2,
}

const SHAPE := preload("res://shapes/shape.tscn")
const LINE_CLEARED_PARTICLES: PackedScene = preload("res://shapes/line_cleared_particles.tscn")
const BREAKING_PARTICLES: PackedScene = preload("res://shapes/breaking_particles.tscn")
const BLOCKS_GROUP := "blocks"
const SHAPES_GROUP := "shapes"
const GRID_LINES_GROUP := "grid_lines"

@export var piece_move_sound: AudioStream = preload("res://assets/SE/ui-button-click.wav")
@export var piece_rot_sound: AudioStream = preload("res://assets/SE/ui-button-click.wav")
@export var hard_drop_sound: AudioStream = preload("res://assets/SE/ui-button-click-snap.wav")
@export var line_clearing_sound: AudioStream = preload("res://assets/SE/49190__angel_perez_grandi__ice-breaking.wav")

@export var debug_trash: Array[PackedVector2Array] = []
@export var debug_inital_piece: ShapeRes = null

@export var detailed_animations := true
@export var zen_mode := false # No Score and no level

@export var t_spin_scores: PackedInt32Array = [400, 800, 1200, 1600]
@export var t_spin_mini_scores: PackedInt32Array = [100, 200, 400]

@export var max_level: int = 20
@export var initial_level: int = 1:
	set(value):
		initial_level = value
		_level = clampi(value, 1, max_level)

@export var max_lock_restarts: int = 8
@export var shapes: Array[ShapeRes] = []
@export var block_size := Vector2(40, 40)
@export var columns: int = 10
@export var rows: int = 20
@export var show_grid := false
@export var level_threshold: int = 10
@export var inital_timer_wait_time := 0.7:
	set(value):
		_gravity_wait_time = value
		inital_timer_wait_time = value

var _test: int = 0

var _gravity_timer: float = 0
var _gravity_wait_time := 0.7

var _active_shape: Shape = null
var _grid: Array[Array] = []

var _current_shape_res: ShapeRes = null
var _next_shapes_queue: Array[ShapeRes] = []
var _hold_piece: ShapeRes = null:
	set(value):
		_hold_piece = value
		hold_piece_changed.emit(value)

var _preview_shape: Shape = null
var _game_over := false
var _can_move := true
var _can_hard_drop := true
var _can_swap_with_hold := false:
	set(value):
		_can_swap_with_hold = value
		can_swap_with_hold_changed.emit(value)

var _combo: int = -1:
	set(value):
		if value == _combo:
			return

		_combo = value
		combo_changed.emit(maxi(_combo, 0))
		_mx_combo = maxi(value, _mx_combo)

var _back_to_back: int = -1:
	set(value):
		_back_to_back = value
		_mx_b2b = maxi(value, _mx_b2b)

var _score: int = 0:
	set(value):
		if zen_mode:
			return

		_score = value
		score_changed.emit(value)

var _level: int = initial_level:
	set(value):
		if zen_mode:
			return

		_level = clampi(value, 1, max_level)
		level_changed.emit(_level)

var _total_lines_cleared: int = 0:
	set(value):
		_total_lines_cleared = value
		total_lines_cleared_changed.emit(value)

		if _total_lines_cleared >= _level * level_threshold:
			increase_level()

var _lock_restarts: int = 0
var _shape_locked := false
var _line_cleared_particles: Array[GPUParticles2D] = []

# For T-Spins
var _last_movement_was_rotation := false
var _last_rotation_offset := Vector2.ZERO

# Used to keep track of how many times the piece is rotated at the same place
# if >= max_lock_restarts, then we lock the piece
var _rotation_pos_set := {}

# stats
var _mx_combo: int = 0
var _mx_b2b: int = 0
var _tetrises: int = 0
var _t_spins: int = 0

# undo history
var _hist: Array[Callable] = []

@onready var _lockdown_timer := $LockdownTimer as Timer
@onready var _audio_player := $AudioStreamPlayer as AudioStreamPlayer


func _ready() -> void:
	_grid.resize(rows)

	for i: int in range(rows):
		var arr: Array[Sprite2D] = []
		arr.resize(columns)
		arr.fill(null)

		_grid[i] = arr

	_line_cleared_particles.resize(rows)
	for i: int in range(rows):
		var particle: GPUParticles2D = LINE_CLEARED_PARTICLES.instantiate()
		particle.position = (Vector2(columns / 2.0, i) * block_size) + block_size / 2
		particle.z_index = 99
		add_child(particle)

		_line_cleared_particles[i] = particle

	if show_grid:
		_build_visual_grid.call_deferred()

	_debug_spawn_inital_trash.call_deferred()

	var min_sz := block_size * Vector2(columns, rows)
	print_debug(min_sz)

	set_deferred("custom_minimum_size", min_sz)


func _process(delta: float) -> void:
	if _active_shape == null:
		return

	_gravity_timer += delta

	if _gravity_timer >= _gravity_wait_time:
		_gravity_timer = 0
		move_shape(Vector2i(0, 1))


func move_shape(direction: Vector2i, soft_drop := false) -> void:
	if _active_shape == null or not _can_move or _game_over:
		return

	if direction == Vector2i.ZERO:
		return

	var blocks: Dictionary = _active_shape.blocks()
	var targets := {}
	var move_success := true

	for block: Sprite2D in blocks:
		var coord: Vector2i = blocks[block]
		var target: Vector2i = coord + direction

		targets[block] = target

		if target.x < 0 or target.x > columns - 1:
			move_success = false
			break

		if target.y < 0 or target.y > rows - 1:
			move_success = false
			break

		var cell: Sprite2D = _grid[coord.y][target.x]
		if cell != null and cell.get_parent() != _active_shape:
			move_success = false
			break

		cell = _grid[target.y][target.x]
		if cell != null and cell.get_parent() != _active_shape:
			move_success = false
			break

	if not move_success:
		if direction.x == 0:
			_start_lockdown()
		return

	_last_movement_was_rotation = false

	if _lockdown_timer.time_left > 0:
		var dist: int = _compute_floor_distance()

		if dist > 0:
			_active_shape.stop_about_to_lock_animation()
			_lockdown_timer.stop()
		else:
			_restart_lock_timer()

	var points_per_cell: int = 1

	if soft_drop:
		_score += points_per_cell * direction.y

	if not soft_drop and direction.x != 0:
		_play_sound(piece_move_sound)

	_active_shape.position += direction * 1.0 * block_size
	_update_ghost_piece()


func rotate_shape(clockwise := true) -> void:
	if _active_shape == null or not _can_move:
		return

	if not _current_shape_res.can_rotate:
		_restart_lock_timer()
		return

	var angle_before_rot: float = _active_shape.rot()
	_active_shape.rotate_shape(clockwise)
	var angle_after_rot: float = _active_shape.rot()

	# Check kickwall
	var blocks_after_rotation: Dictionary = _active_shape.blocks()

	var attemps: int = 5
	var table := KickWallTable.COMMON if _current_shape_res.name != "I" else KickWallTable.OTHER
	var rotation_success := false
	var from: int = floor(angle_before_rot / 90)
	var to: int = floor(angle_after_rot / 90)
	var last_rot_offset: Vector2 = Vector2.ZERO

	for i: int in range(attemps):
		# Swap Y negatives, y < 0 means up
		var target: Vector2i = (
			((table[from][i] * Vector2(1, -1)) - (table[to][i] * Vector2(1, -1))) as Vector2i
		)
		var good := true

		for coord: Vector2i in blocks_after_rotation.values():
			var c: Vector2i = coord + target

			if c.x < 0 or c.x > columns - 1:
				good = false
				break

			if c.y < 0 or c.y > rows - 1:
				good = false
				break

			var cell: Sprite2D = _grid[c.y][c.x]
			if cell != null and cell.get_parent() != _active_shape:
				good = false
				break

		if good:
			rotation_success = true
			last_rot_offset = table[to][i]

			# Update shape position
			_active_shape.position += target * 1.0 * block_size
			break

	_play_sound(piece_rot_sound)

	if not rotation_success:
		_active_shape.rotate_shape(not clockwise)
		return

	if _lockdown_timer.time_left > 0:
		var dist: float = _compute_floor_distance()

		if dist > 0:
			_active_shape.stop_about_to_lock_animation()
			_lockdown_timer.stop()
		else:
			_last_rotation_offset = last_rot_offset
			_restart_lock_timer()

	_last_movement_was_rotation = true
	_preview_shape.rotate_shape(clockwise)

	if _rotation_pos_set.has(_active_shape.position):
		_rotation_pos_set[_active_shape.position] += 1
	else:
		_rotation_pos_set[_active_shape.position] = 1

	if _rotation_pos_set[_active_shape.position] >= max_lock_restarts:
		_lock_piece()

	_update_ghost_piece()


func hard_drop() -> void:
	if not _can_hard_drop:
		return

	if _active_shape == null or not _can_move or _game_over:
		return

	var coords: Array[Vector2i] = _active_shape.coords()
	for coord: Vector2i in coords:
		var c := coord
		_grid[c.y][c.x] = null

	_can_move = false

	var dist: int = _compute_floor_distance()

	if dist > 0:
		_last_movement_was_rotation = false
		_lockdown_timer.stop()
		_preview_shape.hide()

		if detailed_animations:
			var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT_IN)
			var final_val := _active_shape.position + Vector2(0, dist) * block_size
			var time := 0.07

			tween.tween_property(_active_shape, "position", final_val, time)
			await tween.finished
		else:
			_active_shape.position += Vector2(0, dist) * block_size

	var points_per_cell: int = 2
	_score += dist * points_per_cell
	_active_shape.hard_drop_particles.emitting = true
	_active_shape.stop_about_to_lock_animation()
	_lock_piece.call_deferred(detailed_animations)


func hold_piece() -> ShapeRes:
	return _hold_piece


func hold_piece_swap() -> void:
	if not _can_swap_with_hold or _game_over or not _can_move:
		return

	var tmp: ShapeRes = _hold_piece
	_hold_piece = _current_shape_res
	_hist.push_back(_undo_hold.bind(tmp))

	_active_shape.queue_free()
	_spawn_shape(tmp)
	_can_swap_with_hold = false


func start() -> void:
	_spawn_shape.call_deferred(debug_inital_piece)


func restart() -> void:
	_gravity_wait_time = inital_timer_wait_time
	_score = 0
	_combo = -1
	_back_to_back = -1
	_level = initial_level
	_total_lines_cleared = 0
	_hold_piece = null
	_game_over = false
	_mx_combo = 0
	_mx_b2b = 0
	_tetrises = 0
	_t_spins = 0
	_next_shapes_queue.clear()
	_hist.clear()

	if show_grid:
		get_tree().call_group(GRID_LINES_GROUP, "show")

	for y: int in range(_grid.size()):
		for block: Sprite2D in _grid[y]:
			if block != null:
				block.queue_free()

		_grid[y].fill(null)

	_spawn_shape(debug_inital_piece)


# Undo the last movement
func undo() -> void:
	if _hist.is_empty():
		return

	var f: Callable = _hist.pop_back()
	f.call()


func has_undo() -> bool:
	return _hist.size() > 0


func level() -> int:
	return _level


func increase_level() -> void:
	_level = mini(_level + 1, max_level)
	_update_gravity()


func back_to_back() -> bool:
	return _back_to_back > 0


func stats() -> Dictionary:
	return {
		mx_combo = _mx_combo,
		mx_b2b = _mx_b2b,
		tetrises = _tetrises,
		t_spins = _t_spins
	}


func score() -> int:
	return _score


func save() -> Dictionary:
	var minos: Array[String] = []
	minos.assign(_next_shapes_queue.map(func(e: ShapeRes) -> String: return e.name))

	var result = {
		properties = {
			_total_lines_cleared = _total_lines_cleared,
			_combo = _combo,
			_back_to_back = _back_to_back,
			_level = _level,
			_score = _score,
			_lock_restarts = _lock_restarts,

			_mx_combo = _mx_combo,
			_mx_b2b = _mx_b2b,
			_tetrises = _tetrises,
			_t_spins = _t_spins,
			_last_movement_was_rotation = _last_movement_was_rotation,
			_can_swap_with_hold = _can_swap_with_hold,
			show_grid = show_grid,
			_can_move = _can_move,
		},
		blocks = [],

		# Vectors are not supported by json :(
		last_rotation_offset_x = _last_rotation_offset.x,
		last_rotation_offset_y = _last_rotation_offset.y,
		next_queue = minos,
		hold_piece = _hold_piece.name if _hold_piece != null else "",
		current_piece = _current_shape_res.name
	}

	var tree: SceneTree = get_tree()
	var blocks: Array[Node] = tree.get_nodes_in_group(BLOCKS_GROUP)
	for block: Sprite2D in blocks:
		result.blocks.push_back(_get_block_save_data(block))

	return result


func load(state: Dictionary) -> void:
	var props: Dictionary = state.get("properties", {})

	for key: StringName in props.keys():
		set(key, props[key])

	_last_rotation_offset = Vector2(state.last_rotation_offset_x, state.last_rotation_offset_y)

	var minos := {}
	for shape: ShapeRes in shapes:
		minos[shape.name] = shape

	for mino: String in state.next_queue:
		_next_shapes_queue.push_back(minos[mino])

	next_shapes_queue_changed.emit(_next_shapes_queue)
	_hold_piece = minos.get(state.hold_piece, null)
	can_swap_with_hold_changed.emit(_can_swap_with_hold)

	var blocks: Array[Dictionary] = []
	blocks.assign(state.get("blocks", []))

	_restore_blocks_data(blocks)
	_spawn_shape(minos[state.current_piece])


func _build_visual_grid() -> void:
	var line_width: float = 5
	var line_color := Color("#494d64", 0.5)

	for i: int in range(1, columns):
		# Vertical lines
		var line := Line2D.new()
		line.add_point(Vector2(i * block_size.x, 2 * block_size.y))
		line.add_point(Vector2(i * block_size.x, rows * block_size.x))
		line.width = line_width
		line.default_color = line_color
		add_child(line)
		line.add_to_group(GRID_LINES_GROUP)

	for i: int in range(2, rows):
		# Horizontal lines
		var line := Line2D.new()
		line.width = line_width
		line.default_color = line_color
		line.add_point(Vector2(0, i * block_size.y))
		line.add_point(Vector2(columns * block_size.x, i * block_size.y))
		add_child(line)
		line.add_to_group(GRID_LINES_GROUP)


func _debug_spawn_inital_trash() -> void:
	if debug_trash.is_empty():
		return

	for spawn: Vector2i in debug_trash[_test]:
		spawn.y += 2

		assert(spawn.x >= 0 and spawn.x < columns and spawn.y >= 0 and spawn.y < rows)
		var piece: Shape = SHAPE.instantiate()
		piece.add_to_group(SHAPES_GROUP)
		piece.position = (spawn * 1.0 * block_size) + block_size / 2
		_grid[spawn.y][spawn.x] = piece.get_children()[0]
		add_child(piece)

	_test += 1


func _compute_highest_not_empty_row() -> void:
	for y: int in range(rows):
		for x: int in range(columns):
			if _grid[y][x] != null:
				highest_row_changed.emit(rows - y)
				return

	highest_row_changed.emit(0)


func _spawn_shape(shape: ShapeRes = null) -> void:
	_can_move = false
	_gravity_timer = 0
	_can_hard_drop = false
	_active_shape = null
	_can_swap_with_hold = true
	_last_movement_was_rotation = false
	_last_rotation_offset = Vector2.ZERO
	_lockdown_timer.stop()
	_rotation_pos_set.clear()

	if _next_shapes_queue.is_empty():
		_generate_next_shapes()

	var rand_shape: ShapeRes = _next_shapes_queue.pop_front() if shape == null else shape

	if shape == null and _next_shapes_queue.size() <= shapes.size():
		_generate_next_shapes()

	_current_shape_res = rand_shape

	_active_shape = SHAPE.instantiate()
	_active_shape.z_index = 1
	_active_shape.res = rand_shape
	_active_shape.add_to_group(SHAPES_GROUP)

	var min_pos := _active_shape.min_pos()
	var inital_pos := Vector2i((columns as float / 2) as int, abs(min_pos.y) + 1)

	if rand_shape.name == "I":
		inital_pos.y += 1

	_active_shape.position = (inital_pos * 1.0 * block_size) - block_size / 2
	add_child(_active_shape)

	await get_tree().process_frame

	var coords: Array[Vector2i] = _active_shape.coords()
	for coord: Vector2i in coords:
		var cell: Sprite2D = _grid[coord.y][coord.x]
		if cell != null:
			_game_over = true
			await _play_game_over_animation()
			highest_row_changed.emit(0)
			game_over.emit()
			return

	if _preview_shape == null:
		_preview_shape = SHAPE.instantiate()
		add_child(_preview_shape)

		_preview_shape.z_index = 0
		_preview_shape.is_ghost = true
		_preview_shape.add_to_group(SHAPES_GROUP)

	_preview_shape.material = null
	_preview_shape.res = rand_shape
	_preview_shape.position = _active_shape.position
	_preview_shape.show()
	_can_move = true
	_shape_locked = false

	next_shapes_queue_changed.emit(_next_shapes_queue)

	var callback := \
			func() -> void:
				_can_hard_drop = true

	# Prevent accidental drops
	get_tree().create_timer(0.1).timeout.connect(callback, CONNECT_ONE_SHOT)

	_update_ghost_piece()


func _compute_floor_distance() -> int:
	if _active_shape == null:
		return 0

	var blocks: Dictionary = _active_shape.blocks()
	var i: int = 1

	while true:
		var direction := Vector2i(0, i)
		var good := true

		for block: Sprite2D in blocks:
			var coord: Vector2i = blocks[block]
			var target = coord + direction

			if target.y > rows - 1:
				good = false
				break

			var cell: Sprite2D = _grid[target.y][target.x]
			if cell != null and cell.get_parent() != _active_shape:
				good = false
				break

		if not good:
			break

		i += 1

	return i - 1


func _drop_blocks(full_rows: Dictionary) -> Dictionary:
	# Pull down the blocks above the affected lines
	var blocks := {}
	var fall: int = 1
	var lowest_line: int = 0

	for i: int in full_rows.keys():
		lowest_line = maxi(i, lowest_line)

	for i: int in range(lowest_line - 1, -1, -1):
		if full_rows.has(i):
			fall += 1
			continue

		for sp: Sprite2D in _grid[i]:
			if sp == null:
				continue

			var new_pos: Vector2 = _move_block_downwards(sp, fall)
			blocks[sp] = new_pos

	# Perfect clear
	if blocks.is_empty():
		return {}

	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel()

	var time := 0.05
	var blocks_before_fall := {}
	for b in blocks.keys():
		var final_val: Vector2 = blocks[b]
		tween.tween_property(b, "position", final_val, time)

		# Ignore blocks from the current mino
		if b.get_parent() == self:
			blocks_before_fall[final_val] = b.position

	await tween.finished
	return blocks_before_fall


func _detailed_lines_clearing_animation(full_rows: Dictionary) -> void:
	var time := 0.05
	var delay := 0.05
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel()

	for row: Array[Sprite2D] in full_rows.values():
		var idx: int = 0
		var reverse := randi_range(0, 1) == 1
		if reverse:
			row.reverse()

		for sprite: Sprite2D in row:
			assert(sprite != null)

			var particles: GPUParticles2D = BREAKING_PARTICLES.instantiate()
			add_child(particles)

			particles.global_position = sprite.global_position
			particles.emitting = true
			particles.z_index = 999

			particles.finished.connect(particles.queue_free)

			if not reverse:
				particles.scale.x *= -1

			var particles_gradient: Gradient = particles.texture.gradient
			var sprite_gradient: Gradient = sprite.texture.gradient

			particles_gradient.set_color(0, sprite_gradient.get_color(0))
			particles_gradient.set_color(1, sprite_gradient.get_color(0))

			tween.tween_property(sprite, "modulate", Color.TRANSPARENT, time).set_delay(idx * delay)

			idx += 1

	await tween.finished


func _simple_line_clearing_animation(full_rows: Dictionary) -> void:
	for i: int in full_rows.keys():
		_line_cleared_particles[i].emitting = true

		for sprite: Sprite2D in full_rows[i]:
			sprite.hide()


func _move_block_downwards(block: Sprite2D, cells: int) -> Vector2:
	assert(block != null && cells > 0 and not block.is_queued_for_deletion())

	var parent: Node = block.get_parent()
	var parent_pos: Vector2 = parent.position if parent != self else Vector2.ZERO

	var coord: Vector2i = ((block.position + parent_pos) / block_size).floor() as Vector2i
	var target := coord + Vector2i(0, cells)

	assert(target.y <= rows - 1)

	var cell: Sprite2D = _grid[target.y][target.x]
	assert(cell == null)

	# Update grid
	_grid[coord.y][coord.x] = null
	_grid[target.y][target.x] = block

	return block.position + (Vector2(0, cells) * block_size)


func _start_lockdown() -> void:
	if _lockdown_timer.time_left > 0:
		return

	_lock_restarts = 0
	_lockdown_timer.start()
	_active_shape.play_about_to_lock_animation()


func _restart_lock_timer() -> void:
	if _lockdown_timer.time_left == 0:
		return

	if _lock_restarts >= max_lock_restarts:
		return

	_lockdown_timer.start()
	_lock_restarts += 1
	_active_shape.play_about_to_lock_animation()


func _lock_piece(from_hard_drop := false) -> void:
	if _active_shape == null or _shape_locked:
		return

	_active_shape.stop_about_to_lock_animation()

	var dist: int = _compute_floor_distance()
	if dist != 0:
		return

	_preview_shape.hide()
	_lockdown_timer.stop()
	_can_move = false
	_shape_locked = true
	_can_hard_drop = false

	_play_sound(hard_drop_sound)

	var blocks: Dictionary = _active_shape.blocks()
	var touched := {}

	for block: Sprite2D in blocks.keys():
		var pos: Vector2i = blocks[block]
		touched[pos.y] = true
		assert(_grid[pos.y][pos.x] == null)

		_grid[pos.y][pos.x] = block

	var full_rows := {}
	for i: int in touched.keys():
		var full := true
		for sp: Sprite2D in _grid[i]:
			if sp == null:
				full = false
				break

		if full:
			full_rows[i] = _grid[i].duplicate()
			_grid[i].fill(null)

	var lines_cleared: int = full_rows.size()
	var positions_to_restore := {}

	if lines_cleared > 0:
		await _play_lines_clearing_animation(full_rows)
		positions_to_restore = await _drop_blocks(full_rows)

		_combo += 1
	else:
		_combo = -1

		if not from_hard_drop:
			_active_shape.play_lock_animation()

	# For undo operations
	var blocks_to_delete: Array[Vector2i] = []
	var blocks_to_restore: Array[Dictionary] = []

	# Delete blocks in full rows
	for row: Array[Sprite2D] in full_rows.values():
		for sprite: Sprite2D in row:
			sprite.queue_free()

			if sprite.get_parent() == self:
				var save_data: Dictionary = _get_block_save_data(sprite)
				blocks_to_restore.push_back(save_data)

	# Reparent block from the locked piece
	# NOTE: Reparent occurs after all animations have finished;
	# otherwise the game will freeze
	for block: Sprite2D in _active_shape.blocks().keys():
		block.reparent(self)
		block.add_to_group(BLOCKS_GROUP)
		blocks_to_delete.push_back((block.position / block_size).floor() as Vector2i)

	if zen_mode:
		var args: Array = [
			_current_shape_res,
			blocks_to_restore,
			blocks_to_delete,
			positions_to_restore,
			_combo
		]

		_hist.push_back(_undo_lock.bindv(args))

	_active_shape.lock()

	var was_t_spin: int = _was_t_spin()
	var is_perfect_clear: bool = _is_perfect_clear()

	if lines_cleared > 0:
		if was_t_spin != NO_T_SPIN or lines_cleared == 4 or is_perfect_clear:
			_back_to_back += 1
		else:
			_back_to_back = -1

	_score += _compute_score(lines_cleared, is_perfect_clear, was_t_spin)
	piece_locked.emit(lines_cleared, is_perfect_clear, was_t_spin)
	_total_lines_cleared += lines_cleared

	if was_t_spin != NO_T_SPIN:
		_t_spins += 1

	if lines_cleared == 4:
		_tetrises += 1

	_compute_highest_not_empty_row()

	if _test < debug_trash.size():
		get_tree().call_group(BLOCKS_GROUP, "queue_free")
		for y: int in range(_grid.size()):
			_grid[y].fill(null)

		_debug_spawn_inital_trash()
		_spawn_shape(debug_inital_piece)
		return

	_spawn_shape()


func _was_t_spin() -> int:
	if _current_shape_res.name != "T" or not _last_movement_was_rotation:
		return NO_T_SPIN

	var center: Vector2i = _active_shape.center()
	var blocks_in_front: int = 0

	# Check front
	for i: int in [-1, 1]:
		var check := ((center * 1.0) + Vector2(i, -1)) as Vector2i

		if _grid[check.y][check.x] != null:
			blocks_in_front += 1

	if blocks_in_front == 0:
		return NO_T_SPIN

	# Check back
	var blocks_in_back: int = 0
	for i: int in [-1, 0, 1]:
		var check = ((center * 1.0) + Vector2(i, 1)) as Vector2i

		if check.x < 0 or check.x > columns - 1 or check.y < 0 or check.y > rows - 1:
			blocks_in_back += 1
			continue

		if _grid[check.y][check.x] != null:
			blocks_in_back += 1

	if blocks_in_back == 0:
		return NO_T_SPIN

	if blocks_in_front == 1 and not abs(_last_rotation_offset.y) != 2:
		return T_SPIN_MINI

	return T_SPIN


func _is_perfect_clear() -> bool:
	# If no bugs happen then we only have to check the bottom line of the grid
	for block: Sprite2D in _grid[rows - 1]:
		if block != null:
			return false

	return true


func _play_lines_clearing_animation(full_rows: Dictionary) -> void:
	if full_rows.is_empty():
		return

	_play_sound(line_clearing_sound)

	if full_rows.size() == 4:
		Input.vibrate_handheld()

	if detailed_animations:
		await _detailed_lines_clearing_animation(full_rows)
	else:
		_simple_line_clearing_animation(full_rows)


func _compute_score(p_lines_cleared: int, perfect_clear: bool, t_spin: int) -> int:
	assert(p_lines_cleared <= 4 and _level != 0)

	var scores: Array[int] = [0, 100, 300, 500, 800]
	var res: int = scores[p_lines_cleared] * _level

	if p_lines_cleared > 0:
		res += (maxi(0, _combo) * 50 * _level)

	if perfect_clear:
		var actions: Array[int] = [0, 800, 1200, 1800, 2000]
		res += actions[p_lines_cleared] * _level

		# Tetris perfect clear back 2 back
		if p_lines_cleared == 4 and _back_to_back > 0:
			res += 1200

	if t_spin == T_SPIN:
		res += t_spin_scores[p_lines_cleared]
	elif t_spin == T_SPIN_MINI:
		assert(p_lines_cleared < 4)
		res += t_spin_mini_scores[p_lines_cleared]

	if _back_to_back > 0 and not perfect_clear:
		res = round(res * 1.5)

	return res


func _update_gravity() -> void:
	_gravity_wait_time = inital_timer_wait_time - (inital_timer_wait_time / max_level) * _level
	_gravity_wait_time = max(_gravity_wait_time, 0.01)


func _play_game_over_animation() -> void:
	get_tree().call_group(GRID_LINES_GROUP, "hide")
	get_tree().call_group(BLOCKS_GROUP, "queue_free")
	get_tree().call_group(SHAPES_GROUP, "queue_free")

	for y: int in range(_grid.size()):
		_grid[y].fill(null)

	for y: int in range(rows - 1, -1, -1):
		_line_cleared_particles[y].emitting = true

	await get_tree().create_timer(1.0).timeout


func _generate_next_shapes() -> void:
	var n: int = shapes.size()
	var bag: Array[ShapeRes] = []
	bag.resize(n)

	for i: int in range(n):
		bag[i] = shapes[i]

	bag.shuffle()
	_next_shapes_queue.append_array(bag)


func _on_lockdown_timer_timeout() -> void:
	_lock_piece.call_deferred()


func _play_sound(stream: AudioStream) -> void:
	_audio_player.stream = stream
	_audio_player.pitch_scale = randf_range(0.8, 1.2)
	_audio_player.play()


func _undo_lock(mino: ShapeRes, deleted_blocks: Array[Dictionary],
			to_delete_blocks: Array[Vector2i], positions_to_restore: Dictionary, combo_to_restore: int) -> void:
	assert(_current_shape_res != null)
	_active_shape.queue_free()
	_next_shapes_queue.push_front(_current_shape_res)
	_combo = combo_to_restore

	for coord: Vector2i in to_delete_blocks:
		var block: Sprite2D = _grid[coord.y][coord.x]
		assert(block != null)
		block.queue_free()

		_grid[coord.y][coord.x] = null

	# Must be from top to bottom
	var positions_reversed := positions_to_restore.keys()
	positions_reversed.reverse()

	var blocks := {}

	for pos: Vector2 in positions_reversed:
		var original_pos: Vector2 = positions_to_restore[pos]

		# traslate to grid coordinates
		var coord: Vector2i = (pos / block_size).floor() as Vector2i
		var target: Vector2i = (original_pos / block_size).floor() as Vector2i

		var sp: Sprite2D = _grid[coord.y][coord.x]
		assert(sp != null, "wtf")

		blocks[sp] = original_pos
		_grid[coord.y][coord.x] = null
		_grid[target.y][target.x] = sp

	_spawn_shape(mino)
	var new_blocks: Array[Sprite2D] = _restore_blocks_data(deleted_blocks)

	if new_blocks.is_empty() and blocks.is_empty():
		return # no animation

	var time: = 0.05
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel()

	if not blocks.is_empty():
		for sprite: Sprite2D in blocks.keys():
			var final_val: Vector2 = blocks[sprite]
			tween.tween_property(sprite, "position", final_val, time)

	for sprite: Sprite2D in new_blocks:
		sprite.scale.y = 0
		tween.tween_property(sprite, "scale:y", 1.0, time)


func _undo_hold(prev: ShapeRes) -> void:
	_active_shape.queue_free()

	if prev == null:
		_next_shapes_queue.push_front(_current_shape_res)
		_spawn_shape(_hold_piece)
		_hold_piece = null
		_can_swap_with_hold = true
		return

	_spawn_shape(_hold_piece)
	_hold_piece = prev


func _get_block_save_data(block: Sprite2D) -> Dictionary:
	var res := {
		position_x = block.position.x,
		position_y = block.position.y,
		color = block.texture.gradient.get_color(0).to_html()
	}

	return res


func _restore_blocks_data(data: Array[Dictionary]) -> Array[Sprite2D]:
	var dummy_shape := SHAPE.instantiate()
	var instances: Array[Sprite2D] = []

	for block: Dictionary in data:
		assert(block.has("color"))
		assert(block.has("position_x"))
		assert(block.has("position_y"))

		var sp := Sprite2D.new()
		sp.add_to_group(BLOCKS_GROUP)
		sp.texture = dummy_shape.texture.duplicate(true)
		sp.material = dummy_shape.material

		var color := Color.html(block.color)
		sp.texture.gradient.set_color.call_deferred(0, color)
		sp.texture.gradient.set_color.call_deferred(1, color.darkened(0.5))

		var pos: Vector2 = Vector2(block.position_x, block.position_y)
		sp.position = pos

		var coord: Vector2i = (pos / block_size).floor()
		_grid[coord.y][coord.x] = sp

		add_child(sp)
		instances.push_back(sp)

	dummy_shape.queue_free()
	return instances


func _update_ghost_piece():
	if _preview_shape == null or _active_shape == null:
		return

	var i: int = _compute_floor_distance()
	_preview_shape.position = _active_shape.position + Vector2(0, i * block_size.y)
