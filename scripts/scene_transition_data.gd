extends Node

## Этот узел регистрируется как Autoload под именем SceneTransitionData.
## Он переносит физическую скорость и направление игрока в следующую сцену.

var _has_saved_state: bool = false
var _saved_velocity: Vector3 = Vector3.ZERO
var _saved_basis: Basis = Basis.IDENTITY
var saved_camera_rot_x: float = 0.0
var saved_camera_rot_y: float = 0.0
var _saved_head_pitch: float = 0.0
var _has_saved_head_pitch: bool = false

## Сохраняет скорость, направление игрока и углы камеры перед сменой сцены.
## Позиция намеренно не сохраняется: в новой комнате игрок появляется у входа.
func save(player: CharacterBody3D, camera: Camera3D = null) -> void:
	if player == null:
		push_warning("SceneTransitionData: нельзя сохранить пустого игрока.")
		return

	_saved_velocity = player.velocity
	_saved_basis = player.global_transform.basis
	_has_saved_head_pitch = false
	if camera != null:
		saved_camera_rot_x = camera.rotation.x
		saved_camera_rot_y = camera.rotation.y

		# В этой игре вертикальный угол хранится на узле Head над Camera3D.
		var head := player.get_node_or_null("Head") as Node3D
		if head != null and camera.get_parent() == head:
			_saved_head_pitch = head.rotation.x
			_has_saved_head_pitch = true
	_has_saved_state = true

## Восстанавливает скорость, направление и сохранённые углы камеры.
func apply(player: CharacterBody3D, camera: Camera3D = null) -> void:
	if not _has_saved_state or player == null:
		return

	player.velocity = _saved_velocity
	var player_transform: Transform3D = player.global_transform
	player_transform.basis = _saved_basis
	player.global_transform = player_transform

	if camera != null:
		camera.rotation.x = saved_camera_rot_x
		camera.rotation.y = saved_camera_rot_y
		if _has_saved_head_pitch:
			var head := player.get_node_or_null("Head") as Node3D
			if head != null and camera.get_parent() == head:
				head.rotation.x = _saved_head_pitch

	_has_saved_state = false
	_has_saved_head_pitch = false
