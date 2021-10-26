class_name OdometryListener
extends Label


func _handle_bot_data(parsed: Dictionary) -> void:
	if not BotServer.ODOMETRY in parsed:
		return
	
	text = str(parsed[BotServer.ODOMETRY][get_index()])
