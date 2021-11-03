class_name AnchoredControl
extends Control


onready var _camera := get_viewport().get_camera()


func _process(delta):
	rect_position = _camera.unproject_position(get_parent().global_transform.origin)
