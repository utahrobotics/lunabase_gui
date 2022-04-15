# A Control node that hovers over its Spatial parent on screen
class_name AnchoredControl
extends Control


export(NodePath) var _target_path: NodePath

onready var _target: Control = get_node(_target_path)
onready var _camera := get_viewport().get_camera()


func _process(_delta):
	rect_position = _camera.unproject_position(get_parent().global_transform.origin)
	_target.set_global_position(rect_global_position)
