extends Node3D

## Строит простую дверь из примитивов, принимает interact и управляет переходом.
## Скрипт можно повесить на узел DoorFrame.

## Общие настройки двери и комнаты.
@export var config: PortalConfig
## Резервная сцена перехода, если общий ресурс настроек не назначен.
@export_group("Настройки комнаты")
@export_file("*.tscn") var room_scene_path: String = "res://scenes/room_a.tscn"
@export_group("")
## Узлы двери и областей, находящиеся в демонстрационной сцене.
@export var door_model_path: NodePath = NodePath("DoorModel")
@export var door_pivot_path: NodePath = NodePath("DoorPivot")
@export var door_leaf_path: NodePath = NodePath("DoorPivot/DoorLeaf")
@export var portal_surface_path: NodePath = NodePath("PortalSurface")
@export var portal_controller_path: NodePath = NodePath("PortalSystem/PortalController")
@export var open_trigger_path: NodePath = NodePath("DoorOpenTrigger")
@export var passage_trigger_path: NodePath = NodePath("DoorTransitionTrigger")

## Размеры проёма и полотна. Единицы — метры.
@export_range(0.5, 5.0, 0.05, "suffix:m") var door_width: float = 1.2
@export_range(1.0, 5.0, 0.05, "suffix:m") var door_height: float = 2.2
@export_range(0.03, 0.5, 0.01, "suffix:m") var leaf_thickness: float = 0.08
@export_range(0.05, 0.5, 0.01, "suffix:m") var frame_thickness: float = 0.15
@export_range(0.05, 1.0, 0.01, "suffix:m") var passage_depth: float = 0.1

## Дверная механика. Поля доступны в Inspector и берутся из PortalConfig, если он назначен.
@export_range(0.0, 60.0, 0.1, "suffix:s") var auto_close_delay: float = 2.0
@export_range(0.05, 10.0, 0.05, "suffix:s") var door_animation_time: float = 0.45
@export_range(10.0, 180.0, 1.0, "suffix:°") var door_open_angle_deg: float = 100.0
@export_range(-1, 1, 2) var door_open_direction: int = 1
@export_range(0.5, 20.0, 0.1, "suffix:m") var door_open_radius: float = 3.0
## Направление для одностороннего режима: 1 — из отрицательной стороны в положительную, -1 — обратно.
@export_range(-1, 1, 2) var crossing_direction: int = 1
## Разрешает переход через дверь с обеих сторон.
@export var bidirectional_transition: bool = true

var is_player_near: bool = false
var is_door_open: bool = false
## Игрок, который сейчас находится в зоне взаимодействия с дверью.
var _current_player: CharacterBody3D = null
var _door_model: Node3D
var _door_pivot: Node3D
var _door_leaf: MeshInstance3D
var _leaf_collision: CollisionShape3D
var _portal_surface: MeshInstance3D
var _portal_controller: Node
var _portal_state_initialized: bool = false
var _last_portal_is_open: bool = false
var _open_trigger: Area3D
var _passage_trigger: Area3D
var _auto_close_timer: Timer
var _door_tween: Tween
var _players_in_passage: Dictionary = {}
## Внутренние точки подмены для изолированных GUT-тестов.
var _transition_data_override: Node
var _scene_change_scheduler: Callable

func _ready() -> void:
	_apply_config()
	_cache_nodes()
	_sync_portal_room_scene_path()
	_build_procedural_door()
	_configure_triggers()
	_create_auto_close_timer()
	_connect_signals()
	_refresh_portal_state()

func _process(_delta: float) -> void:
	# PortalSurface включается только после того, как полотно открылось больше чем на 10°.
	_refresh_portal_state()

func _physics_process(_delta: float) -> void:
	_check_for_completed_crossing()

func _unhandled_input(event: InputEvent) -> void:
	# Игрок открывает и закрывает дверь только вручную, пока находится рядом.
	if not is_player_near or not event.is_action_pressed("interact"):
		return

	if is_door_open:
		is_door_open = false
		_animate_door(false)
	else:
		# Выбираем сторону открывания по положению игрока относительно плоскости двери.
		# Если игрок стоит почти точно в плоскости, сохраняем направление по умолчанию.
		if _current_player != null and is_instance_valid(_current_player):
			var side := _get_door_side(_current_player)
			if not is_zero_approx(side):
				door_open_direction = 1 if side > 0.0 else -1
		is_door_open = true
		_auto_close_timer.stop()
		_animate_door(true)
	get_viewport().set_input_as_handled()

