class_name Mine
extends Node3D
## Remote (owner, play-test 2): a mine dropped behind the car. The next fire press blows it; after
## a short arming time any car that drives onto it sets it off, the one that dropped it included.
## The blast pushes hard: a car right on top flies and flips, cars at the side get thrown away.

var owner_car: Vehicle
var def := {}

var _t := 0.0
var _done := false
var _lamp: MeshInstance3D
var _armed_told := false


static func drop(v: Vehicle, d: Dictionary) -> Mine:
	var m := Mine.new()
	m.owner_car = v
	m.def = d
	v.get_parent().add_child(m)
	var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.0))
	var back := v.global_position - v.flat_forward() * (size.z * 0.5 + 1.6) + Vector3.UP
	m.global_position = Specials.ground_below(v.get_parent(), back)
	GameFeel.play("mine_drop", m.global_position, v.get_parent())
	v.set_live_special(m, "remote")
	if v.is_player:
		v.notice.emit(v, "REMOTE DROPPED - FIRE TO BLOW")
	return m


var _leds: Array[MeshInstance3D] = []
var _sense: MeshInstance3D
var _sense_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"mines")
	if def.get("electronic", false):
		_build_electronic()
		return
	# The energy-move mine (owner, round 9: stays as it is).
	var dark := MeshKit.mat(Color(0.09, 0.09, 0.1), 0.6, 0.5)
	var steel := MeshKit.mat(Color(0.3, 0.3, 0.31), 0.45, 0.7)
	MeshKit.cylinder(self, 0.6, 0.2, Vector3(0, 0.1, 0), dark, Vector3.ZERO, 14)
	MeshKit.cylinder(self, 0.4, 0.1, Vector3(0, 0.24, 0), steel, Vector3.ZERO, 12)
	for k in 6:
		var a := TAU * k / 6.0
		MeshKit.cylinder(self, 0.05, 0.22, Vector3(cos(a) * 0.48, 0.28, sin(a) * 0.48), steel, Vector3.ZERO, 4, 0.0)
	MeshKit.cylinder(self, 0.02, 0.45, Vector3(0.15, 0.5, 0), steel, Vector3.ZERO, 4)
	_lamp = MeshKit.sphere(self, 0.08, Vector3(0, 0.33, 0), MeshKit.emissive(Color(1.0, 0.1, 0.05), 6.0), Vector3.ONE, 6)
	for mi in find_children("*", "MeshInstance3D", false, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Remote (owner, round 9: "an electronic mine"): a squat armoured puck with a circuit board on top,
## chips, a ring of LEDs that chase round (slow amber while arming, fast red when live), a whip antenna
## with a blinking tip, and once armed a faint red ring on the ground showing where it triggers.
func _build_electronic() -> void:
	var body := MeshKit.mat(Color(0.07, 0.075, 0.08), 0.55, 0.6)
	var steel := MeshKit.mat(Color(0.32, 0.32, 0.33), 0.4, 0.75)
	var board := MeshKit.mat(Color(0.04, 0.26, 0.1), 0.6, 0.1)
	var chip := MeshKit.mat(Color(0.02, 0.02, 0.02), 0.4, 0.2)
	var copper := MeshKit.mat(Color(0.75, 0.45, 0.2), 0.35, 0.9)
	MeshKit.cylinder(self, 0.62, 0.22, Vector3(0, 0.11, 0), body, Vector3.ZERO, 8) # armoured octagon
	MeshKit.cylinder(self, 0.66, 0.06, Vector3(0, 0.03, 0), steel, Vector3.ZERO, 8) # skid plate
	MeshKit.cylinder(self, 0.47, 0.04, Vector3(0, 0.24, 0), board, Vector3.ZERO, 16) # circuit board
	MeshKit.box(self, Vector3(0.22, 0.05, 0.16), Vector3(-0.1, 0.28, 0.05), chip)
	MeshKit.box(self, Vector3(0.1, 0.05, 0.1), Vector3(0.18, 0.28, -0.12), chip)
	MeshKit.box(self, Vector3(0.3, 0.012, 0.03), Vector3(0.05, 0.265, -0.2), copper)
	MeshKit.box(self, Vector3(0.03, 0.012, 0.28), Vector3(0.25, 0.265, 0.1), copper)
	MeshKit.cylinder(self, 0.07, 0.12, Vector3(-0.2, 0.32, -0.15), steel, Vector3.ZERO, 8) # detonator cap
	MeshKit.cylinder(self, 0.012, 0.7, Vector3(0.3, 0.6, 0.2), steel, Vector3.ZERO, 4) # whip antenna
	_lamp = MeshKit.sphere(self, 0.045, Vector3(0.3, 0.96, 0.2), MeshKit.emissive(Color(1.0, 0.1, 0.05), 8.0), Vector3.ONE, 6)
	var led := MeshKit.emissive(Color(1.0, 0.08, 0.03), 2.2)
	for k in 8:
		var a := TAU * k / 8.0
		_leds.append(MeshKit.sphere(self, 0.045, Vector3(cos(a) * 0.55, 0.2, sin(a) * 0.55), led, Vector3.ONE, 6))
	_sense_mat = StandardMaterial3D.new()
	_sense_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sense_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sense_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sense_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.0)
	var r: float = def.get("trigger", 2.4)
	_sense = MeshKit.torus(self, r - 0.08, r, Vector3.UP * 0.08, _sense_mat)
	_sense.scale = Vector3(1.0, 0.3, 1.0)
	_sense.visible = false
	for mi in find_children("*", "MeshInstance3D", false, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _animate_electronic() -> void:
	var live := armed()
	var lit := int(_t * (14.0 if live else 5.0)) % 8 # one LED chasing round, plus its trail
	for k in _leds.size():
		_leds[k].visible = k == lit or (live and k == (lit + 7) % 8)
	if live:
		_sense.visible = true
		_sense_mat.albedo_color.a = 0.18 + 0.14 * sin(_t * 9.0)


## The owner's next fire press.
## Energy move "mines" (design 5.2): a small mine behind the car, no remote; up to 3 per car (a 4th sets
## the oldest off).
static func drop_energy(v: Vehicle) -> Mine:
	var m := Mine.new()
	m.owner_car = v
	m.def = WeaponData.get_def("energy_mine")
	v.get_parent().add_child(m)
	var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.0))
	var back := v.global_position - v.flat_forward() * (size.z * 0.5 + 1.6) + Vector3.UP
	m.global_position = Specials.ground_below(v.get_parent(), back)
	m.scale = Vector3.ONE * 0.75
	GameFeel.play("mine_drop", m.global_position, v.get_parent())
	v._energy_mines = v._energy_mines.filter(func(o: Variant) -> bool: return is_instance_valid(o) and not (o as Mine)._done)
	v._energy_mines.append(m)
	if v._energy_mines.size() > 3:
		(v._energy_mines.pop_front() as Mine).detonate()
	return m


