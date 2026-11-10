extends SceneTree
## Bakes the Los Angeles backdrop: renders the 3D city (LaCity), sky, haze and mountains from the
## middle of the arena into the six faces of a cube, for tests/cube_to_panorama.py to turn into one
## equirectangular image (assets/backdrops/los_angeles_city.jpg). Needs a display (xvfb-run):
##   godot --rendering-method gl_compatibility --path . -s tests/bake_backdrop.gd -- <out_dir> [face_px]
## The stage then shows that image as its sky: the city costs nothing at run time.

const EYE := Vector3(0, 8, 0) # about a chase camera's height on the raised battleground

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://backdrop"
	var face_px := int(args[1]) if args.size() > 1 else 2048
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = LosAngelesArena.sky_material()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.56, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.55, 0.56)
	env.fog_density = 0.00075
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85 # the stage tonemaps the image again: keep the bake soft
	env.adjustment_contrast = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.76, 0.54)
	sun.light_energy = 1.3
	sun.rotation_degrees = LosAngelesArena.SUN_ROTATION
	world.add_child(sun)
	var city := LaCity.new()
	world.add_child(city)
	city.build()

	var vp := SubViewport.new()
	vp.size = Vector2i(face_px, face_px)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.5
	cam.far = 6000.0
	vp.add_child(cam)
	cam.current = true
	# Let the smoke plumes grow before taking the pictures.
	for i in 240:
		await process_frame
	# Face name -> forward, up. Right = forward x up.
	var faces := {
		"px": [Vector3(1, 0, 0), Vector3(0, 1, 0)], "nx": [Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		"pz": [Vector3(0, 0, 1), Vector3(0, 1, 0)], "nz": [Vector3(0, 0, -1), Vector3(0, 1, 0)],
		"py": [Vector3(0, 1, 0), Vector3(0, 0, 1)], "ny": [Vector3(0, -1, 0), Vector3(0, 0, -1)],
	}
	var info := {}
	for name: String in faces:
		var f: Vector3 = faces[name][0]
		var u: Vector3 = faces[name][1]
		cam.global_transform = Transform3D(Basis.looking_at(f, u), EYE)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(out_dir.path_join(name + ".png"))
		var b := cam.global_basis
		info[name] = {"right": [b.x.x, b.x.y, b.x.z], "up": [b.y.x, b.y.y, b.y.z], "forward": [-b.z.x, -b.z.y, -b.z.z]}
		print("face ", name)
	var fa := FileAccess.open(out_dir.path_join("faces.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(info))
	fa.close()
	print("baked to ", out_dir)
	quit()