func _apply_config() -> void:
	if config == null:
		return
	room_scene_path = config.room_scene_path
	auto_close_delay = config.auto_close_delay
	door_animation_time = config.door_animation_time
	door_open_angle_deg = config.door_open_angle_deg
	door_open_direction = -1 if config.door_open_direction < 0 else 1
	door_open_radius = config.door_open_radius

func _sync_portal_room_scene_path() -> void:
	# Дверная сцена задаёт комнату; синхронизируем её с превью-порталом,
	# чтобы картинка и итоговый переход всегда вели в одну сцену.
	if _portal_controller != null and _portal_controller.has_method("set_room_scene_path"):
		_portal_controller.call("set_room_scene_path", room_scene_path)

func _cache_nodes() -> void:
	_door_model = get_node_or_null(door_model_path) as Node3D
	_door_pivot = get_node_or_null(door_pivot_path) as Node3D
	_door_leaf = get_node_or_null(door_leaf_path) as MeshInstance3D
	_portal_surface = get_node_or_null(portal_surface_path) as MeshInstance3D
	_portal_controller = get_node_or_null(portal_controller_path)
	_open_trigger = get_node_or_null(open_trigger_path) as Area3D
	_passage_trigger = get_node_or_null(passage_trigger_path) as Area3D

func _build_procedural_door() -> void:
	if _door_model == null or _door_pivot == null or _door_leaf == null:
		push_error("DoorController: создайте DoorModel, DoorPivot и DoorLeaf в сцене.")
		return

	# Рама и порог — четыре прямоугольных бруска из BoxMesh.
	var frame_material := _make_material(Color(0.22, 0.15, 0.09))
	var post_size := Vector3(frame_thickness, door_height + frame_thickness, frame_thickness)
	_add_box(_door_model, "LeftPost", post_size,
		Vector3(-door_width * 0.5 - frame_thickness * 0.5, 0.0, 0.0), frame_material)
	_add_box(_door_model, "RightPost", post_size,
		Vector3(door_width * 0.5 + frame_thickness * 0.5, 0.0, 0.0), frame_material)
	_add_box(_door_model, "TopBeam", Vector3(door_width + frame_thickness * 2.0, frame_thickness, frame_thickness),
		Vector3(0.0, door_height * 0.5 + frame_thickness * 0.5, 0.0), frame_material)
	_add_box(_door_model, "Threshold", Vector3(door_width + frame_thickness * 2.0, 0.08, frame_thickness),
		Vector3(0.0, -door_height * 0.5, 0.0), frame_material)

	# Ось закреплена у левой стойки, поэтому полотно открывается наружу как обычная дверь.
	_door_pivot.position = Vector3(-door_width * 0.5, 0.0, 0.0)
	_door_pivot.rotation = Vector3.ZERO
	_door_leaf.position = Vector3(door_width * 0.5, 0.0, -leaf_thickness * 0.5)
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(door_width, door_height, leaf_thickness)
	_door_leaf.mesh = leaf_mesh
	_door_leaf.material_override = _make_material(Color(0.35, 0.20, 0.11))

	# Движущееся тело следует за DoorPivot и не даёт игроку пройти сквозь закрытое полотно.
	var leaf_body := AnimatableBody3D.new()
	leaf_body.name = "LeafCollision"
	leaf_body.position = _door_leaf.position
	leaf_body.collision_layer = 1
	leaf_body.sync_to_physics = true
	_door_pivot.add_child(leaf_body)
	_leaf_collision = CollisionShape3D.new()
	_leaf_collision.name = "CollisionShape3D"
	var leaf_box := BoxShape3D.new()
	leaf_box.size = leaf_mesh.size
	_leaf_collision.shape = leaf_box
	leaf_body.add_child(_leaf_collision)

	# Ручки устанавливаются с обеих сторон полотна в симметричных точках.
	_create_handle(1.0)
	_create_handle(-1.0)