func fire_again() -> void:
	detonate()


## Blowing your own Remote right after dropping it (owner, round 7: "it should hurt me, send me flying
## to the front and mess up my control"). The car has already driven past the blast radius by the
## time the button is pressed (it drops ~5 m behind, the car moves ~10 m a second-third), so within
## this window the owner's tail is still in the blast, whatever the distance.
const OWN_BLAST_TIME := 1.0
const OWN_BLAST_REACH := 30.0


func _own_blast(o: Vehicle, rel: Vector3) -> void:
	var hit := lerpf(float(def.get("damage", 50.0)), float(def.get("edge_damage", 20.0)), 0.4) * WeaponData.DAMAGE_SCALE
	o.take_damage(hit, owner_car)
	o.hit_react(rel, hit)
	var forward := Vector3(rel.x, 0.0, rel.z)
	forward = forward.normalized() if forward.length() > 0.3 else o.flat_forward()
	var heights: Dictionary = def.get("launch", {})
	var h := float(heights.get(o.stats.get("class", "medium"), 8.4)) * 0.45
	# Kicked forward and the tail up (it noses over a little), the tyres lose grip for a moment and
	# the car slews off line.
	o.blast_knock(forward * float(def.get("push", 24.0)) * 0.7 * (h / 3.8) + Vector3.UP * sqrt(2.0 * Vehicle.GRAVITY * h), 0.0, false)
	o.angular_velocity += o.global_basis.x * -1.0 + Vector3.UP * randf_range(-1.8, 1.8)
	o.wobble(0.8)


func armed() -> bool:
	return _t >= float(def.get("arm", 0.8))


func _physics_process(delta: float) -> void:
	_t += delta
	_lamp.visible = fmod(_t * (4.0 if armed() else 1.5), 1.0) < 0.5
	if not _leds.is_empty():
		_animate_electronic()
	if _t >= float(def.get("life", 90.0)):
		detonate()
		return
	if not armed():
		return
	if not _armed_told: # tell beat: a blip and a flash of the lamp the moment it goes live
		_armed_told = true
		GameFeel.play("mine_arm", global_position + Vector3.UP * 0.4, get_parent(), -8.0)
		GameFeel.flash(get_parent(), global_position + Vector3.UP * 0.35, 0.5, Color(1.0, 0.2, 0.1), 0.1)
	var reach: float = def.get("trigger", 2.4)
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o.is_dead:
			continue
		var rel := o.global_position - global_position
		if Vector2(rel.x, rel.z).length() < reach and absf(rel.y) < 2.5:
			detonate()
			return


