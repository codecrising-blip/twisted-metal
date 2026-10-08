class_name Blinker
extends Node3D
## Alternates two groups of nodes on and off (police light bar, crane warning light).

@export var period := 0.35

var group_a: Array[Node3D] = []
var group_b: Array[Node3D] = []
var _t := 0.0
var _on_a := true


func _process(delta: float) -> void:
	_t += delta
	if _t < period:
		return
	_t = 0.0
	_on_a = not _on_a
	for n in group_a:
		if is_instance_valid(n):
			n.visible = _on_a
	for n in group_b:
		if is_instance_valid(n):
			n.visible = not _on_a
