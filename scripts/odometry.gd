class_name Odometry
extends Reference


var transform: Transform
var linear_velocity: Vector3
var angular_velocity: Vector3


func _init(odometry_data: Array):
	# rotation, origin, lin_vel, ang_vel
	transform = Transform(Basis(BotServer.array_to_vector(odometry_data[0])), BotServer.array_to_vector(odometry_data[1]))
	linear_velocity = BotServer.array_to_vector(odometry_data[2])
	angular_velocity = BotServer.array_to_vector(odometry_data[3])
