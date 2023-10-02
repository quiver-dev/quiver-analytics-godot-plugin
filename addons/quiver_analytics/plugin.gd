@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Analytics"
const CUSTOM_PROPERTIES := [
	{"name": "quiver/analytics/auth_token", "default": "", "basic": true},
	{"name": "quiver/analytics/player_consent_required", "default": false, "basic": true},
	{"name": "quiver/analytics/config_file_path", "default": "user://analytics.cfg", "basic": false},
	{"name": "quiver/analytics/auto_add_event_on_launch", "default": true, "basic": false},
	{"name": "quiver/analytics/auto_add_event_on_quit", "default": true, "basic": false},
]

func _enter_tree() -> void:
	for property in CUSTOM_PROPERTIES:
		var name = property["name"]
		var default = property["default"]
		var basic = property["basic"]
		if not ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, default)
			ProjectSettings.set_initial_value(name, default)
			if basic:
				ProjectSettings.set_as_basic(name, true)
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/quiver_analytics/analytics.tscn")
	if not ProjectSettings.get_setting("quiver/analytics/auth_token"):
		printerr("Quiver Analytics auth key hasn't been set.")


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	for property in CUSTOM_PROPERTIES:
		var name = property["name"]
		ProjectSettings.set_setting(name, null)
