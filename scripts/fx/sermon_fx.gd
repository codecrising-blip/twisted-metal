class_name SermonFx
extends Node3D
## Brimstone's Hellfire Sermon (round 28): the church bell tolls (three times over the 6 s), a crown of fire
## burns over the cab and a gilded ring turns above it, so everyone can see the sermon is on (design: "stop
## shooting him for 6 s"). reflect() marks a car that just took its share back.

var car: Vehicle
var _fire: FoamFire
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0
var _tolls := 0
var _ending := false


static func start(v: Vehicle) -> SermonFx:
	var fx := SermonFx.new()
	fx.car = v
	var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.5))
	fx.position = v.model.get_meta("bell", Vector3(0, size.y + 0.15, -0.2))
	v.model.add_child(fx)
	return fx


func _ready() -> void:
	_fire = FoamFire.new()
	_fire.box = Vector3(0.75, 0.05, 0.75)
	_fire.rate = 60.0
	_fire.life = 0.6
	_fire.size = 0.7
	_fire.rise = 2.6
	_fire.inherit = 0.85
	_fire.drag = 1.6
	_fire.rise_in = 6.0
	_fire.on = true
	add_child(_fire)
	_ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.95
	tor.outer_radius = 1.08
	tor.rings = 24
	tor.ring_segments = 6
	_ring.mesh = tor
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.72, 0.25)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 1.6, 0)
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 10.0
	_light.light_energy = 2.0
	_light.position = Vector3(0, 1.0, 0)
	_light.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	_light.visible = GraphicsSettings.high
	add_child(_light)
	_toll()


func _toll() -> void:
	_tolls += 1
	GameFeel.play("church_bell", global_position, car if is_instance_valid(car) else get_parent(), 4.0 - _tolls * 1.5, 1.0)
	_ring.scale = Vector3.ONE * 1.35
	create_tween().tween_property(_ring, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	_ring.rotation.y += delta * 1.4
	_ring.position.y = 1.6 + sin(_t * 2.0) * 0.08
	if not _ending and _tolls < 3 and _t > _tolls * 2.0:
		_toll()
	var a := clampf(1.0 - (_t - 0.0) * 0.0, 0.0, 1.0)
	_ring_mat.albedo_color.a = (0.85 + 0.15 * sin(_t * 9.0)) * a


## A car that hurt Brimstone gets its share back: a flash of hellfire on it.
func reflect(o: Vehicle) -> void:
	if not is_instance_valid(o):
		return
	GameFeel.flash(o.get_parent(), o.aim_point(), 1.6, Color(1.0, 0.55, 0.15), 0.08)
	FxKit.spark(o.get_parent(), o.aim_point(), Vector3.UP)


func finish() -> void:
	if _ending:
		return
	_ending = true
	_fire.on = false
	var tw := create_tween()
	tw.tween_property(_ring, "scale", Vector3.ONE * 0.1, 0.5)
	tw.tween_callback(queue_free).set_delay(1.2)
