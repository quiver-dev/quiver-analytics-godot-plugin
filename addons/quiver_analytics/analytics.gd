extends Node
## Handles sending events to Quiver Analytics (https://quiver.dev/analytics/).
##
## This class manages a request queue, which the plugin user can populate with events.
## Events are sent to the Quiver server one at a time.
## This class manages spacing out requests so as to not overload the server
## and to prevent performance issues in the game.
## If events are not able to be sent due to network connection issues,
## the events are saved to disk when the game exits.
##
## This implementation favors performance over accuracy, so events may be dropped if
## they could lead to performance issues.


## Use this to pick a random player identifier
const MAX_INT := 9223372036854775807

## The maximum rate we can add events to the queue.
## If this limit is exceeded, requests will be dropped.
const MAX_ADD_TO_EVENT_QUEUE_RATE := 50

## This controls the maximum size of the request queue that is saved to disk
## in the situation the events weren't able to be successfully sent.
## In pathological cases, we may drop events if the queue grows too long.
const MAX_QUEUE_SIZE_TO_SAVE_TO_DISK := 200

## The file to store queue events that weren't able to be sent due to network or server issues
const QUEUE_FILE_NAME := "user://analytics_queue"

## The server host
const SERVER_PATH := "https://quiver.dev"

## The URL for adding events
const ADD_EVENT_PATH := "/analytics/events/add/"

## Event names can't exceed this length
const MAX_EVENT_NAME_LENGTH := 50

# The next two parameters guide how often we send artifical quit events.
# We send these fake quit events because on certain platfomrms (mobile and web),
# it can be hard to determine when a player ended the game (e.g. they background the app or close a tab).
# So we just send periodic quit events with session IDs, which are reconciled by the server.

# We send a quit event this many seconds after launching the game.
# We set this fairly low to handle immediate bounces from the game.
const INITIAL_QUIT_EVENT_INTERVAL_SECONDS := 10

# This is the max interval between sending quit events
const MAX_QUIT_EVENT_INTERVAL_SECONDS := 60

## Emitted when the sending the final events have been completed
signal exit_handled


var auth_token = ProjectSettings.get_setting("quiver/general/auth_token", "")
var config_file_path := ProjectSettings.get_setting("quiver/analytics/config_file_path", "user://analytics.cfg")
var consent_required = ProjectSettings.get_setting("quiver/analytics/player_consent_required", false)
var consent_requested = false
var consent_granted = false
var consent_dialog_scene := preload("res://addons/quiver_analytics/consent_dialog.tscn")
var consent_dialog_showing := false
var data_collection_enabled := false
var config = ConfigFile.new()
var player_id: int
var time_since_first_request_in_batch := Time.get_ticks_msec()
var requests_in_batch_count := 0
var request_in_flight := false
var request_queue: Array[Dictionary] = []
var should_drain_request_queue := false
var min_retry_time_seconds := 2.0
var current_retry_time_seconds := min_retry_time_seconds
var max_retry_time_seconds := 120.0
var auto_add_event_on_launch := ProjectSettings.get_setting("quiver/analytics/auto_add_event_on_launch", true)
var auto_add_event_on_quit := ProjectSettings.get_setting("quiver/analytics/auto_add_event_on_quit", true)
var quit_event_interval_seconds := INITIAL_QUIT_EVENT_INTERVAL_SECONDS
var session_id = abs(randi() << 32 | randi())

# Note that use_threads has to be turned off on this node because otherwise we get frame rate hitches
# when the request is slow due to server issues.
# Not sure why yet, but might be related to https://github.com/godotengine/godot/issues/33479.
@onready var http_request := $HTTPRequest
@onready var retry_timer := $RetryTimer
@onready var quit_event_timer := $QuitEventTimer

