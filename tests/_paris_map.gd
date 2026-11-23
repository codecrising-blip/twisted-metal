extends SceneTree
## Dumps Paris's street plan (roads, blocks, ramps) as JSON for a quick top-down drawing.
## godot --headless --path . -s tests/_paris_map.gd -- out.json

func _initialize() -> void:
	var a := ParisArena.new()
	root.add_child(a)
	a.build()
	var out := {"roads": [], "blocks": [], "ramps": [], "health": [], "mega": [], "weapons": [], "turbo": []}
	for k: String in ["health", "mega", "weapons", "turbo"]:
		var src: Array = {"health": a.health_points, "mega": a.mega_points, "weapons": a.weapon_points, "turbo": a.turbo_points}[k]
		for p: Vector3 in src:
			out[k].append([p.x, p.y, p.z])
	for r: Dictionary in a.roads:
		out.roads.append({"pts": Array(r.pts).map(func(v): return [v.x, v.y]), "w": r.w})
	for b: Dictionary in a.blocks:
		out.blocks.append({"poly": Array(b.poly).map(func(v): return [v.x, v.y]), "roof": b.roof})
	for r: Dictionary in a.ramps:
		out.ramps.append([r.foot.x, r.foot.z, r.top.x, r.top.z])
	var path := OS.get_cmdline_user_args()[0]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("blocks ", a.blocks.size(), " roads ", a.roads.size())
	quit()
