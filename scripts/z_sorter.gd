class_name ZSorter
extends Spatial


var spatials: Array
var camera_origin: Vector3

onready var camera := get_viewport().get_camera()


func _process(_delta):
	camera_origin = camera.global_transform.origin
	spatials.sort_custom(self, "_sorter")
	for i in range(spatials.size()):
		var node: Node = spatials[i][1]
		node.get_parent().move_child(node, i)


func _sorter(a: Array, b: Array) -> bool:
	return a[0].global_transform.origin.distance_squared_to(camera_origin) > b[0].global_transform.origin.distance_squared_to(camera_origin)
