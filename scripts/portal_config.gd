class_name PortalConfig
extends Resource

## Настройки портала и двери, которые можно менять в Inspector и хранить в .tres.

## Сцена комнаты, которая показывается в окне портала и загружается при переходе.
@export_file("*.tscn") var room_scene_path: String = "res://scenes/room.tscn"
## На каком расстоянии от двери начать фоновую загрузку комнаты.
@export_range(1.0, 500.0, 0.5, "suffix:m") var load_distance: float = 20.0
## На каком расстоянии от двери начать отсчёт перед выгрузкой комнаты.
@export_range(1.0, 1000.0, 0.5, "suffix:m") var unload_distance: float = 30.0
## Сколько секунд подождать перед выгрузкой комнаты.
@export_range(0.0, 120.0, 0.1, "suffix:s") var unload_delay: float = 5.0
## Угол обзора отдельной камеры внутри комнаты.
@export_range(10.0, 120.0, 1.0, "suffix:°") var portal_camera_fov: float = 75.0
## Размер картинки портала. Сохраняйте пропорции проёма.
@export var viewport_size: Vector2i = Vector2i(540, 990)
## Порог переключения стороны, с которой смотрит игрок. Уменьшает дрожание направления.
@export_range(0.0, 1.0, 0.01) var flip_hysteresis: float = 0.15
## Радиус, в котором можно нажать interact.
@export_range(0.5, 20.0, 0.1, "suffix:m") var door_open_radius: float = 3.0
## Время ожидания перед автоматическим закрытием.
@export_range(0.0, 60.0, 0.1, "suffix:s") var auto_close_delay: float = 2.0
## Длительность анимации полотна двери.
@export_range(0.05, 10.0, 0.05, "suffix:s") var door_animation_time: float = 0.45
## Угол поворота открытой двери.
@export_range(10.0, 180.0, 1.0, "suffix:°") var door_open_angle_deg: float = 100.0
## Направление поворота: 1 — в одну сторону, -1 — в другую.
@export_range(-1, 1, 2) var door_open_direction: int = 1
