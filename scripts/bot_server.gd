extends Node


const JOY_STEPS := 20
const JOY_BUTTON_ORDER := [
	JOY_DPAD_RIGHT,
	JOY_DPAD_LEFT,
	JOY_DPAD_UP,
	JOY_DPAD_DOWN,
	JOY_SONY_SQUARE,
	JOY_SONY_X,
	JOY_SONY_CIRCLE,
	JOY_SONY_TRIANGLE,
	JOY_L,
	JOY_R,
	-1,
	-1,
	JOY_SELECT,
	JOY_START
]

const JOY_AXIS_ORDER := [
	JOY_AXIS_0,
	JOY_AXIS_1,
	JOY_AXIS_2,
	JOY_AXIS_6,
	JOY_AXIS_7,
	JOY_AXIS_3
]

# TODO Add PS4 control enums
enum {
	PING,
	ODOMETRY,
	ARM_DEPTH,
	JOY_AXIS,
	INITIATE_AUTONOMY_MACHINE,
	MAKE_MANUAL,
	START_MANUAL_HOME,			# Calibrates motors
	CONNECTED,
	ROSOUT,					# Rosout msg from bot, should be a security level and a ready-to-print string
	SEND_ROSOUT,
	DONT_SEND_ROSOUT,
	DUMP_ACTION,
	FAKE_INIT,
	JOY_BUTTON,
	VID_STREAM,
	SEND_STREAM,
	DONT_SEND_STREAM,
	DIG_ACTION
}

signal odometry(odometry)
signal arm_depth(angle)
signal autonomy_changed
signal rosout(level, msg)
signal packet_received(delta)
signal image_received(img)

const DEADZONE := 0.1
const BROADCAST_DELAY := 0.5
const INPUT_RATE := 10

var bot_tcp_server := TCP_Server.new()
var bot_tcp: StreamPeerTCP

var bot_udp := PacketPeerUDP.new()

var broadcaster := PacketPeerUDP.new()

var start_time := OS.get_system_time_secs()
var broadcasting := false
var listening := false
var bind_addr: String
var bind_port: int

var _manually_homing := false
var _last_packet_time := OS.get_system_time_msecs()
var _broadcast_timer := Timer.new()
var _is_autonomous := true
var _is_sending_rosout := true
var _is_sending_stream := true
var _was_in_deadzone := false

var _last_axes := {}
var _pending_joy_events = {}
var _joy_timer: Timer
var _frame_id := 0


func get_is_autonomous() -> bool:
	return _is_autonomous


func get_is_sending_rosout() -> bool:
	return _is_sending_rosout


func _ready():
	assert(JOY_STEPS < 32 and JOY_STEPS > 0)
	set_process_input(false)
	set_process(false)
	add_child(_broadcast_timer)
	# warning-ignore:return_value_discarded
	_broadcast_timer.connect("timeout", self, "broadcast")
	
	_joy_timer = Timer.new()
	add_child(_joy_timer)
		
	_joy_timer.wait_time = 1.0 / JOY_STEPS
	# warning-ignore:return_value_discarded
	_joy_timer.connect("timeout", self, "_push_pending_joy")
	
#	_joy_timer.start()


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
	_broadcast_timer.start(BROADCAST_DELAY)
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
	_broadcast_timer.stop()


func broadcast():
	# warning-ignore:return_value_discarded
	broadcaster.put_packet((bind_addr + ":" + str(bind_port)).to_utf8())


func initiate_autonomy_machine():
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(INITIATE_AUTONOMY_MACHINE))
	push_warning("Sent INITIATE_AUTONOMY_MACHINE to bot")


func make_manual():
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(MAKE_MANUAL))
	push_warning("Sent MAKE_MANUAL to bot")


func dump_action():
	if not _is_autonomous:
		push_warning("Cannot dump without entering manual control")
		return
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(DUMP_ACTION))
	push_warning("Sent DUMP_ACTION to bot")


func dig_action():
	if not _is_autonomous:
		push_warning("Cannot dig without entering manual control")
		return
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(DIG_ACTION))
	push_warning("Sent DIG_ACTION to bot")


func fake_init():
	if not _is_autonomous:
		push_warning("Cannot fake init without entering manual control")
		return
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(FAKE_INIT))
	push_warning("Sent FAKE_INIT to bot")


func start_manual_home(idx: int):
	_manually_homing = true
	var data := _make_byte(START_MANUAL_HOME)
	assert(idx >= 0 and idx < 256)
	data.append(idx)
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(data)
	push_warning("Sent START_MANUAL_HOME to bot")


func send_rosout():
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(SEND_ROSOUT))
	_is_sending_rosout = true
	push_warning("Sent SEND_ROSOUT to Lunabot")


func dont_send_rosout():
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(DONT_SEND_ROSOUT))
	_is_sending_rosout = false
	push_warning("Sent DONT_SEND_ROSOUT to Lunabot")


func stream_vid():
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(SEND_STREAM))
	_is_sending_rosout = true
	push_warning("Sent SEND_STREAM to Lunabot")


func dont_stream_vid():
	# warning-ignore:return_value_discarded
	bot_tcp.put_data(_make_byte(DONT_SEND_STREAM))
	_is_sending_rosout = false
	push_warning("Sent DONT_SEND_STREAM to Lunabot")


