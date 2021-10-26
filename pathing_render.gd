class_name PathingRender
extends Line2D


onready var camera := get_viewport().get_camera()


func _handle_bot_data(parsed: Dictionary) -> void:
	if not BotServer.PATHING in parsed:
		return
	clear_points()
	for p in parsed[BotServer.PATHING]:
		add_point(camera.unproject_position(BotServer.array_to_vector(p)))
