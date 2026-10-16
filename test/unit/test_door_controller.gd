extends GutTest

const DoorControllerScript = preload("res://scripts/door_controller.gd")

# Подменяет контроллер портала, чтобы проверять смену его состояния.
class PortalControllerSpy extends Node:
	var call_count: int = 0
	var last_door_state: bool = false

	func set_door_open(is_open: bool) -> void:
		call_count += 1
		last_door_state = is_open

# Подменяет Autoload и отложенную смену сцены в тесте перехода.
class TransitionSpy extends Node:
	var saved_player: CharacterBody3D
	var scheduled_paths: Array[String] = []

	func save(player: CharacterBody3D) -> void:
		saved_player = player

	func record_scene_change(scene_path: String) -> void:
		scheduled_paths.append(scene_path)

func _create_door_fixture() -> Dictionary:
	# Собираем минимальную сцену с узлами, которые ищет DoorController.
	var root := Node3D.new()
	root.name = "TestMain"

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group("player")
	root.add_child(player)

	var open_trigger := Area3D.new()
	open_trigger.name = "DoorOpenTrigger"
	root.add_child(open_trigger)

	var transition_trigger := Area3D.new()
	transition_trigger.name = "DoorTransitionTrigger"
	root.add_child(transition_trigger)

	var frame := Node3D.new()
	frame.name = "DoorFrame"
	frame.set_script(DoorControllerScript)
	root.add_child(frame)

	var door_model := Node3D.new()
	door_model.name = "DoorModel"
	frame.add_child(door_model)

	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	frame.add_child(pivot)

	var leaf := MeshInstance3D.new()
	leaf.name = "DoorLeaf"
	pivot.add_child(leaf)

	var surface := MeshInstance3D.new()
	surface.name = "PortalSurface"
	frame.add_child(surface)

	var system := Node.new()
	system.name = "PortalSystem"
	frame.add_child(system)
	var portal_controller := PortalControllerSpy.new()
	portal_controller.name = "PortalController"
	system.add_child(portal_controller)

	# add_child_autofree удалит временную сцену и все её дочерние узлы после теста.
	add_child_autofree(root)
	return {
		"root": root,
		"player": player,
		"door": frame,
		"open_trigger": open_trigger,
		"transition_trigger": transition_trigger,
		"pivot": pivot,
		"surface": surface,
		"portal_controller": portal_controller,
	}

func _interact(door: Node) -> void:
	# Для ручного открытия двери передаём событие проекта interact.
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	door._unhandled_input(event)

func test_door_collision_is_enabled_when_closed_and_disabled_when_open() -> void:
	var fixture := _create_door_fixture()
	var door: Node = fixture.door
	var collision: CollisionShape3D = fixture.pivot.get_node("LeafCollision/CollisionShape3D")

	assert_false(door.is_door_open)
	assert_false(collision.disabled, "У закрытого полотна коллизия включена.")

	door.is_player_near = true
	_interact(door)
	assert_true(door.is_door_open)
	assert_true(collision.disabled, "При открытии полотно перестаёт блокировать проход.")

	_interact(door)
	assert_false(door.is_door_open)
	assert_false(collision.disabled, "При закрытии коллизия полотна снова включается.")

