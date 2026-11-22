class_name BlenderCars
## Cars modelled in Blender (round 10: "serious, not cartoonish"). Puts the nodes of
## assets/models/<id>.glb together into the model the game expects, with the same metadata as the
## old GDScript models (wheels, steer, guns, gun_spinners, launcher, exhaust, top).
## The .glb holds: body, wheel_f, wheel_r (axle along X, outer face at +X), spinner (optional), and
## markers m_wheel_fr/fl/rr/rl, m_gun_*, m_spin_*, m_launcher, m_exh_*, m_top, m_head, m_cone.
## Built by tools/blender/build_<id>.py.

const EXHAUST_DIR := {"sweet_tooth": Vector3.UP}
const SHADOW := {"sweet_tooth": Vector2(3.2, 7.4), "outlaw": Vector2(2.7, 5.6), "mr_grimm": Vector2(2.4, 3.6),
	"thumper": Vector2(2.8, 6.6), "brimstone": Vector2(2.7, 6.0), "darkside": Vector2(3.6, 8.6)}
## How far the body rolls in turns (radians). Grimm's bike has a sidecar bolted on: it barely leans.
const LEAN := {"mr_grimm": 0.08, "darkside": 0.03}
## Turbo flames for models with no exhaust markers (round 21, owner: Axel had no turbo flames): out of
## Axel's back feet, low, under the tail lights.
const EXTRA_EXHAUST := {"axel": [Vector3(0.55, 0.3, 1.08), Vector3(-0.55, 0.3, 1.08)]}


static func has(id: String) -> bool:
	return ModelLib.has(id)


static func build(id: String) -> Node3D:
	var marks := ModelLib.marks(id)
	var m := Node3D.new()
	m.name = "Model"
	m.add_child(ModelLib.instance(id, "body"))
	if marks.has("door") and marks.has("m_door_hinge"): # round 19: Sweet Tooth's tailgate folds down (Sweet Bot)
		var hinge := Node3D.new()
		hinge.name = "DoorHinge"
		hinge.position = (marks["m_door_hinge"] as Transform3D).origin
		hinge.add_child(ModelLib.instance(id, "door"))
		m.add_child(hinge)
		m.set_meta("door", hinge)
	var wheels: Array = []
	var steer: Array = []
	var radius := 0.5
	for key: String in ["fr", "fl", "rr", "rl", "rr2", "rl2"]: # rr2 / rl2: a second rear axle (Darkside)
		var mk := "m_wheel_" + key
		if not marks.has(mk):
			continue
		var pos: Vector3 = (marks[mk] as Transform3D).origin
		radius = pos.y
		var pivot := Node3D.new()
		pivot.position = pos
		m.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var mi := ModelLib.instance(id, "wheel_f" if key.begins_with("f") else "wheel_r")
		if pos.x < 0.0:
			mi.rotation.y = PI # the same wheel, outer face to the left
		spin.add_child(mi)
		wheels.append(spin)
		if key.begins_with("f"):
			steer.append(pivot)
	m.set_meta("wheels", wheels)
	m.set_meta("steer", steer)
	m.set_meta("wheel_radius", radius)
	var guns: Array = []
	var spinners: Array = []
	var exhaust: Array = []
	var names: Array = marks.keys()
	names.sort()
	for mk: String in names:
		var at: Vector3 = (marks[mk] as Transform3D).origin
		if mk.begins_with("m_gun"):
			guns.append(at)
		elif mk.begins_with("m_exh"):
			exhaust.append(at)
		elif mk.begins_with("m_spin"):
			var s := Node3D.new()
			s.position = at
			m.add_child(s)
			s.add_child(ModelLib.instance(id, "spinner"))
			spinners.append(s)
	m.set_meta("guns", guns)
	if not spinners.is_empty():
		m.set_meta("gun_spinners", spinners)
	if exhaust.is_empty() and EXTRA_EXHAUST.has(id):
		exhaust.assign(EXTRA_EXHAUST[id])
	m.set_meta("exhaust", exhaust)
	m.set_meta("exhaust_dir", EXHAUST_DIR.get(id, Vector3.BACK))
	if marks.has("m_launcher"):
		m.set_meta("launcher", (marks["m_launcher"] as Transform3D).origin)
	if marks.has("m_slot_0"): # round 24: Roadkill's six charge slots on his nose strip
		var slots: Array = []
		for k in 8:
			if marks.has("m_slot_%d" % k):
				slots.append((marks["m_slot_%d" % k] as Transform3D).origin)
		m.set_meta("slots", slots)
	if marks.has("m_top"):
		m.set_meta("top", (marks["m_top"] as Transform3D).origin)
	if marks.has("m_head"):
		HeroModels._headlight_beam(m, (marks["m_head"] as Transform3D).origin)
	var cone_parent: Node3D = m
	var cone_at := Vector3.ZERO
	if marks.has("mascot") and marks.has("m_mascot"): # round 19: Sweet Tooth's head on its roof spring (bobs)
		var spring := Node3D.new()
		spring.name = "Mascot"
		spring.position = (marks["m_mascot"] as Transform3D).origin
		spring.add_child(ModelLib.instance(id, "mascot"))
		m.add_child(spring)
		m.set_meta("bobble", spring)
		cone_parent = spring
		cone_at = -spring.position
	if marks.has("m_cone"):
		_cone_fire(m, (marks["m_cone"] as Transform3D).origin + cone_at, cone_parent)
	if LEAN.has(id):
		m.set_meta("lean", LEAN[id])
	# Round 28: markers named m_meta_<name> become model metadata (Thumper's nozzle, Brimstone's sinner and bell),
	# and the parts the specials move get their own nodes: Thumper's gunmen (hidden until the Drive-By, turning at
	# the shoulder marker m_gunman_*), the sinner chained in Brimstone's bed, Darkside's red slit.
	for mk: String in names:
		if mk.begins_with("m_meta_"):
			m.set_meta(mk.substr(7), (marks[mk] as Transform3D).origin)
	for part: String in ["gunman_l", "gunman_r"]:
		if marks.has(part) and marks.has("m_" + part):
			var pivot := Node3D.new()
			pivot.name = part
			pivot.position = (marks["m_" + part] as Transform3D).origin
			var mi := ModelLib.instance(id, part)
			mi.name = "mesh"
			mi.position = -pivot.position
			pivot.add_child(mi)
			pivot.visible = false
			m.add_child(pivot)
	for part: String in ["bed_sinner", "slit"]:
		if marks.has(part):
			m.add_child(ModelLib.instance(id, part))
	HeroModels._ground_shadow(m, SHADOW.get(id, Vector2(2.8, 5.8)))
	return m


