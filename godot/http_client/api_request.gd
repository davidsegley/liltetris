class_name APIRequest
extends HTTPRequest

# default api request

# NOTE: Must be updated 💀
static var base_url: String = "http://localhost:8080/api/"


func _ready() -> void:
	pass


func get_leaderboard() -> void:
	var endpoint := base_url + "leaderboard"
	var error: int = request(endpoint)
	print_debug("request: ", error)


func post_score(score: int, username: String) -> void:
	var endpoint := base_url + "leaderboard"
	var body: String = JSON.stringify({
		score = score,
		username = username
	})

	var headers := [
		"Content-Type: application/json",
	]

	print_debug(body)
	var error: int = request(endpoint, headers, HTTPClient.METHOD_POST, body)
	print_debug("request: ", error)


static func parse_body(body: PackedByteArray) -> Variant:
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var response = json.data
	print_debug(response)

	if response == null:
		return {}

	return response
