extends Node

func _ready() -> void:
	if Analytics.should_show_consent_dialog():
		Analytics.show_consent_dialog(self)


func _on_button_pressed() -> void:
	await Analytics.handle_exit()
	get_tree().quit()


func _on_test_event_button_pressed() -> void:
	Analytics.add_event("Test event")
