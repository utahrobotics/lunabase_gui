extends Node


# TODO Add PS4 control enums
enum {
	REQUEST_TERMINATE,
	ODOMETRY,
	ARM_ANGLE,
	JOY_INPUT,
	MAKE_AUTONOMOUS,
	MAKE_MANUAL,
	ECHO,
	MANUAL_HOME			# Calibrates motors
}

signal manual_home_complete
signal odometry_received(odom)
signal arm_angle_received(angle)
signal packet_received(delta)

const DEADZONE := 0.1
const BROADCAST_DELAY := 1.0
const INPUT_RATE := 20

var bot_tcp_server := TCP_Server.new()
var bot_tcp: StreamPeerTCP

var bot_udp := PacketPeerUDP.new()

var broadcaster := PacketPeerUDP.new()

var _manually_homing := false
var _last_packet_time := OS.get_system_time_msecs()
var start_time := OS.get_system_time_secs()
var broadcasting := false
var listening := false
var bind_addr: String
var bind_port: int
var broadcast_timer := Timer.new()
var _input_timer := 0.0


func _ready():
	set_process_input(false)
	set_process(false)
	add_child(broadcast_timer)
	broadcast_timer.connect("timeout", self, "broadcast")


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
	broadcast_timer.start(BROADCAST_DELAY)
	return OK 


func start_listening(addr: String, port: int) -> int:
	assert(addr.is_valid_ip_address())
	
	var err := bot_udp.listen(port, addr)
	if err != OK:
		return err
	
	err = bot_tcp_server.listen(port + 1, addr)
	if err != OK:
		return err

	bind_addr = addr
	bind_port = port
	set_process(true)
	listening = true
	return OK


func reset_connection():
	broadcaster = PacketPeerUDP.new()
	bot_udp = PacketPeerUDP.new()
	bot_tcp = null
	bot_tcp_server = TCP_Server.new()
	broadcasting = false
	listening = false
	set_process(false)
	set_process_input(false)
	broadcast_timer.stop()


func broadcast():
	broadcaster.put_packet((bind_addr + ":" + str(bind_port)).to_utf8())


func make_autonomous():
	bot_tcp.put_data(_make_byte(MAKE_AUTONOMOUS))
	push_warning("Sent MAKE_AUTONOMOUS to bot")


func make_manual():
	bot_tcp.put_data(_make_byte(MAKE_MANUAL))
	push_warning("Sent MAKE_MANUAL to bot")


func manual_home(idx: int):
	_manually_homing = true
	var data := _make_byte(MANUAL_HOME)
	assert(idx >= 0 and idx < 256)
	data.append(idx)
	bot_tcp.put_data(data)
	push_warning("Sent MANUAL_HOME to bot")


func _input(event):
	if (event is InputEventJoypadMotion and abs(event.axis_value) >= DEADZONE) or \
		event is InputEventJoypadButton:
		if event is InputEventJoypadMotion and _input_timer > 0: return
		_input_timer = 1.0 / INPUT_RATE
		if event.is_action_pressed("end_manual_home"): emit_signal("manual_home_complete")
		
		var msg := _get_controller_state()
		msg.insert(0, JOY_INPUT)
		var err := bot_udp.put_packet(msg)
		if err != OK:
			push_error("Faced error code " + str(err) + " while sending input data!")


func _process(delta):
	if _input_timer > 0:
		_input_timer -= delta
	match bot_udp.get_available_packet_count():
		0: pass
		-1:
			push_error("Got -1")
		_: _poll_udp()
	
	if bot_tcp == null:
		if bot_tcp_server.is_connection_available():
			bot_tcp = bot_tcp_server.take_connection()
			bot_tcp.set_no_delay(true)
			if broadcasting:
				broadcasting = false
				broadcast_timer.stop()
		return
	
	match bot_tcp.get_available_bytes():
		0: pass
		-1:
			push_error("Got -1")
		_: _poll_tcp()


func _poll_udp():
	var msg := bot_udp.get_packet()
	if msg.size() == 0:
		push_error("Got 0 length message")
		return
	
	var current_time := OS.get_system_time_msecs()
	emit_signal("packet_received", current_time - _last_packet_time)
	_last_packet_time = current_time
	
	if msg.get_string_from_utf8() == "hello":
		set_process_input(true)
		var err := bot_udp.set_dest_address(bot_udp.get_packet_ip(), bot_udp.get_packet_port())
		if broadcasting:
			if err != OK:
				push_error("Error code: " + str(err) + " while trying to connect to Lunabot_udp")
				return
			broadcasting = false
			broadcast_timer.stop()
	
	_handle_message(msg)


