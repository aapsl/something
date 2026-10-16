extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5


func _physics_process(delta: float) -> void:
	if not can_move:
		return
	
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


@export var mouse_sensivity: float = 0.002
@export var speed: float = 5.0

@onready var head: Node3D = $Head
@onready var ray_cast: RayCast3D = $Head/RayCast3D

var can_move: bool = true

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensivity)
		head.rotate_x(-event.relative.y * mouse_sensivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		
	if event.is_action_pressed("interact"):
		interact_with_object()

func interact_with_object() -> void:
	if ray_cast.is_colliding():
		var target = ray_cast.get_collider()
		if target.has_method("interact"):
			target.interact()


@onready var dialogue_box: Panel = $DialogueLayer/DialogueBox
@onready var dialogue_text: Label = $DialogueLayer/DialogueBox/MarginContainer/DialogueText

func show_dialogue(text: String) -> void:
	dialogue_box.visible = true
	dialogue_text.text = text
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func hide_dialogue() -> void:
	dialogue_box.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
