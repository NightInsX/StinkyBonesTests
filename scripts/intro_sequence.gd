extends Control

var current_text := ""
var character_index := 0
var is_typing := false
var character_voice : AudioStreamPlayer

func show_line(line: String) -> void:
	current_text = line
	character_index = 0
	is_typing = true
	$dialogue.text = current_text
	$dialogue.visible_characters = 0
	$DialogueTimer.start()
	$DialogueTimer.timeout.connect(func():
		if character_index >= current_text.length():
			finish_line()
			return
		var character := current_text[character_index]
		character_index += 1
		$dialogue.visible_characters = character_index
		if character != " ":
			character_voice.play()
		)

func finish_line() -> void:
	is_typing = false
	$DialogueTimer.stop()
	$dialogue.visible_characters = -1

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Accion"):
		$AnimationPlayer.play("to_game")
	if event.is_action_pressed("ui_accept"):
		if is_typing:
			finish_line()
		else:
			hide()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "to_game":
		get_tree().change_scene_to_file("res://scenes/main.tscn")