## Sweet Tooth's head burns on the roof (its sculpted flames catch a real fire, round 19): a low flame on
## the crown that rides the spring with the head. `parent` = the model, or the head's spring.
static func _cone_fire(m: Node3D, at: Vector3, parent: Node3D = null) -> void:
	var fire := FxKit.fire(0.3, 10)
	fire.position = at
	fire.emission_sphere_radius = 0.13
	fire.color_ramp = FxKit._ramp(CONE_FIRE)
	(parent if parent else m).add_child(fire)
	fire.emitting = true
	m.set_meta("cone_fire", fire)
	var glow := FlickerLight.new()
	glow.light_color = Color(1.0, 0.45, 0.12)
	glow.base_energy = 0.8
	glow.omni_range = 4.0
	glow.position = at + Vector3(0, 0.3, 0)
	glow.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	glow.visible = GraphicsSettings.high
	(parent if parent else m).add_child(glow)
	m.set_meta("cone_glow", glow)


const CONE_FIRE := [Color(0.9, 0.45, 0.12, 0.5), Color(0.8, 0.22, 0.04, 0.38), Color(0.3, 0.07, 0.02, 0.2), Color(0.08, 0.05, 0.05, 0.0)]
## Last Laugh (Sweet Tooth under 30% health): the roof fire burns blue, a warning everyone can see.
const CONE_FIRE_BLUE := [Color(0.55, 0.8, 1.0, 0.55), Color(0.15, 0.4, 1.0, 0.42), Color(0.05, 0.1, 0.4, 0.2), Color(0.04, 0.05, 0.08, 0.0)]

static func cone_fire_blue(m: Node3D, blue: bool) -> void:
	if m == null or not m.has_meta("cone_fire"):
		return
	var fire: CPUParticles3D = m.get_meta("cone_fire")
	fire.color_ramp = FxKit._ramp(CONE_FIRE_BLUE if blue else CONE_FIRE)
	fire.amount = 16 if blue else 10
	var glow: Light3D = m.get_meta("cone_glow")
	glow.light_color = Color(0.3, 0.55, 1.0) if blue else Color(1.0, 0.45, 0.12)
