class_name MajorAxisPivot
extends Spatial


export var max_major_rotation_degrees := 20.0
export var max_minor_rotation_degrees := 90.0
export var offload_excess_major_rotation := true

onready var _major_angle := rotation.y
onready var _minor_angle := rotation.x


func rotate_about_major(angle: float):
	var max_angle := deg2rad(max_major_rotation_degrees)
	
	_major_angle += angle
	if max_angle != 0 and abs(_major_angle) > max_angle:
		var excess = (abs(_major_angle) - max_angle) * sign(_major_angle)
		_major_angle -= excess
		angle -= excess
		
		if offload_excess_major_rotation:
			get_parent().rotate_object_local(Vector3.UP, excess)
	
	rotate(_get_parent_basis().y, angle)


func rotate_about_minor(angle: float):
	var max_angle := deg2rad(max_minor_rotation_degrees)
	
	_minor_angle += angle
	if abs(_minor_angle) > max_angle:
		var excess = (abs(_minor_angle) - max_angle) * sign(_minor_angle)
		_minor_angle -= excess
		angle -= excess
	
	rotate_object_local(Vector3.RIGHT, angle)


func _get_parent_basis() -> Basis:
	return get_parent().global_transform.basis