func test_transition_trigger_connects_and_tracks_player() -> void:
	var fixture := _create_door_fixture()
	var trigger: Area3D = fixture.transition_trigger
	var door: Node = fixture.door
	var shape := (trigger.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var callback := Callable(door, "_on_passage_entered")

	assert_true(fixture.player.is_in_group("player"), "Игрок должен быть в группе player.")
	assert_eq(trigger.collision_mask, 1, "Триггер должен проверять слой игрока.")
	assert_true(trigger.body_entered.is_connected(callback), "body_entered должен быть подключён к обработчику.")
	assert_eq(shape.size, Vector3(door.door_width, door.door_height, door.passage_depth))

	# Вызываем обработчики напрямую, чтобы тест не зависел от физического кадра.
	door._on_passage_entered(fixture.player)
	assert_false(door._players_in_passage.is_empty(), "После входа игрок должен отслеживаться.")
	door._on_passage_exited(fixture.player)
	assert_true(door._players_in_passage.is_empty(), "После выхода игрок удаляется из отслеживания.")

func test_crossing_saves_player_and_schedules_scene_change() -> void:
	var fixture := _create_door_fixture()
	var door: Node = fixture.door
	var player: CharacterBody3D = fixture.player
	var transition_spy := TransitionSpy.new()
	fixture.root.add_child(transition_spy)

	# Для направления -1 игрок пересекает дверь с положительной стороны на отрицательную.
	door.crossing_direction = -1
	door.is_door_open = true
	player.global_position = Vector3(0.0, 0.0, 1.0)
	door._on_passage_entered(player)
	var crossing: Dictionary = door._players_in_passage[player.get_instance_id()]
	crossing["previous_side"] = 1.0
	door._players_in_passage[player.get_instance_id()] = crossing

	# Подмены подтверждают сохранение состояния и запрос смены, не меняя сцену GUT.
	door._transition_data_override = transition_spy
	door._scene_change_scheduler = Callable(transition_spy, "record_scene_change")
	door._check_for_completed_crossing()

	assert_eq(transition_spy.saved_player, player, "SceneTransitionData.save должен получить игрока.")
	assert_eq(transition_spy.scheduled_paths, [door.room_scene_path], "Путь комнаты должен быть передан планировщику.")

func test_exit_starts_auto_close_and_return_stops_timer() -> void:
	var fixture := _create_door_fixture()
	var door: Node = fixture.door
	door.is_player_near = true
	_interact(door)
	assert_true(door.is_door_open)

	door._on_player_exited(fixture.player)
	assert_false(door._auto_close_timer.is_stopped(), "После выхода должен запуститься таймер.")

	door._on_player_entered(fixture.player)
	assert_true(door._auto_close_timer.is_stopped(), "Повторный вход должен отменить автозакрытие.")

func test_portal_surface_is_visible_only_when_door_is_open() -> void:
	var fixture := _create_door_fixture()
	var door: Node = fixture.door

	fixture.pivot.rotation.y = 0.0
	door._refresh_portal_state()
	assert_false(fixture.surface.visible, "При закрытом полотне поверхность портала скрыта.")

	fixture.pivot.rotation.y = deg_to_rad(90.0)
	door._refresh_portal_state()
	assert_true(fixture.surface.visible, "При открытом полотне поверхность портала видна.")

func test_player_scene_belongs_to_player_group() -> void:
	# Проверяем группу на ресурсной сцене игрока, а не только на тестовой заглушке.
	var packed_player := load("res://player.tscn") as PackedScene
	var player := packed_player.instantiate() as CharacterBody3D
	assert_true(player.is_in_group("player"))
	player.free()

func test_crossing_direction_can_be_configured() -> void:
	var fixture := _create_door_fixture()
	var door: Node = fixture.door

	assert_eq(door.crossing_direction, 1)
	assert_true(door._has_crossed_in_configured_direction(-0.1, 0.1))
	assert_false(door._has_crossed_in_configured_direction(0.1, -0.1))

	door.crossing_direction = -1
	assert_true(door._has_crossed_in_configured_direction(0.1, -0.1))
	assert_false(door._has_crossed_in_configured_direction(-0.1, 0.1))

func test_door_side_uses_global_normal_after_rotation() -> void:
	var fixture := _create_door_fixture()
	var door: Node3D = fixture.door
	var player: CharacterBody3D = fixture.player
	door.rotation.y = PI / 2.0

	var frame_front := door.global_transform.basis.z
	player.global_position = door.global_position + frame_front * 2.0
	assert_true(door._get_door_side(player) < 0.0, "Со стороны фасада знак должен быть отрицательным.")

	player.global_position = door.global_position - frame_front * 2.0
	assert_true(door._get_door_side(player) > 0.0, "С обратной стороны знак должен быть положительным.")

func test_portal_controller_is_not_notified_when_state_does_not_change() -> void:
	var fixture := _create_door_fixture()
	var spy: PortalControllerSpy = fixture.portal_controller
	assert_eq(spy.call_count, 1, "Начальное состояние задаётся один раз.")

	fixture.door._refresh_portal_state()
	assert_eq(spy.call_count, 1, "Без изменения угла повторного вызова нет.")

	fixture.pivot.rotation.y = deg_to_rad(20.0)
	fixture.door._refresh_portal_state()
	assert_eq(spy.call_count, 2, "При изменении состояния отправляется один вызов.")
	assert_true(spy.last_door_state)

	fixture.door._refresh_portal_state()
	assert_eq(spy.call_count, 2, "При неизменном открытом состоянии вызов не повторяется.")
