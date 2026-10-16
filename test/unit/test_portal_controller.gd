extends GutTest

const PortalControllerScript = preload("res://scripts/portal_controller.gd")

func _create_portal_fixture() -> Dictionary:
	# Создаём иерархию, нужную PortalController для разрешения стандартных NodePath.
	var root := Node3D.new()
	root.name = "TestMain"
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group("player")
	player.position = Vector3(0.0, 0.0, 5.0)
	root.add_child(player)

	var door_trigger := Area3D.new()
	door_trigger.name = "DoorTrigger"
	root.add_child(door_trigger)
	var frame := Node3D.new()
	frame.name = "DoorFrame"
	root.add_child(frame)
	var surface := MeshInstance3D.new()
	surface.name = "PortalSurface"
	frame.add_child(surface)
	var system := Node.new()
	system.name = "PortalSystem"
	frame.add_child(system)
	var viewport := SubViewport.new()
	viewport.name = "PortalViewport"
	system.add_child(viewport)
	var room_container := Node3D.new()
	room_container.name = "RoomScene"
	viewport.add_child(room_container)
	var entry := Marker3D.new()
	entry.name = "RoomEntry"
	entry.position = Vector3(0.0, 0.0, 3.0)
	viewport.add_child(entry)
	var camera := Camera3D.new()
	camera.name = "PortalCamera"
	viewport.add_child(camera)
	var controller := Node.new()
	controller.name = "PortalController"
	controller.set_script(PortalControllerScript)
	system.add_child(controller)

	# GUT очистит временную сцену после завершения теста.
	add_child_autofree(root)
	return {
		"root": root,
		"player": player,
		"frame": frame,
		"viewport": viewport,
		"room_container": room_container,
		"camera": camera,
		"controller": controller,
	}

func test_viewport_is_disabled_while_door_is_closed() -> void:
	var fixture := _create_portal_fixture()
	assert_eq(
		fixture.viewport.render_target_update_mode,
		SubViewport.UPDATE_DISABLED,
		"Закрытая дверь не должна запускать обновление SubViewport."
	)

func test_portal_camera_direction_changes_after_crossing_door_plane() -> void:
	var fixture := _create_portal_fixture()
	var controller: Node = fixture.controller
	# Заглушка загруженной комнаты делает портал активным без фоновой загрузки ресурсов.
	var room_instance := Node3D.new()
	fixture.room_container.add_child(room_instance)
	controller._room_instance = room_instance
	controller.set_door_open(true)

	fixture.player.global_position = Vector3(0.0, 0.0, 5.0)
	controller._update_portal_camera()
	var direction_before: Vector3 = fixture.camera.global_basis.z.normalized()

	fixture.player.global_position = Vector3(0.0, 0.0, -5.0)
	controller._update_portal_camera()
	var direction_after: Vector3 = fixture.camera.global_basis.z.normalized()

	assert_false(
		direction_before.is_equal_approx(direction_after),
		"После перехода на другую сторону двери камера портала должна развернуться."
	)

func test_portal_config_has_expected_defaults() -> void:
	# Этот тест покрывает дефолтные значения третьего целевого скрипта — PortalConfig.
	var config := PortalConfig.new()
	assert_eq(config.room_scene_path, "res://scenes/room.tscn")
	assert_eq(config.load_distance, 20.0)
	assert_eq(config.unload_distance, 30.0)
	assert_eq(config.unload_delay, 5.0)
	assert_eq(config.portal_camera_fov, 75.0)
	assert_eq(config.viewport_size, Vector2i(540, 990))
	assert_eq(config.flip_hysteresis, 0.15)
	assert_eq(config.door_open_radius, 3.0)
	assert_eq(config.auto_close_delay, 2.0)
	assert_eq(config.door_animation_time, 0.45)
	assert_eq(config.door_open_angle_deg, 100.0)
	assert_eq(config.door_open_direction, 1)
