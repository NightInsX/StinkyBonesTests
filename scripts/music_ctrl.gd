extends CanvasLayer

var current_node : AudioStreamPlayer

func _ready():
	current_node = $AudioStreamPlayer
	print("Music node has been initialised")

func set_music_volume(value:int):
	Global.master_volume = value
	current_node.volume_db = (-value+100)/2
	if value == 0: current_node.volume_db = -1000

func pause():
	current_node.stream_paused = true

func restart():
	current_node.stream_paused = true
