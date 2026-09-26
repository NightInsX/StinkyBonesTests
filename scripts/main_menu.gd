extends Control


func _ready():
	$Settings/HSlider.value = Global.master_volume
	$Settings/CheckButton.button_pressed = Global.fullscreen
	$Settings/volume.text = "Currently: " + str(Global.master_volume)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld_testing_room.tscn")

func _on_settings_pressed() -> void:
	$Animations.play("to_settings")
	$invisible_panel.show()

func _on_exit_pressed() -> void:
	get_tree().quit()


func _toggle_fullscreen() -> void:
	Global.swap_screen_resolution($Settings/CheckButton.button_pressed)


func _on_exiting_settings() -> void:
	$Animations.play("to_settings",-1,-1,true)
	$invisible_panel.show()

func _on_animations_animation_finished(_anim_name: StringName) -> void:
	$invisible_panel.hide()

func _input(event):
	if event.is_action_pressed("ui_cancel") and $Settings.position == Vector2.ZERO:
		_on_exiting_settings()

func _on_h_slider_value_changed(value: float) -> void:
	Global.master_volume = value
	$AudioStreamPlayer.volume_db = (-value+100)/2
	if value == 0: $AudioStreamPlayer.volume_db = -1000
	$Settings/volume.text = "Currently: " + str(int(value))