func _ready() -> void:
	# We attempt to load the saved configuration, if present
	var err = config.load(config_file_path)
	if err == OK:
		player_id = config.get_value("general", "player_id")
		consent_granted = config.get_value("general", "granted")
		if player_id and player_id is int:
			# We use the hash as a basic (but easily bypassable) protection to reduce
			# the chance that the player ID has been tampered with.
			var hash = str(player_id).sha256_text()
			if hash != config.get_value("general", "hash"):
				DirAccess.remove_absolute(config_file_path)
				_init_config()
	else:
		# If we don't have a config file, we create one now
		_init_config()

	# Check to see if data collection is possible
	if auth_token and (!consent_required or consent_granted):
		data_collection_enabled = true

	# Let's load any saved events from previous sessions
	# and start processing them, if available.
	_load_queue_from_disk()
	if not request_queue.is_empty():
		DirAccess.remove_absolute(QUEUE_FILE_NAME)
		_process_requests()

	if auto_add_event_on_launch:
		add_event("Launched game")
	if auto_add_event_on_quit:
		quit_event_timer.start(quit_event_interval_seconds)

#	if auto_add_event_on_quit:
#		get_tree().set_auto_accept_quit(false)


## Whether we should be obligated to show the consent dialog to the player
func should_show_consent_dialog() -> bool:
	return consent_required and not consent_requested


## Show the consent dialog to the user, using the passed in node as the parent
func show_consent_dialog(parent: Node) -> void:
	if not consent_dialog_showing:
		consent_dialog_showing = true
		var consent_dialog: ConsentDialog = consent_dialog_scene.instantiate()
		parent.add_child(consent_dialog)
		consent_dialog.show_with_animation()


## Call this when consent has been granted.
## The ConsentDialog scene will manage this automatically.
func approve_data_collection() -> void:
	consent_requested = true
	consent_granted = true
	config.set_value("general", "requested", consent_requested)
	config.set_value("general", "granted", consent_granted)
	config.save(config_file_path)


## Call this when consent has been denied.
## The ConsentDialog scene will manage this automatically.
func deny_data_collection() -> void:
	if consent_granted:
		consent_requested = true
		consent_granted = false
		#if FileAccess.file_exists(CONFIG_FILE_PATH):
		#	DirAccess.remove_absolute(CONFIG_FILE_PATH)
		config.set_value("general", "requested", consent_requested)
		config.set_value("general", "granted", consent_granted)
		config.save(config_file_path)


## Use this track an event. The name must be 50 characters or less.
## You can pass in an arbitrary dictionary of properties.
func add_event(name: String, properties: Dictionary = {}) -> void:
	if not data_collection_enabled:
		_process_requests()
		return

	if name.length() > MAX_EVENT_NAME_LENGTH:
		printerr("[Quiver Analytics] Event name '%s' is too long. Must be %d characters or less." % [name, MAX_EVENT_NAME_LENGTH])
		_process_requests()
		return

	# We limit big bursts of event tracking to reduce overusage due to buggy code
	# and to prevent overloading the server.
	var current_time_msec = Time.get_ticks_msec()
	if (current_time_msec - time_since_first_request_in_batch) > 60 * 1000:
		time_since_first_request_in_batch = current_time_msec
		requests_in_batch_count = 0
	else:
		requests_in_batch_count += 1
	if requests_in_batch_count > MAX_ADD_TO_EVENT_QUEUE_RATE:
		printerr("[Quiver Analytics] Event tracking was disabled temporarily because max event rate was exceeded.")
		return

	# Auto-add default properties
	properties["$platform"] = OS.get_name()
	properties["$session_id"] = session_id
	properties["$debug"] = OS.is_debug_build()
	properties["$export_template"] = OS.has_feature("template")

	# Add the request to the queue and process the queue
	var request := {
		"url": SERVER_PATH + ADD_EVENT_PATH,
		"headers": ["Authorization: Token " + auth_token],
		"body": {"name": name, "player_id": player_id, "properties": properties, "timestamp": Time.get_unix_time_from_system()},
	}
	request_queue.append(request)
	_process_requests()


## Ideally, this should be called when a user exits the game,
## although it may be difficult on certain plaforms.
## This handles draining the request queue and saving the queue to disk, if necessary.
func handle_exit():
	quit_event_timer.stop()
	should_drain_request_queue = true
	if auto_add_event_on_quit:
		add_event("Quit game")
	else:
		_process_requests()
	return exit_handled