func _poll_tcp():
	if not bot_tcp.is_connected_to_host():
		push_error("Lost connection to lunabot!")
		get_tree().change_scene("res://scenes/bind_addr.tscn")
		reset_connection()
		return
	
	var result := bot_tcp.get_data(bot_tcp.get_available_bytes())
	
	if result[0] != OK:
		push_error("Error code: " + str(result[0]) + " while trying to receive TCP packet")
		return
	
	var msg: PoolByteArray = result[1]
	
	if msg.size() == 0:
		push_error("Got 0 length message")
		return
	
	var current_time := OS.get_system_time_msecs()
	emit_signal("packet_received", current_time - _last_packet_time)
	_last_packet_time = current_time
	
	_handle_message(msg)


func _handle_message(msg: PoolByteArray):
	var header := msg[0]
	msg.remove(0)
	match header:
		REQUEST_TERMINATE:
			push_warning("bot_udp has requested to terminate")
		ODOMETRY:
			# Pass data to rust module to deserialize
			emit_signal("odometry_received", Odometry.new(
				Serde.deserialize_quat(msg.subarray(0, 15)),
				Serde.deserialize_vector3(msg.subarray(16, 27)),
				Serde.deserialize_vector3(msg.subarray(28, 39)),
				Serde.deserialize_quat(msg.subarray(40, 55))
			))
		ARM_ANGLE:
			emit_signal("arm_angle_received", Serde.deserialize_f32(msg))
		ECHO:
			match msg[0]:
				MAKE_AUTONOMOUS:
					push_warning("Bot is autonomous")
				MAKE_MANUAL:
					push_warning("Bot is manual")
		_:
			push_error("Received unrecognized header: " + str(msg[0]))


func _get_joy_axis(device: int, axis: int) -> float:
	var value := Input.get_joy_axis(device, axis)
	if abs(value) < DEADZONE:
		return 0.0
	return value


func _get_controller_state() -> PoolByteArray:
	return _concat_bytes([
		Serde.serialize_f32(_get_joy_axis(0, JOY_AXIS_0)),
		Serde.serialize_f32(_get_joy_axis(0, JOY_AXIS_1)),
		Serde.serialize_f32(_get_joy_axis(0, JOY_AXIS_2)),
		Serde.serialize_f32(_get_joy_axis(0, JOY_AXIS_6)),
		Serde.serialize_f32(_get_joy_axis(0, JOY_AXIS_7)),
		Serde.serialize_f32(_get_joy_axis(0, JOY_AXIS_3)),
		int(Input.is_joy_button_pressed(0, JOY_DPAD_RIGHT)) - int(Input.is_joy_button_pressed(0, JOY_DPAD_LEFT)),
		int(Input.is_joy_button_pressed(0, JOY_DPAD_UP)) - int(Input.is_joy_button_pressed(0, JOY_DPAD_DOWN)),
		Serde.serialize_bool_array([
			Input.is_joy_button_pressed(0, JOY_SONY_SQUARE),
			Input.is_joy_button_pressed(0, JOY_SONY_X),
			Input.is_joy_button_pressed(0, JOY_SONY_CIRCLE),
			Input.is_joy_button_pressed(0, JOY_SONY_TRIANGLE),
			Input.is_joy_button_pressed(0, JOY_L),
			Input.is_joy_button_pressed(0, JOY_R),
			Input.is_joy_button_pressed(0, JOY_L2),
			Input.is_joy_button_pressed(0, JOY_R2),
			Input.is_joy_button_pressed(0, JOY_SELECT),
			Input.is_joy_button_pressed(0, JOY_START),
#			false, 		# left stick
#			false,		# right stick
#			false,		# unknown
#			false		# unknown
		])
	])


static func _concat_bytes(bytes_arr: Array) -> PoolByteArray:
	var bytes: PoolByteArray = bytes_arr[0]
	for i in range(1, bytes_arr.size()):
		bytes.append_array(bytes_arr[i])
	return bytes


func _make_byte(num: int) -> PoolByteArray:
	assert(num >= 0 and num < 256)
	return PoolByteArray([num])


func _get_runtime() -> int:
	return OS.get_system_time_secs() - start_time
