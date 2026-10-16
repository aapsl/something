extends Node3D

@export var next_scene: String = "res://scenes/room.tscn"
var player_inside := false

func _ready() -> void:
	$Area3D.body_entered.connect(_on_enter)
	$Area3D.body_exited.connect(_on_exit)

func _on_enter(body: Node3D) -> void:
	if body.name == "Player":
		player_inside = true

func _on_exit(body: Node3D) -> void:
	if body.name == "Player":
		player_inside = false

func _unhandled_input(event: InputEvent) -> void:
	if player_inside and event.is_action_pressed("interact"):
		get_tree().change_scene_to_file(next_scene)
