extends CanvasLayer

var sure_to_exit := 0 # Takes negative value if to menu, takes positive if to exit, takes 0 if to neither.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide()
	
func pause_game():
	# Stop music
	$ColorRect/Label2.hide()
	show()
	$ColorRect/HSlider.value = Global.master_volume
	$ColorRect/CheckButton.button_pressed = Global.fullscreen


func _on_resume_pressed() -> void:
	sure_to_exit = 0
	hide()

func _on_menu_pressed() -> void:
	if sure_to_exit == -1:
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

#func _input(event):
#	if event is InputEventMouseButton and sure_to_exit != 0:
#		sure_to_exit = 0
#		$ColorRect/Label2.hide()


func _on_h_slider_value_changed(value: float) -> void:
	Global.master_volume = value # Estoupa co 0 por algun motivo
	#$AudioStreamPlayer.volume_db = (-value+100)/2 ###### Awaiting music controller
	if value == 0: $AudioStreamPlayer.volume_db = -1000
	$ColorRect/volume.text = "Currently: " + str(int(value))
	print("Inserir cambio de volume: pendente da música")


func _on_button_pressed() -> void:
	Global.swap_screen_resolution($ColorRect/CheckButton.button_pressed)
