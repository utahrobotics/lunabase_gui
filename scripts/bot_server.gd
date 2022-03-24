extends Node


# TODO Add PS4 control enums
enum {
	REQUEST_TERMINATE,
	ODOMETRY,
	ARM_ANGLE,
	AUTONOMY_STAGE,
	PATHING,
	COST_MAP,
	REQUEST_COST_MAP,
	AUTONOMY_BIT,
	TARGET_ARM_ANGLE
}

signal packet_received(delta)

const DEADZONE := 0.05
const BROADCAST_DELAY := 1.0

var receiver := PacketPeerUDP.new()
var bot: PacketPeerUDP
var broadcaster := PacketPeerUDP.new()
#var autonomy := true setget set_autonomy

var _last_packet_time := OS.get_system_time_msecs()
var start_time := OS.get_system_time_secs()
var broadcasting := false
var listening := false
var bind_addr: String
var bind_port: int
var broadcast_timer := 0.0


#func set_autonomy(bit: bool) -> void:
#	if bot == null:
#		print("BOT IS NOT CONNECTED, CANNOT CHANGE AUTONOMY STATE")
#		return
#	# warning-ignore:return_value_discarded
##	bot.put_packet(to_json({AUTONOMY_BIT: bit}).to_utf8())
#	autonomy = bit
#	set_process_input(not bit)
##	logs[AUTONOMY_BIT].append([get_runtime(), bit])
#
#	if bit:
#		print("BOT IS FULLY AUTONOMOUS")
#		return
#	print("BOT IS AWAITING INPUT")


func _ready():
	set_process_input(false)


func start_brodcasting(addr: String, port: int) -> int:
	assert(addr.is_valid_ip_address())
	assert(bind_addr.is_valid_ip_address())		# Verify we are listening
	
	var interface_name: String
	for interface in IP.get_local_interfaces():
		var addresses: Array = interface["addresses"]
		if bind_addr in addresses:
			interface_name = interface["name"]
			break
	
	if interface_name.empty():
		return ERR_CANT_RESOLVE
	
	var err := broadcaster.join_multicast_group(addr, interface_name)
	
	if err != OK:
		return err
	
	err = broadcaster.set_dest_address(addr, port)
	
	if err != OK:
		return err
	
	broadcasting = true
	return OK 


func start_listening(addr: String, port: int) -> int:
	assert(addr.is_valid_ip_address())
	
	var err := receiver.listen(port, addr)
	if err != OK:
		return err

	bind_addr = addr
	bind_port = port
	set_process_input(true)
	listening = true
	return OK


func _process(delta):
	if broadcasting:
		if broadcast_timer < BROADCAST_DELAY:
			broadcast_timer += delta
		else:
			broadcast_timer = 0
			# warning-ignore:return_value_discarded
			broadcaster.put_packet((bind_addr + ":" + str(bind_port)).to_utf8())
		
	if not listening: return
	if receiver.get_available_packet_count() == 0: return
	var msg := receiver.get_packet()
	if msg.size() == 0:
		push_error("Got 0 length message")
		return
	
	var current_time := OS.get_system_time_msecs()
	emit_signal("packet_received", current_time - _last_packet_time)
	_last_packet_time = current_time
	
	if bot == null:
		bot = PacketPeerUDP.new()
		var err := bot.set_dest_address(receiver.get_packet_ip(), receiver.get_packet_port())
		if err != OK:
			push_error("Error code: " + str(err) + " while trying to connect to Lunabot")
			bot = null
			return
		broadcasting = false
	
	match msg[0]:
		REQUEST_TERMINATE:
			print("Bot has requested to terminate")
		ODOMETRY:
			# Pass data to rust module to deserialize
			pass
		_:
			push_error("Received unrecognized header: " + str(msg[0]))
	
#	var parsed: Dictionary = parse_json(msg)
#	for key in parsed:
#		var data = parsed[key]
#		match int(key):
#			ODOMETRY:
#				get_tree().root.propagate_call("_handle_odometry", [Odometry.new(data)])
#
#			ARM_ANGLE:
#				get_tree().root.propagate_call("_handle_arm_angle", [data])
#
#			AUTONOMY_STAGE:
#				get_tree().root.propagate_call("_handle_autonomy_stage", [data])
#
#			PATHING:
#				var path := PoolVector3Array()
#				for arr in data:
#					path.append(array_to_vector(arr))
#				get_tree().root.propagate_call("_handle_pathing", [path])
#
#			COST_MAP:
#				assert(false)
#
#			_:
#				prints("Received unrecognized enum:", key)


func _input(event):
	if (event is InputEventJoypadMotion and abs(event.axis_value) >= DEADZONE) or \
		event is InputEventJoypadButton:
		var err := bot.put_packet(to_json(_get_controller_state()).to_ascii())
		if err != OK:
			push_error("Faced error code " + str(err) + "while sending input data!")


func _get_joy_axis(device: int, axis: int) -> float:
	var value := Input.get_joy_axis(device, axis)
	if abs(value) < DEADZONE:
		return 0.0
	return value


func _get_controller_state():
	return {
		"axes": [
			_get_joy_axis(0, JOY_AXIS_0), _get_joy_axis(0, JOY_AXIS_1),
			_get_joy_axis(0, JOY_AXIS_2), _get_joy_axis(0, JOY_AXIS_3),
			_get_joy_axis(0, JOY_AXIS_6),
			_get_joy_axis(0, JOY_AXIS_7)
		],
		"buttons": [
			Input.is_joy_button_pressed(0, JOY_DPAD_LEFT),
			Input.is_joy_button_pressed(0, JOY_DPAD_RIGHT),
			Input.is_joy_button_pressed(0, JOY_DPAD_UP),
			Input.is_joy_button_pressed(0, JOY_DPAD_DOWN),
			Input.is_joy_button_pressed(0, JOY_XBOX_X),
			Input.is_joy_button_pressed(0, JOY_XBOX_B),
			Input.is_joy_button_pressed(0, JOY_XBOX_Y),
			Input.is_joy_button_pressed(0, JOY_XBOX_A),
			Input.is_joy_button_pressed(0, JOY_XBOX_X),
			Input.is_joy_button_pressed(0, JOY_XBOX_B),
			Input.is_joy_button_pressed(0, JOY_XBOX_Y),
			Input.is_joy_button_pressed(0, JOY_XBOX_A),
			Input.is_joy_button_pressed(0, JOY_L),
			Input.is_joy_button_pressed(0, JOY_R),
		]
	}


func get_runtime() -> int:
	return OS.get_system_time_secs() - start_time


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
