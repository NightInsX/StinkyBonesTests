extends Control

signal line_started(speaker: String, text: String)

var current_text := ""
var character_index := 0
var is_typing := false
var awaiting_advance := false
var dialogue_over := false

var current_speaker := "narrator"
var voice_players := {}

var dialogue_sequence : Array = []
var line_index := 0

var current_round := -1
var piled_text := ""

var first_text_round := "\"I didn't realize... was the climb... always this tiring?\"\nWhatever. I need to do one of these excursions alone. Even if it's not much, I want to grow... I don't want to be treated like a baby for my whole life!\n I got into the cave with determination and a bit of excess confidence. Enough to forget how bad I was at climbing... and I lost my grip."
var second_text_round := "\"eh? where... am I?\"\nI didn't know how much time had passed, but the cold and humid rock I was lying on made it clear to me that I was still in the cave.\nSomehow, my three lanterns were gone. And gone too, were the rest of my belongings. I felt especially bad not having my coat on me. The cold was making me tremble non-stop."
var third_text_round := "When I finally got off the ground, I saw something in front of me. Maybe another caver? But who would be so deep inside of a cave without a light on, really...\nMust be my mind playing tricks on me, I thought. But right after that, something started to echo in my mind.\n\"You'd do us all a favor if you stopped breathing around here, you know?\"\n\"It's much more sensitive than it may appear, this cave\""
var fourth_text_round := "\"Tough luck. I'm not planning to stop breathing just for the sake of this cave.\"\n\"But you can help me get outta here if you're so worried about me staying...\"\n\"I'd rather not. There are other, more efficient ways to get this over with\"."

var speakers_first := ["protagonist", "narrator", "narrator"]
var speakers_second := ["protagonist", "narrator", "narrator"]
var speakers_third := ["narrator", "narrator", "misterious", "misterious"]
var speakers_fourth := ["protagonist", "misterious"]


func _ready() -> void:
	voice_players = {
		"narrator": $narrator,
		"protagonist": $girl,
		"misterious": $misterious
	}
	$DialogueTimer.timeout.connect(_on_dialogue_timer_timeout)
	_build_dialogue_sequence()

func _build_dialogue_sequence() -> void:
	_append_round(first_text_round, speakers_first, 0)
	_append_round(second_text_round, speakers_second, 1)
	_append_round(third_text_round, speakers_third, 2)
	_append_round(fourth_text_round, speakers_fourth, 3)


func _append_round(round_text: String, speakers: Array, round_id: int) -> void:
	var lines := round_text.split("\n")
	for i in lines.size():
		var speaker := "narrator"
		if i < speakers.size():
			speaker = speakers[i]
		dialogue_sequence.append({"speaker": speaker, "text": lines[i], "round": round_id})


func _show_current_line() -> void:
	if line_index >= dialogue_sequence.size():
		_end_dialogue()
		return
	var entry = dialogue_sequence[line_index]
	show_line(entry.text, entry.speaker, entry.round)


func show_line(line: String, speaker: String = "narrator", round_id: int = 0) -> void:
	if round_id != current_round:
		piled_text = ""
		current_round = round_id
	current_text = line
	current_speaker = speaker
	is_typing = true
	awaiting_advance = false
	line_started.emit(speaker, line)
	var separator := "\n" if piled_text != "" else ""
	$dialogue.text = piled_text + separator + current_text
	character_index = (piled_text + separator).length()
	$dialogue.visible_characters = character_index
	$DialogueTimer.start()


func _on_dialogue_timer_timeout() -> void:
	var target_length := len($dialogue.text)
	if character_index >= target_length:
		finish_line()
		return
	var character = $dialogue.text[character_index]
	character_index += 1
	$dialogue.visible_characters = character_index
	if character != " " and character != "\n":
		var voice : AudioStreamPlayer = voice_players.get(current_speaker)
		if voice:
			voice.play()


func finish_line() -> void:
	is_typing = false
	awaiting_advance = true
	$DialogueTimer.stop()
	$dialogue.visible_characters = -1
	piled_text = $dialogue.text


func _advance_dialogue() -> void:
	line_index += 1
	if line_index >= dialogue_sequence.size():
		_end_dialogue()
	else:
		_show_current_line()


func _end_dialogue() -> void:
	dialogue_over = true
	awaiting_advance = false
	_go_to_game()

func _go_to_game() -> void:
	$AnimationPlayer.play("to_game")

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("Accion"):
		_go_to_game()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept"):
		if is_typing:
			finish_line()
		elif awaiting_advance:
			_advance_dialogue()
		get_viewport().set_input_as_handled()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "to_game":
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	elif anim_name == "ready":
		_show_current_line()
