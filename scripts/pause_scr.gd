extends CanvasLayer

var sure_to_exit := 0 # Takes negative value if to menu, takes positive if to exit, takes 0 if to neither.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide()
	
	
func pause_game():
	MusicCtrl.pause()
	sure_to_exit = 0
	$ColorRect/Label2.hide()
	show()
	$ColorRect/HSlider.value = Global.master_volume
	$ColorRect/CheckButton.button_pressed = Global.fullscreen
	$ColorRect/volume.text = "Currently: " + str(Global.master_volume)


func _on_resume_pressed() -> void:
	MusicCtrl.restart()
	sure_to_exit = 0
	hide()

func _on_menu_pressed() -> void:
	if sure_to_exit == -1:
		MusicCtrl.restart()
		Global.overworld = false
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		hide()
	else:
		sure_to_exit = -1
		$ColorRect/Label2.show()

func _on_exit_pressed() -> void:
	if sure_to_exit == 1:
		get_tree().quit()
	else:
		sure_to_exit = 1
		$ColorRect/Label2.show()

func _on_h_slider_value_changed(value: float) -> void:
	Global.master_volume = value # Estoupa co 0 por algun motivo
	MusicCtrl.set_music_volume(value)
	if value == 0: MusicCtrl.set_music_volume(-1000)
	$ColorRect/volume.text = "Currently: " + str(int(value))


func _on_button_pressed() -> void:
	Global.swap_screen_resolution($ColorRect/CheckButton.button_pressed)
