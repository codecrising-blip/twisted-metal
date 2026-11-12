class_name LaOutside
extends Node3D
## BAKE ONLY (owner, round 5: "anything outside the walls must not cost frames, a photo is enough").
## The hills north of the arena with the HOLLYWOOD sign and scrub, and Calypso's blimp. Rendered by
## tests/bake_backdrop.gd into the Los Angeles backdrop panorama together with LaCity; never built
## in the game. (The shoot-the-letters easter egg went with it.)

var _rng := RandomNumberGenerator.new()
var _shrub: ArrayMesh


func build() -> void:
	_rng.seed = 1996
	_hollywood_sign()
	_blimp()


## One shrub (a few lumps of dark and olive green), shared by every bush on the stage.
func _bush_mesh() -> ArrayMesh:
	if _shrub:
		return _shrub
	var mb := MeshBuilder.new()
	var green := MatKit.paint(Color(0.2, 0.28, 0.14), 0.1, 0.0, 0.5, 1.0, 0.9, 170)
	var olive := MatKit.paint(Color(0.32, 0.34, 0.18), 0.1, 0.0, 0.5, 1.0, 0.9, 171)
	for k in 5:
		var a := TAU * k / 5.0
		mb.sphere(green if k % 2 == 0 else olive, 0.7, MeshBuilder.at(Vector3(cos(a) * 0.55, 0.45, sin(a) * 0.55), Vector3.ZERO, Vector3(1.0, 0.75, 1.0)), 8, 5)
	mb.sphere(green, 0.75, MeshBuilder.at(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0)), 8, 5)
	_shrub = mb.build_mesh(0.4, 0.0, true)
	return _shrub


## Many copies of one mesh in a single draw (per material): bushes, scrub.
func _scatter(mesh: Mesh, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Letter strokes (center lines) on a 4 x 6.5 grid; the HOLLYWOOD sign's tall, bold sans letters.
const GLYPHS := {
	"H": [[Vector2(0, 0), Vector2(0, 6.5)], [Vector2(4, 0), Vector2(4, 6.5)], [Vector2(0, 3.3), Vector2(4, 3.3)]],
	"L": [[Vector2(0, 6.5), Vector2(0, 0), Vector2(3.8, 0)]],
	"Y": [[Vector2(0, 6.5), Vector2(2, 3.1), Vector2(4, 6.5)], [Vector2(2, 3.1), Vector2(2, 0)]],
	"W": [[Vector2(0, 6.5), Vector2(0.9, 0), Vector2(2, 4.3), Vector2(3.1, 0), Vector2(4, 6.5)]],
	"D": [[Vector2(0, 0), Vector2(0, 6.5), Vector2(1.8, 6.5), Vector2(3.2, 5.8), Vector2(4, 4.4),
		Vector2(4, 2.1), Vector2(3.2, 0.7), Vector2(1.8, 0), Vector2(0, 0)]],
}


func _glyph_strokes(ch: String) -> Array:
	if ch == "O": # a tall rounded oval
		var ring: Array[Vector2] = []
		for k in 21:
			var a := TAU * k / 20.0
			var c := cos(a)
			var sn := sin(a)
			ring.append(Vector2(2.0 + 2.0 * signf(c) * pow(absf(c), 0.75), 3.25 + 3.25 * signf(sn) * pow(absf(sn), 0.75)))
		return [ring]
	return GLYPHS[ch]


func _hollywood_sign() -> void:
	# Hills: a height grid, scrub texture, and 3D scrub clumps scattered on the slopes.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -320.0
	var x1 := 300.0
	var z0 := -380.0
	var z1 := -163.0
	var nx := 84
	var nz := 32
	var grid: Array[Vector3] = []
	for j in nz + 1:
		for i in nx + 1:
			var x := lerpf(x0, x1, float(i) / nx)
			var z := lerpf(z0, z1, float(j) / nz)
			grid.append(Vector3(x, LosAngelesArena.hill_height(x, z), z))
	for j in nz:
		for i in nx:
			var a := grid[j * (nx + 1) + i]
			var b := grid[j * (nx + 1) + i + 1]
			var c := grid[(j + 1) * (nx + 1) + i]
			var d := grid[(j + 1) * (nx + 1) + i + 1]
			for v: Vector3 in [a, b, c, b, d, c]:
				st.set_uv(Vector2(v.x, v.z)) # chaparral reads UVs in meters
				st.add_vertex(v)
	st.generate_normals()
	var hill := MeshInstance3D.new()
	hill.mesh = st.commit()
	hill.material_override = MatKit.chaparral(36.0, 21)
	hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hill)
	var scrub: Array[Transform3D] = []
	var sign_x0 := -10.0 - 4.5 * 9.0
	var sign_x1 := -10.0 + 4.5 * 9.0
	while scrub.size() < 700: # baked into the image: as much scrub as looks right
		var x := _rng.randf_range(-260.0, 240.0)
		var z := _rng.randf_range(-330.0, -172.0)
		if x > sign_x0 and x < sign_x1 and absf(z - LosAngelesArena.SIGN_Z) < 9.0:
			continue # keep the letters clear
		var y := LosAngelesArena.hill_height(x, z)
		if y < -12.0:
			continue
		var sc := _rng.randf_range(2.2, 4.5)
		scrub.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * 0.7, sc)), Vector3(x, y - 0.4, z)))
	add_child(_scatter(_bush_mesh(), scrub))
	# The letters: bold strokes, weathered white paint, two steel legs behind each.
	var word := "HOLLYWOOD"
	var u := 1.3
	var t := 0.95 * u
	var paint := MatKit.paint(Color(0.88, 0.87, 0.83), 0.25, 0.15, 0.45, 3.0, 0.4, 150)
	var posts := MeshBuilder.new()
	var steel := MatKit.steel(Color(0.2, 0.2, 0.21), 0.6, 1.0)
	for i in word.length():
		var x := sign_x0 + 4.5 + i * 9.0
		var base := Vector3(x, LosAngelesArena.hill_height(x, LosAngelesArena.SIGN_Z) + 0.8, LosAngelesArena.SIGN_Z)
		var letter := Node3D.new()
		letter.position = base
		letter.rotation_degrees.x = -10.0
		add_child(letter)
		var lmb := MeshBuilder.new()
		for stroke: Array in _glyph_strokes(word[i]):
			for k in stroke.size() - 1:
				var a: Vector2 = stroke[k]
				var b: Vector2 = stroke[k + 1]
				var pa := Vector3((a.x - 2.0) * u, (a.y + 0.5) * u, 0)
				var pb := Vector3((b.x - 2.0) * u, (b.y + 0.5) * u, 0)
				var dir := (pb - pa).normalized()
				var across := Vector3(-dir.y, dir.x, 0)
				var length := pa.distance_to(pb) + t # overlap at the joints
				lmb.box(paint, Vector3(t, 0.5, length), Transform3D(Basis(across, Vector3.BACK, dir), (pa + pb) * 0.5), 0.0)
		lmb.commit(letter, true, 0.4)
		for px: float in [-1.8, 1.8]:
			posts.box(steel, Vector3(0.18, 7.0, 0.18), MeshBuilder.at(base + Vector3(px, 2.0, -1.6), Vector3(-20, 0, 0)), 0.0)
	posts.commit(self)


