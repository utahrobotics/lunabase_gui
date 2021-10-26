extends Node


# TODO Add PS4 control enums
enum {
	ODOMETRY,
	ORIENTATION,
	POSITION,
	ARM_ANGLE,
	AUTONOMY_STAGE,
	AUTONOMY_BIT,
	PATHING,
}

signal packet_received(delta)

const SECRET_PASSWORD := "LMAO"
const SECRET_REPLY := "OKAY"
const PORT_SERVER := 4242
const LOG_FILENAME := "LUNABOT.LOG"

var udp := UDPServer.new()
var bot: PacketPeerUDP
var logs := {
	ODOMETRY: [],
	ORIENTATION: [],
	POSITION: [],
	ARM_ANGLE: [],
	AUTONOMY_STAGE: [],
	AUTONOMY_BIT: [],
	PATHING: []
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
		set_process_input(false)
		print("ERROR CODE STARTING UDP SERVER: " + str(err))
		return
	print("UDP SERVER ACTIVE")


func get_runtime() -> int:
	return OS.get_system_time_secs() - start_time


func _process(_delta):
	# warning-ignore:return_value_discarded
	udp.poll()
	if bot == null:
		if not udp.is_connection_available():
			return
		var peer := udp.take_connection()

		if peer.get_packet_error() != 0:
			print("Packet received from", peer.get_packet_ip(), "but there was error code:", peer.get_packet_error())
			return

		var peer_message := peer.get_packet().get_string_from_utf8()
		if peer_message != SECRET_PASSWORD:
			print("Received connection but password was false: ", peer_message, "\n from ", peer.get_packet_ip())
			return

		print("Received valid connection from bot and replied with secret reply")
		# warning-ignore:return_value_discarded
		peer.put_packet(SECRET_REPLY.to_utf8())
		bot = peer
		return

	var msg := bot.get_packet().get_string_from_utf8()
	if msg.length() > 0:
		var err := validate_json(msg)
		if err.length() > 0:
			print("Recieved unparsable message: ", msg)
			return
		var current_time := OS.get_system_time_msecs()
		emit_signal("packet_received", current_time - _last_packet_time)
		_last_packet_time = current_time
		var parsed := {}
		var parsed_raw: Dictionary = parse_json(msg)
		for key in parsed_raw:
			parsed[int(key)] = parsed_raw[key]
		get_tree().root.propagate_call("_handle_bot_data", [parsed])
		for key in parsed:
			logs[key].append([get_runtime(), parsed[key]])


func _input(event):
	# TODO Add controller input
#	bot.put_packet(to_json([]).to_utf8())
	pass


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
