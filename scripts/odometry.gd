class_name Odometry
extends Reference


var transform: Transform
var linear_velocity: Vector3
var angular_velocity: Vector3


func _init(rotation: Vector3, origin: Vector3, lin_vel: Vector3, ang_vel: Vector3):
	# rotation, origin, lin_vel, ang_vel
	transform = Transform(Basis(rotation), origin)
	linear_velocity = lin_vel
	angular_velocity = ang_vel
