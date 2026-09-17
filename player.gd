extends CharacterBody2D

# Neste script hai 3 erros. Bastante tochos, ademais. Revisa a lóxica e interiorízaa, seguro que os atopas!

@export var speed: float = 150.0
@export var sprint_multiplier: float = 2.0

var facing_direction: Vector2 = Vector2.DOWN

func _physics_process(_delta: float) -> void:
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	
	if Input.is_action_just_pressed("ui_select"):
		speed *= sprint_multiplier
	
	velocity = input_vector * speed
	
	if input_vector.x != 0:
		facing_direction = Vector2(input_vector.x, 0)
	
	move_and_slide()
