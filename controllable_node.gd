class_name ControllableNode
extends Spatial


signal camera_lock_changed(val)

export var speed := 7.0
export var acceleration_weight := 15.0
export var mouse_sensitivity := 0.003

var locked := true

var _movement_vector: Vector3
var _linear_velocity: Vector3


static func exp_weight_conversion(weight: float) -> float:
	return 1.0 - exp(- weight)


func _input(event):
	if event.is_action_pressed("camera_lock"):
		locked = not locked
		if locked:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			
		emit_signal("camera_lock_changed", locked)
	
	if locked:
		_movement_vector = Vector3.ZERO
		return
	
	if event is InputEventMouseMotion:
		rotation.x -= event.relative.y * mouse_sensitivity
		rotation.y -= event.relative.x * mouse_sensitivity
	
	_movement_vector = Vector3(
		Input.get_action_strength("camera_right") - Input.get_action_strength("camera_left"),
		Input.get_action_strength("camera_up") - Input.get_action_strength("camera_down"),
		Input.get_action_strength("camera_back") - Input.get_action_strength("camera_forward")
	)


func _process(delta):
	_linear_velocity = _linear_velocity.linear_interpolate(global_transform.basis.xform(_movement_vector * speed), exp_weight_conversion(delta * acceleration_weight))
	global_transform.origin += _linear_velocity * delta
