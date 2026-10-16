extends Area3D

@export var dialogue_resourse: DialogueResource
@export var dialogue_title: String = "start"

const MY_BALLOON = preload("res://dialogue balloon/balloon.tscn")

func interact() -> void:
	if dialogue_resourse:
		var balloon = MY_BALLOON.instantiate()
		get_tree().current_scene.add_child(balloon)
		balloon.start(dialogue_resourse, dialogue_title)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.can_move = false
		await balloon.tree_exited
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if player:
			player.can_move = true
