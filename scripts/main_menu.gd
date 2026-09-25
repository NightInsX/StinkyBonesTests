extends Control


func _ready():
	$Settings/HSlider.value = Global.master_volume
	$Settings/CheckButton.button_pressed = Global.fullscreen

func _on_play_pressed() -> void:
	print("Play")

func _on_settings_pressed() -> void:
	$Animations.play("to_settings")
	$invisible_panel.show()

func _on_exit_pressed() -> void:
	get_tree().exit()


func _toggle_fullscreen() -> void:
	if $Settings/CheckButton.button_pressed:
		print("Activar")
	else:
		print("Desactivar")


func _on_exiting_settings() -> void:
	$Animations.play("to_settings",-1,-1,true)
	$invisible_panel.show()

func _on_animations_animation_finished(_anim_name: StringName) -> void:
	$invisible_panel.hide()

func _input(event):
	if event.is_action_pressed("ui_cancel") and $Settings.position == Vector2.ZERO:
		_on_exiting_settings()
