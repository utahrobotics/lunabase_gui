class_name PathingRender
extends Line2D


onready var camera := get_viewport().get_camera()


func _handle_pathing(path: PoolVector3Array) -> void:
	clear_points()
	for p in path:
		add_point(camera.unproject_position(p))