## Calypso's blimp, far away in stage 1 (it gets closer every stage).
func _blimp() -> void:
	var blimp := Node3D.new()
	blimp.name = "CalypsoBlimp"
	blimp.position = Vector3(620, 330, -1050)
	blimp.rotation_degrees.y = 25.0
	blimp.scale = Vector3.ONE * 1.7
	add_child(blimp)
	var skin := MeshKit.mat(Color(0.18, 0.17, 0.2), 0.5, 0.3)
	var gold := MeshKit.mat(Color(0.85, 0.65, 0.2), 0.3, 1.0)
	MeshKit.sphere(blimp, 14.0, Vector3.ZERO, skin, Vector3(4.2, 1.0, 1.0), 20)
	MeshKit.torus(blimp, 13.8, 14.4, Vector3(-18, 0, 0), gold, Vector3(0, 0, 90))
	MeshKit.torus(blimp, 13.0, 13.6, Vector3(22, 0, 0), gold, Vector3(0, 0, 90))
	for k in 4:
		var fin := Node3D.new()
		fin.position = Vector3(50, 0, 0)
		fin.rotation.x = k * PI * 0.5
		blimp.add_child(fin)
		MeshKit.box(fin, Vector3(14, 0.8, 12), Vector3(0, 0, 9), skin)
	MeshKit.box(blimp, Vector3(22, 5, 7), Vector3(0, -15, 0), gold)
	for side: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "CALYPSO"
		l.font_size = 400
		l.pixel_size = 0.035
		l.modulate = Color(1.3, 1.0, 0.4)
		l.outline_size = 0
		l.position = Vector3(0, 2, side * 14.3)
		l.rotation_degrees.y = 0.0 if side > 0 else 180.0
		blimp.add_child(l)
	var blinker := Blinker.new()
	blinker.period = 0.9
	blimp.add_child(blinker)
	for x: float in [-55.0, 55.0]:
		var lamp := MeshKit.sphere(blimp, 0.8, Vector3(x, 0, 0), MeshKit.emissive(Color(1, 0.1, 0.05), 8.0))
		blinker.group_a.append(lamp)
	var tw := blimp.create_tween().set_loops()
	tw.tween_property(blimp, "position:y", 338.0, 8.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(blimp, "position:y", 330.0, 8.0).set_trans(Tween.TRANS_SINE)