## Wiped out without a blast (Axel's Crowd Controller): a pop of sparks and it is gone.
func fizzle() -> void:
	if _done:
		return
	_done = true
	FxKit.spark(get_parent(), global_position + Vector3.UP * 0.3, Vector3.UP)
	FxKit.puff(get_parent(), global_position + Vector3.UP * 0.2, 0.35)
	GameFeel.play("taser_fizzle", global_position, get_parent(), -8.0)
	if is_instance_valid(owner_car) and owner_car.live_special() == self:
		owner_car.set_live_special(null)
	queue_free()


func detonate() -> void:
	if _done:
		return
	_done = true
	var world := get_parent()
	var radius: float = def.get("radius", 8.0)
	var core: float = def.get("core", 3.5)
	var full := float(def.get("damage", 50.0))
	var edge := float(def.get("edge_damage", 20.0))
	for node in world.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o.is_dead:
			continue
		var rel := o.global_position - global_position
		var flat := Vector2(rel.x, rel.z).length()
		if o == owner_car and _t < OWN_BLAST_TIME and flat > radius and flat <= OWN_BLAST_REACH and absf(rel.y) < 6.0 and def.has("launch"):
			_own_blast(o, rel)
			continue
		if flat > radius or absf(rel.y) > 4.0:
			continue
		var hit := lerpf(full, edge, clampf((flat - core) / (radius - core), 0.0, 1.0)) * WeaponData.DAMAGE_SCALE
		o.take_damage(hit, owner_car)
		o.hit_react(rel, hit)
		var away := Vector3(rel.x, 0.0, rel.z)
		away = away.normalized() if away.length() > 0.3 else o.flat_forward()
		var heights: Dictionary = def.get("launch", {})
		var h := float(heights.get(o.stats.get("class", "medium"), 8.4))
		if def.has("burn") and flat < core: # a clean hit sets the car on fire (owner, round 9)
			o.ignite(float(def["burn"]), owner_car)
		if flat < 2.8: # right on top: thrown up a bit higher than its class height (owner, round 6), rolling
			# Sometimes once round and back on its wheels, sometimes onto its roof.
			o.blast_knock(Vector3.UP * sqrt(2.0 * Vehicle.GRAVITY * h * 1.25) + away * 3.0, 0.5 if randf() < 0.45 else 1.0, false)
		else:
			# Side hits (owner, round 6): thrown sideways away from the blast, the near side lifted, so
			# it rolls away from it; the closer, the higher and the further. Light cars fly furthest.
			var k := 1.0 - clampf((flat - 2.8) / (radius - 2.8), 0.0, 1.0)
			var up := sqrt(2.0 * Vehicle.GRAVITY * h * (0.25 + 0.5 * k) * k)
			var side := away * float(def.get("push", 24.0)) * (0.35 + 0.65 * k) * (h / 8.4)
			o.blast_knock(side + Vector3.UP * up, 0.15 + 0.35 * k, false)
	Specials.blast_props(world, global_position, radius, full, owner_car)
	FxKit.explosion(world, global_position + Vector3.UP * 0.5, float(def.get("blast_size", 2.8)), Color(1.0, 0.45, 0.12))
	if def.get("electronic", false): # the electronics go up: a blue-white spark burst and a ring of fire
		GameFeel.flash(world, global_position + Vector3.UP * 0.6, 2.5, Color(0.6, 0.8, 1.0), 0.08)
		for k in 5:
			var a := TAU * k / 5.0 + randf() * 0.6
			FxKit.spark(world, global_position + Vector3(cos(a), 0.4, sin(a)) * 0.8, Vector3(cos(a), 1.2, sin(a)).normalized())
		GameFeel.shockwave(world, global_position, radius * 1.2, Color(1.0, 0.5, 0.15))
		GameFeel.scorch(world, global_position + Vector3.UP * 0.3, 2.8)
	var player_in := is_instance_valid(owner_car) and owner_car.is_player and global_position.distance_to(owner_car.global_position) < 40.0
	for node in world.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o.is_player and o.global_position.distance_to(global_position) < radius:
			player_in = true
	if player_in: # impact beat: a blink of hit-stop when you are in it or set it off nearby
		GameFeel.hitstop(world.get_tree(), 0.07, 0.05)
	if is_instance_valid(owner_car) and owner_car.live_special() == self:
		owner_car.set_live_special(null)
	queue_free()