func _save_queue_to_disk() -> void:
	var f = FileAccess.open(QUEUE_FILE_NAME, FileAccess.WRITE)
	if f:
		# If the queue is too big, we trim the queue,
		# favoring more recent events (i.e. the back of the queue).
		if request_queue.size() > MAX_QUEUE_SIZE_TO_SAVE_TO_DISK:
			request_queue = request_queue.slice(request_queue.size() - MAX_QUEUE_SIZE_TO_SAVE_TO_DISK)
			printerr("[Quiver Analytics] Request queue overloaded. Events were dropped.")
		f.store_var(request_queue, false)


func _load_queue_from_disk() -> void:
	var f = FileAccess.open(QUEUE_FILE_NAME, FileAccess.READ)
	if f:
		request_queue.assign(f.get_var())


func _handle_request_failure(response_code: int):
	request_in_flight = false
	# Drop invalid 4xx events
	# 5xx and transient errors will be presumed to be fixed server-side.
	if response_code >= 400 and response_code <= 499:
		request_queue.pop_front()
		printerr("[Quiver Analytics] Event was dropped because it couldn't be processed by the server. Response code %d." % response_code)
	# If we are not in draining mode, we retry with exponential backoff
	if not should_drain_request_queue:
		retry_timer.start(current_retry_time_seconds)
		current_retry_time_seconds += min(current_retry_time_seconds * 2.0, max_retry_time_seconds)
	# If we are in draining mode, we immediately save the existing queue to disk
	# and use _process_requests() to emit the exit_handled signal.
	# We do this because we want to hurry up and let the player quit the game.
	else:
		_save_queue_to_disk()
		request_queue = []
		_process_requests()


func _process_requests() -> void:
	if not request_queue.is_empty() and not request_in_flight:
		var request: Dictionary = request_queue.front()
		request_in_flight = true
		var error = http_request.request(
			request["url"],
			request["headers"],
			HTTPClient.METHOD_POST,
			JSON.stringify(request["body"])
		)
		if error != OK:
			_handle_request_failure(error)
	# If we have successfully drained the queue, emit the exit_handled signal
	if should_drain_request_queue and request_queue.is_empty():
		# We only want to emit the exit_handled signal in the next frame,
		# so that the caller has a chance to receive the signal.
		await get_tree().process_frame
		exit_handled.emit()


func _init_config() -> void:
	# This should give us a nice randomized player ID with low chance of collision
	player_id = abs(randi() << 32 | randi())
	config.set_value("general", "player_id", player_id)
	# We calculate the hash to prevent the player from arbitrarily changing the player ID
	# in the file. This is easy to bypass, and players could always manually send events
	# anyways, but this provides some basic protection.
	var hash = str(player_id).sha256_text()
	config.set_value("general", "hash", hash)
	config.set_value("general", "requested", consent_requested)
	config.set_value("general", "granted", consent_granted)
	config.save(config_file_path)


func _on_http_request_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code >= 200 and response_code <= 299:
	# This line doesn't work, possibly due to a bug in Godot.
	# Even with a non-2xx response code, the result is shown as a success.
	#if result == HTTPRequest.RESULT_SUCCESS:
		request_in_flight = false
		request_queue.pop_front()
		current_retry_time_seconds = min_retry_time_seconds
		# If we are draining the queue, process events as fast as possible
		if should_drain_request_queue:
			_process_requests()
		# Otherwise, take our time so as not to impact the frame rate
		else:
			retry_timer.start(current_retry_time_seconds)
	else:
		_handle_request_failure(response_code)


func _on_retry_timer_timeout() -> void:
	_process_requests()


func _on_quit_event_timer_timeout() -> void:
	add_event("Quit game")
	quit_event_interval_seconds = min(quit_event_interval_seconds + 10, MAX_QUIT_EVENT_INTERVAL_SECONDS)
	quit_event_timer.start(quit_event_interval_seconds)


#func _notification(what):
#	if what == NOTIFICATION_WM_CLOSE_REQUEST:
#		handle_exit()
#		get_tree().quit()
