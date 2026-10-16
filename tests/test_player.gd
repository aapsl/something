@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

const PLAYER_SCRIPT = preload("res://Player.gd")

func suite_name() -> String:
	return "player"

var player

func setup() -> void:
	player = PLAYER_SCRIPT.new()
	track(player)

	# Setup mock nodes
	var head = Node3D.new()
	head.name = "Head"
	player.add_child(head)
	track(head)

	var raycast = RayCast3D.new()
	raycast.name = "RayCast3D"
	head.add_child(raycast)
	track(raycast)

	var dl = Node.new()
	dl.name = "DialogueLayer"
	player.add_child(dl)
	track(dl)

	var db = Panel.new()
	db.name = "DialogueBox"
	dl.add_child(db)
	track(db)

	var mc = MarginContainer.new()
	mc.name = "MarginContainer"
	db.add_child(mc)
	track(mc)

	var dt = Label.new()
	dt.name = "DialogueText"
	mc.add_child(dt)
	track(dt)

	player.head = head
	player.ray_cast = raycast
	player.dialogue_box = db
	player.dialogue_text = dt

	# Initial setup like ready would do
	player.can_move = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func test_disabled_movement() -> void:
	player.can_move = false
	player.velocity = Vector3(10, 10, 10)
	player._physics_process(0.1)
	assert_eq(player.velocity, Vector3(10, 10, 10), "Velocity should not change if can_move is false")

# Mock Area3D for interactable targets
class MockInteractable extends Area3D:
	var interacted = false
	func interact():
		interacted = true

class MockNonInteractable extends Area3D:
	pass

func test_airborne_gravity() -> void:
	# Note: player is currently out of tree, so is_on_floor() is false
	player.velocity = Vector3.ZERO
	player._physics_process(1.0) # delta 1.0
	assert_eq(player.velocity.x, 0.0)
	assert_eq(player.velocity.z, 0.0)
	# Gravity is negative usually, check that velocity.y decreased
	assert_true(player.velocity.y < 0.0, "Velocity.y should decrease due to gravity")

func test_grounded_jump() -> void:
	# CharacterBody3D is_on_floor() is usually driven by move_and_slide(), which requires a scene tree to work reliably.
	# We'll need to mock the is_on_floor method if possible or skip testing behavior relying on it unless we can put it in tree.
	# For now, we will add the player to the test suite tree or just skip the jump test if it relies heavily on internal physics engine state.
	# Wait, we can mock `is_on_floor` using a script override or just test that if ui_accept is pressed, nothing happens when NOT on floor.

	# Let's verify that if it's NOT on floor, it doesn't jump
	player.velocity.y = 0.0
	var ev = InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

	player._physics_process(0.1)
	assert_true(player.velocity.y <= 0.0, "Should not jump because it's not on floor")

	# Clear input
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

	# Now we dynamically mock `is_on_floor` to test the grounded jump behavior
	var MockPlayerClass = GDScript.new()
	MockPlayerClass.source_code = "extends \"res://Player.gd\"\nfunc is_on_floor(): return true\n"
	MockPlayerClass.reload()
	var mocked_player = MockPlayerClass.new()
	track(mocked_player)
	mocked_player.can_move = true
	mocked_player.velocity = Vector3.ZERO

	var ev2 = InputEventAction.new()
	ev2.action = "ui_accept"
	ev2.pressed = true
	Input.parse_input_event(ev2)
	Input.flush_buffered_events()

	mocked_player._physics_process(0.1)
	assert_eq(mocked_player.velocity.y, 4.5, "Should jump (velocity.y = JUMP_VELOCITY) because it's on floor")

func test_directional_movement_and_stopping() -> void:
	# We simulate input vector
	var ev_forward = InputEventAction.new()
	ev_forward.action = "move_forward"
	ev_forward.pressed = true
	Input.parse_input_event(ev_forward)
	Input.flush_buffered_events()

	player.velocity = Vector3.ZERO
	player._physics_process(0.1)

	# Since basis is identity, move_forward translates to vector (0, -1).
	# Wait, input_dir = (move_left, move_right, move_forward, move_back) -> (0, 0, 1, 0) means y=1. Wait, x=-1 for left, x=1 for right, y=-1 for forward, y=1 for back?
	# We just assert x and z are updated
	assert_true(player.velocity.x != 0.0 or player.velocity.z != 0.0, "Player should move when directional input is provided")

	# Clear input
	ev_forward.pressed = false
	Input.parse_input_event(ev_forward)
	Input.flush_buffered_events()

	player._physics_process(0.1)
	# move_toward 0
	# SPEED is 5.0, move_toward(..., 0, 5.0) should bring it back to 0
	assert_eq(player.velocity.x, 0.0)
	assert_eq(player.velocity.z, 0.0)

func test_mouse_look_with_pitch_clamping() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ev = InputEventMouseMotion.new()
	ev.relative = Vector2(100, 200000) # Large Y to test clamping

	player._unhandled_input(ev)

	assert_true(player.rotation.y < 0.0, "Player should rotate around Y axis negatively")
	assert_true(player.head.rotation.x < 0.0, "Head should pitch up negatively")
	assert_eq(player.head.rotation.x, deg_to_rad(-89), "Head pitch should be clamped to -89 degrees")

	var ev2 = InputEventMouseMotion.new()
	ev2.relative = Vector2(0, -400000)
	player._unhandled_input(ev2)
	assert_eq(player.head.rotation.x, deg_to_rad(89), "Head pitch should be clamped to 89 degrees")

func test_interact_with_collider() -> void:
	var interactable = MockInteractable.new()
	# The mock raycast doesn't have physics, we need to mock it
	# So we inject a mock RayCast3D with is_colliding and get_collider mocked
	var MockRayClass = GDScript.new()
	MockRayClass.source_code = """
extends RayCast3D
var mock_collider
func is_colliding(): return mock_collider != null
func get_collider(): return mock_collider
"""
	MockRayClass.reload()
	var mock_ray = MockRayClass.new()
	track(mock_ray)
	mock_ray.mock_collider = interactable
	player.ray_cast = mock_ray

	var ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	player._unhandled_input(ev)

	assert_true(interactable.interacted, "Interact method should be called on target")

func test_interact_without_collider() -> void:
	var non_interactable = MockNonInteractable.new()
	var MockRayClass = GDScript.new()
	MockRayClass.source_code = """
extends RayCast3D
var mock_collider
func is_colliding(): return mock_collider != null
func get_collider(): return mock_collider
"""
	MockRayClass.reload()
	var mock_ray = MockRayClass.new()
	track(mock_ray)
	mock_ray.mock_collider = non_interactable
	player.ray_cast = mock_ray

	var ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	# Should not crash
	player._unhandled_input(ev)
	assert_true(true, "Did not crash when interacting with non-interactable object")

func test_show_dialogue() -> void:
	player.dialogue_box.visible = false
	player.show_dialogue("Hello world")
	assert_true(player.dialogue_box.visible, "Dialogue box should be visible")
	assert_eq(player.dialogue_text.text, "Hello world", "Dialogue text should be updated")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)

func test_hide_dialogue() -> void:
	player.dialogue_box.visible = true
	player.hide_dialogue()
	assert_false(player.dialogue_box.visible, "Dialogue box should be hidden")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)
