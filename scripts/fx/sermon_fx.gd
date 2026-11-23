class_name SermonFx
extends Node3D
## Brimstone's Hellfire Sermon (round 29, owner: "remove that angel crown completely; the sky glows reddish and a
## hellfire horn sounds, like the gates of hell opening on judgment day"). While it lasts the whole world turns
## to hell: the sky and the sunlight go blood red (the sun and the ambient light tinted, a red glow pouring down
## from the top of the screen), and a huge devil's horn sounds for everyone (audio/sfx/hellfire_horn.ogg, made in
## tools/synth_round29.py). Nothing sits on his car. reflect() marks a car that just took its share back.

const FADE_IN := 0.7
const FADE_OUT := 1.2
const RED_SUN := Color(1.0, 0.3, 0.2)
const RED_AMBIENT := Color(0.75, 0.12, 0.08)

static var _active := 0 # sermons going at once (two Brimstones): the sky goes back only when the last ends
static var _orig_sun := Color.WHITE # the world's own light, taken when the first sermon starts
static var _orig_amb := Color.WHITE

var car: Vehicle
var _t := 0.0
var _ending := false
var _end_t := 0.0
var _sun: DirectionalLight3D
var _sun_color := Color.WHITE
var _env: Environment
var _amb_color := Color.WHITE
var _layer: CanvasLayer
var _glow: ColorRect
var _mat: ShaderMaterial


static func start(v: Vehicle) -> SermonFx:
	var fx := SermonFx.new()
	fx.car = v
	v.get_parent().add_child(fx)
	return fx


func _ready() -> void:
	_active += 1
	var world := get_parent()
	for n in world.find_children("*", "DirectionalLight3D", true, false):
		_sun = n as DirectionalLight3D
		break
	for n in world.find_children("*", "WorldEnvironment", true, false):
		_env = (n as WorldEnvironment).environment
		break
	if _active == 1: # the first: remember the world's own light
		_orig_sun = _sun.light_color if _sun else Color.WHITE
		_orig_amb = _env.ambient_light_color if _env else Color.WHITE
	_sun_color = _orig_sun
	_amb_color = _orig_amb
	_layer = CanvasLayer.new()
	_layer.layer = 4 # over the world, under the HUD
	_glow = ColorRect.new()
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _sky_shader()
	_glow.material = _mat
	_layer.add_child(_glow)
	add_child(_layer)
	_glow.size = get_viewport().get_visible_rect().size
	GameFeel.ui("hellfire_horn", get_tree(), 1.0) # everyone hears hell open, wherever they are
	GameFeel.play("church_bell", car.global_position + Vector3.UP * 2.0, car, -2.0, 0.55) # a cracked, low toll under it
	if GameFeel.camera:
		GameFeel.camera.add_shake(0.35)


static func _sky_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float top = 1.0 - smoothstep(0.0, 0.62, UV.y);
	float roil = noise(vec2(UV.x * 5.0 + TIME * 0.15, UV.y * 3.0 - TIME * 0.35));
	vec3 c = mix(vec3(0.45, 0.02, 0.01), vec3(0.95, 0.22, 0.05), roil * top);
	float a = (top * (0.42 + 0.2 * roil) + 0.1) * amount * (0.92 + 0.08 * sin(TIME * 5.0));
	COLOR = vec4(c, a);
}
"""
	return sh


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / FADE_IN, 0.0, 1.0)
	if _ending:
		_end_t += delta
		k *= 1.0 - clampf(_end_t / FADE_OUT, 0.0, 1.0)
	_mat.set_shader_parameter("amount", k)
	if _sun:
		_sun.light_color = _sun_color.lerp(RED_SUN, k * 0.65)
	if _env:
		_env.ambient_light_color = _amb_color.lerp(RED_AMBIENT, k * 0.7)
	if _ending and _end_t >= FADE_OUT:
		_restore()
		queue_free()


func _restore() -> void:
	_active = maxi(0, _active - 1)
	if _active > 0:
		return
	if _sun:
		_sun.light_color = _sun_color
	if _env:
		_env.ambient_light_color = _amb_color


## A car that hurt Brimstone gets its share back: a flash of hellfire on it.
func reflect(o: Vehicle) -> void:
	if not is_instance_valid(o):
		return
	GameFeel.flash(o.get_parent(), o.aim_point(), 1.6, Color(1.0, 0.35, 0.1), 0.08)
	FxKit.spark(o.get_parent(), o.aim_point(), Vector3.UP)


func finish() -> void:
	if _ending:
		return
	_ending = true


func _exit_tree() -> void:
	if not _ending or _end_t < FADE_OUT: # freed early (the match ended): the world gets its light back
		_ending = true
		_end_t = FADE_OUT
		_restore()
