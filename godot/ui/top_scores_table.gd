class_name TopScoresTable
extends PanelContainer

const PLACES: int = 10
const LABEL := preload("res://ui/top_score_label.tscn")

var _labels: Array[Label] = []

@onready var _box := $MarginContainer/VBoxContainer/GridContainer as GridContainer
@onready var _scores_request := $ScoresRequest as APIRequest
@onready var _timer := $Timer as Timer


func _ready() -> void:
	modulate = Color.TRANSPARENT

	_labels.resize(PLACES * 3)

	for child: Node in _box.get_children():
		child.queue_free()

	for i: int in range(PLACES * 3):
		var new_label: Label = LABEL.instantiate()
		new_label.modulate = Color.TRANSPARENT
		_box.add_child(new_label)

		_labels[i] = new_label

	_scores_request.request_completed.connect(_on_get_top_scores_completed)
	_scores_request.get_leaderboard()


func _on_get_top_scores_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug(result)
		return

	if code != 200:
		print_debug(code)
		return

	var response: Array = APIRequest.parse_body(body)
	var anim_time := 0.25
	var resp_idx := 0
	for i: int in range(0, PLACES * 3, 3):
		if resp_idx >= response.size():
			_labels[i].modulate = Color.TRANSPARENT
			_labels[i + 1].modulate = Color.TRANSPARENT
			_labels[i + 2].modulate = Color.TRANSPARENT
			continue

		var record = response[resp_idx]
		resp_idx += 1

		if not record is Dictionary:
			continue

		if _labels[i + 1].text == record.username and _labels[i + 2].text == str(record.score).rpad(6, "0"):
			continue

		_labels[i].text = str(resp_idx) + "."
		_labels[i + 1].text = record.username.strip_edges()
		_labels[i + 2].text = str(record.score).rpad(6, "0")

		for j: int in range(0, 3):
			_labels[i + j].modulate = Color.TRANSPARENT

			var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(_labels[i + j], "modulate", Color.WHITE, anim_time).set_delay((resp_idx) * anim_time)

	if _labels[0].visible:
		var other_tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		other_tween.tween_property(self, "modulate", Color.WHITE, anim_time)

	if _timer.is_stopped():
		_timer.start()


func _on_timer_timeout() -> void:
	_scores_request.get_leaderboard()

