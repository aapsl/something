extends Node

## Контроллер загружает соседнюю комнату в отдельный SubViewport и рисует её
## на плоскости в проёме. Саму дверь и её открывание контролирует DoorController.

## Общий ресурс настроек. Если он не назначен, используются поля ниже.
@export var config: PortalConfig
## Путь к игроку в демонстрационной сцене.
@export var player_path: NodePath = NodePath("../../../Player")
## Узел рамы, относительно которого считается направление взгляда и расстояние.
@export var door_frame_path: NodePath = NodePath("../..")
## Путь к SubViewport с изолированным 3D-миром.
@export var portal_viewport_path: NodePath = NodePath("../PortalViewport")
## Узел, в который помещается загруженная сцена комнаты.
@export var room_container_path: NodePath = NodePath("../PortalViewport/RoomScene")
## Маркер входа в комнату и позиция камеры портала.
@export var room_entry_path: NodePath = NodePath("../PortalViewport/RoomEntry")
@export var portal_camera_path: NodePath = NodePath("../PortalViewport/PortalCamera")
## Плоскость в дверном проёме, показывающая изображение SubViewport.
@export var portal_surface_path: NodePath = NodePath("../../PortalSurface")
## Радиусный триггер дальности; фактическая выгрузка дополнительно использует гистерезис.
@export var load_trigger_path: NodePath = NodePath("../../DoorTrigger")

## Значения по умолчанию. Назначенный PortalConfig заменит их при запуске.
@export_file("*.tscn") var room_scene_path: String = "res://scenes/room.tscn"
@export_range(1.0, 500.0, 0.5, "suffix:m") var load_distance: float = 20.0
@export_range(1.0, 1000.0, 0.5, "suffix:m") var unload_distance: float = 30.0
@export_range(0.0, 120.0, 0.1, "suffix:s") var unload_delay: float = 5.0
@export_range(10.0, 120.0, 1.0, "suffix:°") var portal_camera_fov: float = 75.0
@export var viewport_size: Vector2i = Vector2i(540, 990)
@export_range(0.0, 1.0, 0.01) var flip_hysteresis: float = 0.15
## Максимальная величина смещения камеры в комнате при приближении к двери.
@export_range(0.0, 1.0, 0.01) var parallax_strength: float = 0.15
## Дистанция, на которой эффект плавно затухает до нуля.
@export_range(0.1, 10.0, 0.1) var parallax_falloff: float = 3.0

var _player: CharacterBody3D
var _door_frame: Node3D
var _portal_viewport: SubViewport
var _room_container: Node3D
var _room_entry: Marker3D
var _portal_camera: Camera3D
var _portal_surface: MeshInstance3D
var _load_trigger: Area3D
var _room_instance: Node3D
var _door_is_open: bool = false
var _was_flipped: bool = false
var _load_is_running: bool = false
var _load_requested: bool = false
var _distance_timer: Timer
var _unload_timer: Timer

func _ready() -> void:
	_apply_config()
	_cache_scene_nodes()
	_setup_viewport()
	_configure_load_trigger()
	_setup_timers()
	_update_portal_surface()

func _apply_config() -> void:
	if config == null:
		return
	room_scene_path = config.room_scene_path
	load_distance = config.load_distance
	unload_distance = max(config.unload_distance, config.load_distance)
	unload_delay = config.unload_delay
	portal_camera_fov = config.portal_camera_fov
	viewport_size = config.viewport_size
	flip_hysteresis = config.flip_hysteresis

func _cache_scene_nodes() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_door_frame = get_node_or_null(door_frame_path) as Node3D
	_portal_viewport = get_node_or_null(portal_viewport_path) as SubViewport
	_room_container = get_node_or_null(room_container_path) as Node3D
	_room_entry = get_node_or_null(room_entry_path) as Marker3D
	_portal_camera = get_node_or_null(portal_camera_path) as Camera3D
	_portal_surface = get_node_or_null(portal_surface_path) as MeshInstance3D
	_load_trigger = get_node_or_null(load_trigger_path) as Area3D

func _setup_viewport() -> void:
	if _portal_viewport == null:
		push_error("PortalController: не найден PortalViewport.")
		return

	# Собственный World3D не даёт геометрии комнаты смешиваться с миром MainScene.
	_portal_viewport.own_world_3d = true
	_portal_viewport.size = viewport_size
	_portal_viewport.transparent_bg = false
	_portal_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_portal_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	if _portal_camera != null:
		_portal_camera.fov = portal_camera_fov
		# Ближняя плоскость портальной камеры не должна отсекать геометрию у входа.
		_portal_camera.near = 0.01
		_portal_camera.current = true
		print("PortalController: near PortalCamera=%.3f" % _portal_camera.near)

	if _portal_surface != null:
		var shader: Shader = load("res://shaders/portal_shader.gdshader")
		if shader != null:
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("portal_texture", _portal_viewport.get_texture())
			_portal_surface.material_override = material

func _configure_load_trigger() -> void:
	if _load_trigger == null:
		return
	_load_trigger.collision_layer = 0
	_load_trigger.collision_mask = 1
	var shape_node := _load_trigger.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		_load_trigger.add_child(shape_node)
	var sphere := SphereShape3D.new()
	sphere.radius = load_distance
	shape_node.shape = sphere

func _setup_timers() -> void:
	# Проверка дистанции выполняется пять раз в секунду, а не каждый кадр.
	_distance_timer = Timer.new()
	_distance_timer.name = "DistanceCheckTimer"
	_distance_timer.wait_time = 0.2
	_distance_timer.one_shot = false
	_distance_timer.timeout.connect(_on_distance_check_timeout)
	add_child(_distance_timer)
	_distance_timer.start()

	_unload_timer = Timer.new()
	_unload_timer.name = "RoomUnloadTimer"
	_unload_timer.one_shot = true
	_unload_timer.timeout.connect(_unload_room)
	add_child(_unload_timer)