func _create_handle(side: float) -> void:
	# Цилиндрическая ручка создаётся примитивом, чтобы не требовались внешние модели.
	var handle := MeshInstance3D.new()
	handle.name = "DoorHandleFront" if side > 0.0 else "DoorHandleBack"
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.025
	handle_mesh.bottom_radius = 0.025
	handle_mesh.height = 0.12
	handle.mesh = handle_mesh
	handle.position = Vector3(
		door_width * 0.5 - 0.12,
		0.0,
		side * (leaf_thickness * 0.5 + 0.025)
	)
	# Сохраняем ориентацию ручки и зеркально разворачиваем заднюю сторону,
	# чтобы обе ручки выступали от своей стороны полотна.
	handle.rotation.z = deg_to_rad(90.0)
	if side < 0.0:
		handle.rotation.x = PI
	handle.material_override = _make_material(Color(0.75, 0.62, 0.28))
	_door_leaf.add_child(handle)

func _add_box(parent: Node3D, node_name: String, size: Vector3, local_position: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)

	# У брусков рамы есть собственная статичная физическая форма.
	var frame_body := parent.get_node_or_null("FrameCollision") as StaticBody3D
	if frame_body == null:
		frame_body = StaticBody3D.new()
		frame_body.name = "FrameCollision"
		frame_body.collision_layer = 1
		parent.add_child(frame_body)
	var collision := CollisionShape3D.new()
	var collision_box := BoxShape3D.new()
	collision_box.size = size
	collision.shape = collision_box
	collision.position = local_position
	frame_body.add_child(collision)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material

func _configure_triggers() -> void:
	if _open_trigger != null:
		_open_trigger.collision_layer = 0
		_open_trigger.collision_mask = 1
		_set_sphere_shape(_open_trigger, door_open_radius)

	if _passage_trigger != null:
		# Триггер перехода сам не является физическим препятствием, но отслеживает слой игрока.
		_passage_trigger.collision_layer = 0
		_passage_trigger.collision_mask = 1
		_passage_trigger.monitoring = true
		_set_box_shape(_passage_trigger, Vector3(door_width, door_height, passage_depth))

func _set_sphere_shape(area: Area3D, radius: float) -> void:
	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		area.add_child(shape_node)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape_node.shape = sphere

func _set_box_shape(area: Area3D, size: Vector3) -> void:
	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		area.add_child(shape_node)
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box

func _create_auto_close_timer() -> void:
	_auto_close_timer = Timer.new()
	_auto_close_timer.name = "AutoCloseTimer"
	_auto_close_timer.one_shot = true
	_auto_close_timer.timeout.connect(_on_auto_close_timeout)
	add_child(_auto_close_timer)

func _connect_signals() -> void:
	if _open_trigger != null:
		_open_trigger.body_entered.connect(_on_player_entered)
		_open_trigger.body_exited.connect(_on_player_exited)
	if _passage_trigger != null:
		_passage_trigger.body_entered.connect(_on_passage_entered)
		_passage_trigger.body_exited.connect(_on_passage_exited)

func _on_player_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	is_player_near = true
	_current_player = body as CharacterBody3D
	_auto_close_timer.stop()

func _on_player_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	is_player_near = false
	_current_player = null
	if is_door_open and _auto_close_timer != null and _auto_close_timer.is_inside_tree():
		# При смене сцены дверь удаляется вместе с триггером; не запускаем уже удаляемый таймер.
		_auto_close_timer.start(auto_close_delay)

func _on_auto_close_timeout() -> void:
	# Повторный вход игрока останавливает Timer и сбрасывает is_player_near.
	if is_player_near or not is_door_open:
		return
	is_door_open = false
	_animate_door(false)

func _animate_door(open: bool) -> void:
	if _door_pivot == null:
		return
	# У открытого полотна отключаем физическую форму, чтобы она не перекрывала проём.
	# При закрытии включаем её сразу, до начала поворота обратно.
	if _leaf_collision != null:
		_leaf_collision.disabled = open
	if _door_tween != null and _door_tween.is_running():
		_door_tween.kill()

	var target_angle: float = deg_to_rad(door_open_angle_deg) * door_open_direction if open else 0.0
	_door_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_door_tween.tween_property(_door_pivot, "rotation:y", target_angle, door_animation_time)

