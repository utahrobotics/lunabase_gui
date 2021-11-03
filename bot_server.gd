extends Node


# TODO Add PS4 control enums
enum {
	ODOMETRY,
	ARM_ANGLE,
	AUTONOMY_STAGE,
	PATHING,
	COST_MAP,
	REQUEST_COST_MAP,
	AUTONOMY_BIT,
	RIGHT_STICK,
	LEFT_STICK
}

signal packet_received(delta)

const PORT_SERVER := 4242
const LOG_FILENAME := "LUNABOT.LOG"

var udp := UDPServer.new()
var bot: PacketPeerUDP
var logs := {
	ODOMETRY: [],
	ARM_ANGLE: [],
	AUTONOMY_STAGE: [],
	AUTONOMY_BIT: [],
	PATHING: [],
	COST_MAP: []
}
var autonomy := true setget set_autonomy

var _last_packet_time := OS.get_system_time_msecs()
var start_time := OS.get_system_time_secs()


func set_autonomy(bit: bool) -> void:
	if bot == null:
		print("BOT IS NOT CONNECTED, CANNOT CHANGE AUTONOMY STATE")
		return
	# warning-ignore:return_value_discarded
	bot.put_packet(to_json({AUTONOMY_BIT: bit}).to_utf8())
	autonomy = bit
	set_process_input(bit)
	logs[AUTONOMY_BIT].append([get_runtime(), bit])
	
	if bit:
		print("BOT IS FULLY AUTONOMOUS")
		return
	print("BOT IS AWAITING INPUT")
	


func _ready():
	set_process_input(false)
	var err := udp.listen(PORT_SERVER)
	if err != 0:
		set_process(false)
		print("ERROR CODE STARTING UDP SERVER: " + str(err))
		return
	print("UDP SERVER ACTIVE")


func get_runtime() -> int:
	return OS.get_system_time_secs() - start_time


func _process(_delta):
	# warning-ignore:return_value_discarded
	udp.poll()
	if udp.is_connection_available():
		var peer := udp.take_connection()

		if peer.get_packet_error() != 0:
			prints("Packet received from", peer.get_packet_ip(), "but there was error code:", peer.get_packet_error())
			return
		
		if bot == null:
			prints("Received first packet from", peer.get_packet_ip())
			
		else:
			prints("Received packet from different ip:", peer.get_packet_ip(), "listening to new ip...")
		
		bot = peer
	
	if bot == null: return
	var msg := bot.get_packet().get_string_from_utf8()
	if msg.length() == 0: return
	var err := validate_json(msg)
	if err.length() > 0:
		print("Recieved unparsable message: ", msg)
		return
	
	var current_time := OS.get_system_time_msecs()
	emit_signal("packet_received", current_time - _last_packet_time)
	_last_packet_time = current_time
	
	var parsed: Dictionary = parse_json(msg)
	for key in parsed:
		var data = parsed[key]
		match int(key):
			ODOMETRY:
				get_tree().root.propagate_call("_handle_odometry", [Odometry.new(data)])
			
			ARM_ANGLE:
				get_tree().root.propagate_call("_handle_arm_angle", [data])
			
			AUTONOMY_STAGE:
				get_tree().root.propagate_call("_handle_autonomy_stage", [data])
			
			PATHING:
				var path := PoolVector3Array()
				for arr in data:
					path.append(array_to_vector(arr))
				get_tree().root.propagate_call("_handle_pathing", [path])
			
			COST_MAP:
				assert(false)
			
			_:
				prints("Received unrecognized enum:", key)
		
		logs[key].append([get_runtime(), data])


func _input(event):
	# TODO Add controller input
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_0 or event.axis == JOY_AXIS_1:
			bot.put_packet(to_json({LEFT_STICK: [Input.get_joy_axis(0, JOY_AXIS_0), Input.get_joy_axis(0, JOY_AXIS_1)]}).to_utf8())
			
		elif event.axis == JOY_AXIS_2 or event.axis == JOY_AXIS_3:
			bot.put_packet(to_json({RIGHT_STICK: [Input.get_joy_axis(0, JOY_AXIS_2), Input.get_joy_axis(0, JOY_AXIS_3)]}).to_utf8())
		
		return
	
	elif not event is InputEventJoypadButton:
		return
	
	bot.put_packet(to_json({event.button_index: event.pressed}).to_utf8())


func _exit_tree():
	var log_file := File.new()
	# warning-ignore:return_value_discarded
	log_file.open(LOG_FILENAME, File.WRITE)
	log_file.store_string(to_json(logs))


static func array_to_vector(arr: Array):
	if len(arr) == 3:
		return Vector3(arr[0], arr[1], arr[2])
	assert(len(arr) == 2)
	return Vector2(arr[0], arr[1])


static func vector_to_array(vec) -> Array:
	if typeof(vec) == TYPE_VECTOR3:
		return [vec.x, vec.y, vec.z]
	assert(typeof(vec) == TYPE_VECTOR2)
	return [vec.x, vec.y]
