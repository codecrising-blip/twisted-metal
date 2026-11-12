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


func _ready() -> void:
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


func armed() -> bool:
	return _t >= float(def.get("arm", 0.8))


func _physics_process(delta: float) -> void:
	_t += delta
	_lamp.visible = fmod(_t * (4.0 if armed() else 1.5), 1.0) < 0.5
	if _t >= float(def.get("life", 90.0)):
		detonate()
		return
	if not armed():
		return
	var reach: float = def.get("trigger", 2.4)
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o.is_dead:
			continue
		var rel := o.global_position - global_position
		if Vector2(rel.x, rel.z).length() < reach and absf(rel.y) < 2.5:
			detonate()
			return


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
		if flat > radius or absf(rel.y) > 4.0:
			continue
		var hit := lerpf(full, edge, clampf((flat - core) / (radius - core), 0.0, 1.0)) * WeaponData.DAMAGE_SCALE
		o.take_damage(hit, owner_car)
		o.hit_react(rel, hit)
		var away := Vector3(rel.x, 0.0, rel.z)
		away = away.normalized() if away.length() > 0.3 else o.flat_forward()
		var heights: Dictionary = def.get("launch", {})
		var h := float(heights.get(o.stats.get("class", "medium"), 8.4))
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
	FxKit.explosion(world, global_position + Vector3.UP * 0.5, float(def.get("blast_size", 2.8)), Color(1.0, 0.45, 0.12))
	if is_instance_valid(owner_car) and owner_car.live_special() == self:
		owner_car.set_live_special(null)
	queue_free()
