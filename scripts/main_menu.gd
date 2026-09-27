extends Control


func _ready():
	$Settings/HSlider.value = Global.master_volume
	$Settings/CheckButton.button_pressed = Global.fullscreen
	$Settings/volume.text = "Currently: " + str(Global.master_volume)
	for button in get_tree().get_nodes_in_group("Buttons"):
		button.pressed.connect(_on_button_pressed)

func _on_play_pressed() -> void:
	$Animations.play("outro")

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

func _on_exiting_credits() -> void:
	$Animations.play("to_credits",-1,-1,true)
	$invisible_panel.show()

func _on_animations_animation_finished(anim_name: StringName) -> void:
	if anim_name == "outro":
		get_tree().change_scene_to_file("res://scenes/intro_sequence.tscn")
	$invisible_panel.hide()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if $Settings.position == Vector2.ZERO:
			_on_exiting_settings()
		if $Credits.position == Vector2.ZERO:
			_on_exiting_credits()

func _on_h_slider_value_changed(value: float) -> void:
	Global.master_volume = value
	$AudioStreamPlayer.volume_db = (-value+100)/2
	if value == 0: $AudioStreamPlayer.volume_db = -1000
	$Settings/volume.text = "Currently: " + str(int(value))


func _on_credits_pressed() -> void:
	$Animations.play("to_credits")
	$invisible_panel.show()

func _on_button_2_pressed() -> void:
	_on_exiting_credits()

func _on_button_pressed() -> void:
	$AudioStreamPlayer2.play()