func _on_distance_check_timeout() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null or _door_frame == null:
		return

	var distance: float = _player.global_position.distance_to(_door_frame.global_position)
	if distance <= load_distance:
		_unload_timer.stop()
		if not _load_is_running and _room_instance == null:
			_request_room_load()
	elif distance > unload_distance and (_room_instance != null or _load_is_running):
		if _room_instance != null and _unload_timer.is_stopped():
			_unload_timer.start(unload_delay)
	else:
		# Между радиусами загрузки и выгрузки комнату сохраняем загруженной.
		_unload_timer.stop()

func _request_room_load() -> void:
	if room_scene_path.is_empty():
		push_warning("PortalController: путь к сцене комнаты не задан.")
		return

	var error: Error = ResourceLoader.load_threaded_request(room_scene_path, "PackedScene")
	if error != OK and error != ERR_BUSY:
		push_warning("PortalController: не удалось начать фоновую загрузку: %s" % error_string(error))
		return

	_load_requested = true
	_load_is_running = true

func _process_threaded_load() -> void:
	if not _load_requested:
		return

	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(room_scene_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_load_requested = false
	_load_is_running = false

	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("PortalController: не удалось загрузить комнату (статус %s)." % status)
		return

	var packed_scene := ResourceLoader.load_threaded_get(room_scene_path) as PackedScene
	if packed_scene == null or _room_container == null:
		push_warning("PortalController: ресурс комнаты не является PackedScene.")
		return

	var instance := packed_scene.instantiate()
	if not instance is Node3D:
		instance.queue_free()
		push_warning("PortalController: корень room.tscn должен быть Node3D.")
		return

	_room_instance = instance as Node3D
	_room_instance.name = "LoadedRoom"
	_room_container.add_child(_room_instance)
	# Комната содержит Player для финального перехода, но в превью его камера
	# не должна перехватывать PortalCamera.
	if _portal_camera != null:
		_portal_camera.current = true
	_unload_timer.stop()
	_update_portal_surface()

func _process(_delta: float) -> void:
	_process_threaded_load()
	if _is_active():
		_update_portal_camera()
	_update_portal_surface()

func _is_active() -> bool:
	return _door_is_open and _room_instance != null and _player != null and _portal_viewport != null

func set_door_open(is_open: bool) -> void:
	## Вызывается дверью при изменении угла. Закрытый портал не перерисовывается.
	_door_is_open = is_open
	_update_portal_surface()

func set_room_scene_path(scene_path: String) -> void:
	## Дверь передаёт сюда путь, выбранный в её настройках Inspector.
	room_scene_path = scene_path

func _update_portal_surface() -> void:
	if _portal_surface != null:
		# До загрузки оставляем чёрную текстуру в проёме как заглушку.
		_portal_surface.visible = _door_is_open
	if _portal_viewport != null:
		_portal_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if _is_active() else SubViewport.UPDATE_DISABLED
		)

func _update_portal_camera() -> void:
	if _portal_camera == null or _room_entry == null or _door_frame == null or _player == null:
		return

	# Считаем направление от игрока к центру двери и расстояние до неё.
	var to_door: Vector3 = _door_frame.global_position - _player.global_position
	var distance: float = to_door.length()
	if distance < 0.0001:
		return
	var view_dir: Vector3 = to_door / distance
	var door_basis: Basis = _door_frame.global_transform.basis
	var door_normal: Vector3 = -door_basis.z.normalized()
	var door_right: Vector3 = door_basis.x.normalized()
	var door_up: Vector3 = door_basis.y.normalized()
	var side_dot: float = view_dir.dot(door_normal)

	# Сохраняем прежний гистерезис, чтобы камера не дёргалась около плоскости двери.
	if side_dot < -flip_hysteresis:
		_was_flipped = true
	elif side_dot > flip_hysteresis:
		_was_flipped = false
	if absf(side_dot) <= flip_hysteresis:
		var expected_side: float = -1.0 if _was_flipped else 1.0
		if side_dot * expected_side < 0.0:
			view_dir = (view_dir - door_normal * side_dot + door_normal * expected_side * flip_hysteresis).normalized()

	# Чем ближе игрок, тем заметнее смещение. Ограничиваем делитель и плавно
	# сводим эффект к нулю на дистанции parallax_falloff.
	var safe_distance: float = maxf(distance, 0.5)
	var strength: float = clampf(parallax_strength / safe_distance, 0.0, parallax_strength)
	var falloff_end: float = maxf(parallax_falloff, 0.51)
	var falloff_start: float = minf(0.5, falloff_end * 0.5)
	var falloff_weight: float = 1.0 - smoothstep(falloff_start, falloff_end, distance)
	strength *= falloff_weight

	var angle_offset: Vector3 = view_dir - door_normal
	var camera_offset: Vector3 = (
		door_right * angle_offset.dot(door_right) * strength
		+ door_up * angle_offset.dot(door_up) * strength
	)
	_portal_camera.global_position = _room_entry.global_position + camera_offset
	if view_dir.length_squared() > 0.0001:
		_portal_camera.look_at(_room_entry.global_position + view_dir, Vector3.UP)
	_portal_camera.fov = portal_camera_fov

func _unload_room() -> void:
	if _player != null and _door_frame != null:
		var distance: float = _player.global_position.distance_to(_door_frame.global_position)
		if distance <= unload_distance:
			return
	if _room_instance != null and is_instance_valid(_room_instance):
		_room_instance.queue_free()
	_room_instance = null
	_update_portal_surface()
