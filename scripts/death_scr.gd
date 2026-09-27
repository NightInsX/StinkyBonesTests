extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.overworld = false

func _on_retry_pressed() -> void:
	print("Código para regresar ao xogo")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
