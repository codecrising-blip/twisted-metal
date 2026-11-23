class_name ZoomBurst
extends CanvasLayer
## Round 29: the radial zoom blur of a Darkside Slam over the whole screen (zoom_burst.gdshader), strongest at
## once and easing out over `time` s. Only for the player who slams.

var time := 0.8
var _t := 0.0
var _mat: ShaderMaterial


static func play(tree: SceneTree, seconds := 0.8) -> void:
	var z := ZoomBurst.new()
	z.time = seconds
	z.layer = 5 # over the world, under the HUD panels
	tree.root.add_child(z)


func _ready() -> void:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.offset_right = 0.0
	r.offset_bottom = 0.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/fx/zoom_burst.gdshader")
	r.material = _mat
	add_child(r)
	r.size = get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - clampf(_t / time, 0.0, 1.0)
	_mat.set_shader_parameter("strength", k * k)
	if _t >= time:
		queue_free()