func _input(event):
	if event is InputEventJoypadMotion:
		if not event.axis in JOY_AXIS_ORDER: return
		var value: float = event.axis_value
		if abs(value) <= DEADZONE:
			value = 0
		_pending_joy_events[event.axis] = value
		
	elif event is InputEventJoypadButton:
		if not event.button_index in JOY_BUTTON_ORDER: return
		if event.button_index == JOY_L2 or event.button_index == JOY_R2: return
		var byte := JOY_BUTTON_ORDER.find(event.button_index)
		if event.pressed: byte += 128
		# warning-ignore:return_value_discarded
		bot_udp.put_packet(PoolByteArray([JOY_BUTTON, byte]))


func _push_pending_joy():
	var payload := PoolByteArray([JOY_AXIS])
	for axis in _pending_joy_events:
		var axis_value: float = _pending_joy_events[axis]
		var order := JOY_AXIS_ORDER.find(axis)
		
		if order <= 2 or order == 5:
			axis_value = (axis_value + 1) / 2
		assert(axis_value >= 0 and axis_value <= 1)
		axis_value = round(axis_value * JOY_STEPS)
		
		if axis in _last_axes and axis_value == _last_axes[axis]:
			continue
		_last_axes[axis] = axis_value
		
		# warning-ignore: narrowing_conversion
		var byte: int = order * 32 + axis_value
		assert(byte >= 0 and byte <= 255)
		payload.append(byte)
	
	if payload.size() == 1: return
	# warning-ignore:return_value_discarded
	bot_udp.put_packet(payload)
#	bot_tcp.put_data(payload)
	_pending_joy_events.clear()


func _process(_delta):
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
				_broadcast_timer.stop()
		return
	
	match bot_tcp.get_available_bytes():
		0:
			if bot_tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				push_error("Lost connection to lunabot!")
				# warning-ignore:return_value_discarded
				get_tree().change_scene("res://scenes/bind_addr.tscn")
				reset_connection()
		-1:
			push_error("Got -1")
		_: _poll_tcp()


func _poll_udp():
	var msg := bot_udp.get_packet()
	if msg.size() == 0:
		push_error("Got 0 length message")
		return
	
	if msg[0] == CONNECTED:
		var err := bot_udp.set_dest_address(bot_udp.get_packet_ip(), bot_udp.get_packet_port())
		if err != OK:
			push_error("Error code: " + str(err) + " while trying to connect to Lunabot_udp")
			return
		if broadcasting:
			broadcasting = false
			_broadcast_timer.stop()
		set_process_input(true)
		_joy_timer.start()
		return
	
	_handle_message(msg)


func _poll_tcp():
	var result := bot_tcp.get_data(bot_tcp.get_available_bytes())
	
	if result[0] != OK:
		push_error("Error code: " + str(result[0]) + " while trying to receive TCP packet")
		return
	
	var msg: PoolByteArray = result[1]
	
	if msg.size() == 0:
		push_error("Got 0 length message")
		return
	
	_handle_message(msg)


func _handle_message(msg: PoolByteArray):
	var current_time := OS.get_system_time_msecs()
	emit_signal("packet_received", current_time - _last_packet_time)
	_last_packet_time = current_time
	
	var header := msg[0]
	msg.remove(0)
	match header:
		PING:
			push_warning("lunabot pinged us!")
		ODOMETRY:
			# Pass data to rust module to deserialize
			emit_signal("odometry", Odometry.new(
				Serde.deserialize_quat(msg.subarray(0, 15)),
				Serde.deserialize_vector3(msg.subarray(16, 27)),
				Serde.deserialize_vector3(msg.subarray(28, 39)),
				Serde.deserialize_vector3(msg.subarray(40, 51))
			))
		ARM_DEPTH:
			emit_signal("arm_depth", Serde.deserialize_f32(msg))
		ROSOUT:
			var level := msg[0]
			msg.remove(0)
			var txt := msg.get_string_from_utf8()
#			var txt := msg.decompress_dynamic(-1, File.COMPRESSION_GZIP).get_string_from_utf8()
			emit_signal("rosout", level, txt)
		INITIATE_AUTONOMY_MACHINE:
			_is_autonomous = true
			push_warning("Bot set itself to autonomous!")
			emit_signal("autonomy_changed")
		MAKE_MANUAL:
			_is_autonomous = false
			push_warning("Bot set itself to manual!")
			emit_signal("autonomy_changed")
		VID_STREAM:
			var new_frame_id := msg[0]
			msg.remove(0)
			if _frame_id < 220 and new_frame_id < _frame_id: return
			_frame_id = new_frame_id
			var img := Image.new()
			var err := img.load_jpg_from_buffer(msg)
			if err != OK:
				push_error("Error parsing webcam jpg: " + str(err))
				return
			emit_signal("image_received", img)
		_:
			push_error("Received unrecognized header: " + str(header))


func _get_joy_axis(device: int, axis: int) -> float:
	var value := Input.get_joy_axis(device, axis)
	if abs(value) < DEADZONE:
		return 0.0
	return stepify(value, 0.05)


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
