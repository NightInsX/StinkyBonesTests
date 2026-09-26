extends Node

var master_volume := 100
var fullscreen := false

var overworld := false

func _ready():
	print("Game started")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and overworld: # Debería ser Escape
		PauseScr.pause_game()

func swap_screen_resolution(resolution):
	if resolution: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else: 
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(640,360))