func _refresh_portal_state() -> void:
	if _door_pivot == null:
		return
	var portal_is_open: bool = absf(rad_to_deg(_door_pivot.rotation.y)) > 10.0
	# Дёргаем сцену и SubViewport только при изменении фактического состояния проёма.
	if _portal_state_initialized and portal_is_open == _last_portal_is_open:
		return
	_portal_state_initialized = true
	_last_portal_is_open = portal_is_open
	if _portal_surface != null:
		_portal_surface.visible = portal_is_open
	if _portal_controller != null and _portal_controller.has_method("set_door_open"):
		_portal_controller.call("set_door_open", portal_is_open)

func _on_passage_entered(body: Node3D) -> void:
	print("DoorController: body_entered DoorTransitionTrigger: %s, игрок=%s" % [
		body.name, body.is_in_group("player")
	])
	if not body.is_in_group("player"):
		return
	var player := body as CharacterBody3D
	if player == null:
		return
	_players_in_passage[player.get_instance_id()] = {
		"player": player,
		"previous_side": _get_door_side(player)
	}

func _on_passage_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_players_in_passage.erase(body.get_instance_id())

func _check_for_completed_crossing() -> void:
	if not is_door_open or _players_in_passage.is_empty():
		return

	print("DoorController: проверяю пересечение DoorTransitionTrigger, игроков=%d" % _players_in_passage.size())
	for instance_id in _players_in_passage.keys():
		var crossing: Dictionary = _players_in_passage[instance_id]
		var player := crossing.get("player") as CharacterBody3D
		if player == null or not is_instance_valid(player):
			_players_in_passage.erase(instance_id)
			continue

		var current_side: float = _get_door_side(player)
		var previous_side: float = crossing["previous_side"]
		crossing["previous_side"] = current_side
		_players_in_passage[instance_id] = crossing

		print("DoorController: сторона игрока %.3f -> %.3f" % [previous_side, current_side])
		# Портал двусторонний: любое пересечение плоскости ведёт в соседнюю комнату.
		if _has_crossed_in_configured_direction(previous_side, current_side):
			_perform_transition(player)
			return

func _perform_transition(player: CharacterBody3D) -> void:
	# Сохраняем состояние игрока и откладываем смену сцены до конца физического шага.
	var crossing_sign: int = 1 if _get_door_side(player) >= 0.0 else -1
	print("DoorController: переход через портал, сторона назначения=%d, crossing_direction=%d" % [
		crossing_sign, crossing_direction
	])
	if not _save_transition_data(player):
		return
	_schedule_scene_change(room_scene_path)

func _save_transition_data(player: CharacterBody3D) -> bool:
	var transition_data: Node = _transition_data_override
	if transition_data == null:
		transition_data = get_node_or_null("/root/SceneTransitionData")
	if transition_data == null:
		push_error("DoorController: Autoload SceneTransitionData не зарегистрирован.")
		return false
	# В этой сцене камера находится внутри Head, а не прямо на корне Player.
	var player_camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	# Тестовый override может реализовывать старый однопараметрический spy;
	# реальный Autoload получает также Camera3D для сохранения её углов.
	if _transition_data_override != null:
		transition_data.call("save", player)
	else:
		transition_data.call("save", player, player_camera)
	return true

func _schedule_scene_change(scene_path: String) -> void:
	# Смена сцены откладывается, потому что пересечение обрабатывается во время физического шага.
	if _scene_change_scheduler.is_valid():
		_scene_change_scheduler.call(scene_path)
	else:
		get_tree().call_deferred("change_scene_to_file", scene_path)

func _has_crossed_in_configured_direction(previous_side: float, current_side: float) -> bool:
	var crossed_forward: bool = previous_side < 0.0 and current_side >= 0.0
	var crossed_backward: bool = previous_side > 0.0 and current_side <= 0.0
	if bidirectional_transition:
		return crossed_forward or crossed_backward
	if crossing_direction >= 0:
		return crossed_forward
	return crossed_backward

func _get_door_side(player: CharacterBody3D) -> float:
	# Нормаль берём из глобального базиса, чтобы знак сохранялся при повороте DoorFrame.
	var door_normal: Vector3 = -global_transform.basis.z.normalized()
	return (player.global_position - global_position).dot(door_normal)
