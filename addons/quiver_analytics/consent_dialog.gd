@tool
class_name ConsentDialog
extends CanvasLayer

@onready var anim_player = $AnimationPlayer


func show_with_animation(anim_name: String = "pop_up") -> void:
	anim_player.play(anim_name)


func hide_with_animation(anim_name: String = "pop_up") -> void:
	anim_player.play_backwards(anim_name)


func _on_approve_button_pressed() -> void:
	Analytics.approve_data_collection()
	hide()


func _on_deny_button_pressed() -> void:
	Analytics.deny_data_collection()
	hide()
