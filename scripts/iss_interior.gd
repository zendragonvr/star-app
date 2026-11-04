# ISS interior. vc153 first version, vc180 rework (user 2026-11-04: "do your
# research how it really looks inside and mimic it").
#
# You float inside DESTINY, the US laboratory: 8.5 m long, 4.3 m outside
# diameter, 24 racks. Inside, the racks make a SQUARE aisle about 2 m across,
# with four named surfaces (deck, overhead, port, starboard) of 6 racks each.
# Rack faces are off-white with grey and blue panels, laptops on arms, white
# cargo bags strapped on, cables everywhere, grey handrails. Lights are LED
# panels in the four corner standoffs. In the deck is Destiny's real Earth
# window (about 51 cm). Both ends have open square hatches: aft to Unity
# (Node 1), forward to Harmony (Node 2). Real layout, simplified detail;
# the exact equipment on each rack is NOT the real current rack list.
#
# All geometry is merged into a few meshes (1 draw call for the module),
# unshaded with baked light/dark per surface, so it holds 72 fps on Quest.
# Placed ONCE when you enter (main.gd), not every frame, so it does not
# move with your head. Any pinch exits, as before.
extends Node3D
class_name IssInterior

const L: float = 8.5     # Destiny length
const H: float = 1.0     # half of the 2 m square aisle
const RACK_W: float = 1.06
const EARTH_TEX: String = "res://data/textures/2k_earth.jpg"

var _floaters: Array = []
var _earth: MeshInstance3D = null
var _rng := RandomNumberGenerator.new()

# Light per surface (baked, unshaded): overhead brightest, deck darkest.
const SHADE := {"ovhd": 1.0, "port": 0.9, "stbd": 0.9, "deck": 0.78, "end": 0.85}

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)

func _box(st: SurfaceTool, size: Vector3, xf: Transform3D, col: Color) -> void:
	var h: Vector3 = size * 0.5
	var faces: Array = [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var c: Vector3 = n * h
		var hu: Vector3 = (f[1] as Vector3) * h
		var hv: Vector3 = (f[2] as Vector3) * h
		var wn: Vector3 = xf.basis * n
		var lit: float = 0.82 + 0.18 * clamp(wn.normalized().y * 0.5 + 0.5, 0.0, 1.0)
		var cc := Color(col.r * lit, col.g * lit, col.b * lit, col.a)
		_quad(st, xf * (c - hu - hv), xf * (c + hu - hv), xf * (c + hu + hv), xf * (c - hu + hv), cc)

# Surface frame: each of the 4 rack walls as (origin, right, up-into-room, normal).
# Racks run along X (module axis). "in" points from the wall into the aisle.
func _walls() -> Array:
	return [
		{"name": "deck", "o": Vector3(0, -H, 0), "in": Vector3(0, 1, 0), "side": Vector3(0, 0, 1)},
		{"name": "ovhd", "o": Vector3(0, H, 0), "in": Vector3(0, -1, 0), "side": Vector3(0, 0, -1)},
		{"name": "port", "o": Vector3(0, 0, -H), "in": Vector3(0, 0, 1), "side": Vector3(0, -1, 0)},
		{"name": "stbd", "o": Vector3(0, 0, H), "in": Vector3(0, 0, -1), "side": Vector3(0, 1, 0)},
	]

func _wall_xf(w: Dictionary, x: float, s: float, lift: float) -> Transform3D:
	# Point on wall w at axial x, across-wall s (-H..H), lifted 'lift' into the aisle.
	var inn: Vector3 = w["in"]
	var side: Vector3 = w["side"]
	# Columns: X along module, Y = into aisle, Z = across the wall.
	var basis := Basis(Vector3(1, 0, 0), inn, side)
	return Transform3D(basis, (w["o"] as Vector3) + side * s + inn * lift + Vector3(x, 0, 0))

func _build() -> void:
	_rng.seed = 2026
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rack_base := Color(0.86, 0.85, 0.80)    # off-white rack fronts
	var grey := Color(0.62, 0.63, 0.64)
	var blue := Color(0.50, 0.60, 0.72)
	var standoff := Color(0.58, 0.62, 0.68)     # corner standoffs, blue-grey
	var x0: float = -RACK_W * 3.0
	for w in _walls():
		var sh: float = SHADE[w["name"]]
		for i in range(6):
			var xc: float = x0 + RACK_W * (float(i) + 0.5)
			if w["name"] == "deck" and i == 3:
				continue  # Earth window rack, built separately below (open centre)
			# Rack face, slightly inset into the wall, a thin gap between racks.
			_box(st, Vector3(RACK_W - 0.03, 0.04, 1.30), _wall_xf(w, xc, 0.0, 0.0), rack_base * sh)
			# 2-5 sub-panels per rack: lockers, drawers, instrument panels.
			var y: float = -0.6
			while y < 0.55:
				var ph: float = _rng.randf_range(0.18, 0.42)
				var pc: Color = [rack_base * 0.95, grey, blue, Color(0.80, 0.80, 0.76)][_rng.randi() % 4]
				_box(st, Vector3(RACK_W - 0.14, 0.03, ph - 0.04), _wall_xf(w, xc, y + ph * 0.5, 0.035), pc * sh)
				# knobs / latches
				_box(st, Vector3(0.06, 0.03, 0.03), _wall_xf(w, xc + RACK_W * 0.35, y + ph * 0.5, 0.06), Color(0.2, 0.2, 0.22))
				y += ph
			# Status LEDs
			for k in range(_rng.randi_range(1, 4)):
				var led: Color = [Color(0.2, 1.0, 0.3), Color(1.0, 0.7, 0.1), Color(0.3, 0.6, 1.0)][_rng.randi() % 3]
				_box(st, Vector3(0.02, 0.012, 0.02), _wall_xf(w, xc - 0.35 + float(k) * 0.05, 0.55, 0.06), led)
			# White cargo bag (CTB) strapped on, on some racks
			if _rng.randf() < 0.45:
				_box(st, Vector3(0.50, 0.25, 0.34), _wall_xf(w, xc + _rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.3, 0.3), 0.16), Color(0.93, 0.93, 0.90) * sh)
				_box(st, Vector3(0.52, 0.27, 0.03), _wall_xf(w, xc, 0.0, 0.16), Color(0.25, 0.25, 0.28))  # strap
			# Laptop on an arm, on some side racks
			if (w["name"] == "port" or w["name"] == "stbd") and _rng.randf() < 0.4:
				_box(st, Vector3(0.04, 0.30, 0.04), _wall_xf(w, xc, 0.1, 0.17), Color(0.3, 0.3, 0.32))
				_box(st, Vector3(0.36, 0.02, 0.26), _wall_xf(w, xc, 0.1, 0.33), Color(0.12, 0.12, 0.13))
				_box(st, Vector3(0.32, 0.005, 0.20), _wall_xf(w, xc, 0.1, 0.345), Color(0.25, 0.45, 0.75))  # screen glow
			# Cables: a few dark runs across the rack face
			for k in range(_rng.randi_range(1, 3)):
				var b := Basis(Vector3(1, 0, 0), w["in"], w["side"]).rotated(w["in"], _rng.randf_range(-0.8, 0.8))
				_box(st, Vector3(RACK_W * 0.9, 0.015, 0.015), Transform3D(b, _wall_xf(w, xc, _rng.randf_range(-0.5, 0.5), 0.09).origin), [Color(0.1, 0.1, 0.1), Color(0.15, 0.15, 0.2), Color(0.9, 0.9, 0.9)][_rng.randi() % 3])
			# Velcro patches
			for k in range(2):
				_box(st, Vector3(0.08, 0.006, 0.05), _wall_xf(w, xc + _rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.55, 0.55), 0.05), Color(0.45, 0.45, 0.47))
		# Handrails: grey bars along the rack edges, every other rack
		for i in range(0, 6, 2):
			var xh: float = x0 + RACK_W * (float(i) + 0.5)
			_box(st, Vector3(0.45, 0.035, 0.035), _wall_xf(w, xh, 0.62, 0.10), Color(0.55, 0.57, 0.60))
			_box(st, Vector3(0.035, 0.08, 0.035), _wall_xf(w, xh - 0.2, 0.62, 0.05), Color(0.55, 0.57, 0.60))
			_box(st, Vector3(0.035, 0.08, 0.035), _wall_xf(w, xh + 0.2, 0.62, 0.05), Color(0.55, 0.57, 0.60))
	# Corner standoffs (45 deg strips) with LED light panels on the overhead pair.
	var half_len: float = RACK_W * 3.0
	for cy in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var pos := Vector3(0, cy * (H - 0.18), cz * (H - 0.18))
			var b := Basis(Vector3(1, 0, 0), deg_to_rad(45.0 * cy * cz))
			_box(st, Vector3(half_len * 2.0, 0.06, 0.52), Transform3D(b, pos), standoff * (1.0 if cy > 0.0 else 0.8))
			if cy > 0.0:
				for k in range(4):
					var lx: float = -half_len + 0.8 + float(k) * 1.6
					_box(st, Vector3(0.9, 0.03, 0.22), Transform3D(b, pos + b.y * -0.04 + Vector3(lx, 0, 0)), Color(1.0, 1.0, 0.97))
	# Deck Earth window (real: ~51 cm, nadir): frame around an opening.
	var wx: float = x0 + RACK_W * 3.5
	var deck: Dictionary = _walls()[0]
	for side_s in [-1.0, 1.0]:
		_box(st, Vector3(RACK_W - 0.03, 0.04, 0.38), _wall_xf(deck, wx, side_s * 0.46, 0.0), rack_base * SHADE["deck"])
		_box(st, Vector3(0.28, 0.04, 0.6), _wall_xf(deck, wx + side_s * 0.39, 0.0, 0.0), rack_base * SHADE["deck"])
	for k in range(16):
		var a: float = TAU * float(k) / 16.0
		var p := Vector3(wx + cos(a) * 0.29, -H + 0.03, sin(a) * 0.29)
		_box(st, Vector3(0.13, 0.06, 0.05), Transform3D(Basis(Vector3.UP, -a), p), Color(0.25, 0.25, 0.27))
	# End cones with open square hatches (real CBM hatch ~1.27 m, rounded).
	for ex in [-1.0, 1.0]:
		var xe: float = ex * (half_len + 0.35)
		var sh2: float = SHADE["end"]
		_box(st, Vector3(0.08, 2.0, 0.37), Transform3D(Basis.IDENTITY, Vector3(xe, 0, 0.82)), Color(0.80, 0.80, 0.78) * sh2)
		_box(st, Vector3(0.08, 2.0, 0.37), Transform3D(Basis.IDENTITY, Vector3(xe, 0, -0.82)), Color(0.80, 0.80, 0.78) * sh2)
		_box(st, Vector3(0.08, 0.37, 1.27), Transform3D(Basis.IDENTITY, Vector3(xe, 0.82, 0)), Color(0.80, 0.80, 0.78) * sh2)
		_box(st, Vector3(0.08, 0.37, 1.27), Transform3D(Basis.IDENTITY, Vector3(xe, -0.82, 0)), Color(0.80, 0.80, 0.78) * sh2)
		# hatch frame ring
		_box(st, Vector3(0.12, 0.06, 1.30), Transform3D(Basis.IDENTITY, Vector3(xe, 0.64, 0)), Color(0.55, 0.55, 0.57))
		_box(st, Vector3(0.12, 0.06, 1.30), Transform3D(Basis.IDENTITY, Vector3(xe, -0.64, 0)), Color(0.55, 0.55, 0.57))
		_box(st, Vector3(0.12, 1.30, 0.06), Transform3D(Basis.IDENTITY, Vector3(xe, 0, 0.64)), Color(0.55, 0.55, 0.57))
		_box(st, Vector3(0.12, 1.30, 0.06), Transform3D(Basis.IDENTITY, Vector3(xe, 0, -0.64)), Color(0.55, 0.55, 0.57))
		# Bridge to the end cone corners (fills between racks and hatch wall)
		_box(st, Vector3(0.35, 0.04, 2.0), Transform3D(Basis.IDENTITY, Vector3(ex * (half_len + 0.17), H, 0)), Color(0.82, 0.82, 0.80) * SHADE["ovhd"])
		_box(st, Vector3(0.35, 0.04, 2.0), Transform3D(Basis.IDENTITY, Vector3(ex * (half_len + 0.17), -H, 0)), Color(0.82, 0.82, 0.80) * SHADE["deck"])
		_box(st, Vector3(0.35, 2.0, 0.04), Transform3D(Basis.IDENTITY, Vector3(ex * (half_len + 0.17), 0, H)), Color(0.82, 0.82, 0.80) * SHADE["stbd"])
		_box(st, Vector3(0.35, 2.0, 0.04), Transform3D(Basis.IDENTITY, Vector3(ex * (half_len + 0.17), 0, -H)), Color(0.82, 0.82, 0.80) * SHADE["port"])
		# Node beyond the hatch (Unity aft, Harmony forward): a 2.6 m room
		# with its own hatches on the side walls, dimmer, so the station
		# reads as continuing past this module.
		var nx: float = xe + ex * 1.3
		var nd: float = 0.62
		_box(st, Vector3(0.05, 2.6, 2.6), Transform3D(Basis.IDENTITY, Vector3(nx + ex * 1.3, 0, 0)), Color(0.70, 0.70, 0.68) * nd)
		_box(st, Vector3(2.6, 0.05, 2.6), Transform3D(Basis.IDENTITY, Vector3(nx, 1.3, 0)), Color(0.80, 0.80, 0.78) * nd)
		_box(st, Vector3(2.6, 0.05, 2.6), Transform3D(Basis.IDENTITY, Vector3(nx, -1.3, 0)), Color(0.66, 0.66, 0.64) * nd)
		_box(st, Vector3(2.6, 2.6, 0.05), Transform3D(Basis.IDENTITY, Vector3(nx, 0, 1.3)), Color(0.74, 0.74, 0.72) * nd)
		_box(st, Vector3(2.6, 2.6, 0.05), Transform3D(Basis.IDENTITY, Vector3(nx, 0, -1.3)), Color(0.74, 0.74, 0.72) * nd)
		for hz in [-1.0, 1.0]:
			_box(st, Vector3(1.2, 1.2, 0.03), Transform3D(Basis.IDENTITY, Vector3(nx, 0, hz * 1.27)), Color(0.45, 0.46, 0.48) * nd)
		_box(st, Vector3(0.03, 1.2, 1.2), Transform3D(Basis.IDENTITY, Vector3(nx + ex * 1.27, 0, 0)), Color(0.45, 0.46, 0.48) * nd)
		_box(st, Vector3(1.6, 0.03, 0.3), Transform3D(Basis.IDENTITY, Vector3(nx, 1.27, 0)), Color(1.0, 1.0, 0.95) * 0.8)
	# Outer shell around everything (passthrough is always on, so any gap
	# would show the real room). Closed on all sides except a 0.52 m hole
	# under the deck window, so the only thing outside you can see is Earth.
	var sx: float = half_len + 0.35 + 2.7
	var sy: float = 1.4
	var shell := Color(0.12, 0.12, 0.13)
	_box(st, Vector3(sx * 2.0, 0.04, sy * 2.0), Transform3D(Basis.IDENTITY, Vector3(0, sy, 0)), shell)
	_box(st, Vector3(sx * 2.0, sy * 2.0, 0.04), Transform3D(Basis.IDENTITY, Vector3(0, 0, sy)), shell)
	_box(st, Vector3(sx * 2.0, sy * 2.0, 0.04), Transform3D(Basis.IDENTITY, Vector3(0, 0, -sy)), shell)
	_box(st, Vector3(0.04, sy * 2.0, sy * 2.0), Transform3D(Basis.IDENTITY, Vector3(sx, 0, 0)), shell)
	_box(st, Vector3(0.04, sy * 2.0, sy * 2.0), Transform3D(Basis.IDENTITY, Vector3(-sx, 0, 0)), shell)
	var hw: float = 0.26
	var lx0: float = -sx
	var lx1: float = wx - hw
	_box(st, Vector3(lx1 - lx0, 0.04, sy * 2.0), Transform3D(Basis.IDENTITY, Vector3((lx0 + lx1) * 0.5, -sy, 0)), shell)
	var rx0: float = wx + hw
	_box(st, Vector3(sx - rx0, 0.04, sy * 2.0), Transform3D(Basis.IDENTITY, Vector3((rx0 + sx) * 0.5, -sy, 0)), shell)
	_box(st, Vector3(hw * 2.0, 0.04, sy - hw), Transform3D(Basis.IDENTITY, Vector3(wx, -sy, (sy + hw) * 0.5)), shell)
	_box(st, Vector3(hw * 2.0, 0.04, sy - hw), Transform3D(Basis.IDENTITY, Vector3(wx, -sy, -(sy + hw) * 0.5)), shell)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	_build_window_and_earth(wx)
	_build_floaters()

func _build_window_and_earth(wx: float) -> void:
	# Window tube: a short black shaft under the deck opening, open at the
	# bottom, so you look down through the ~0.5 m window at Earth.
	var tube := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.26
	tm.bottom_radius = 0.26
	tm.height = 0.2
	tm.cap_top = false
	tm.cap_bottom = false
	tm.radial_segments = 24
	tube.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(0.08, 0.08, 0.09)
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tube.material_override = tmat
	tube.position = Vector3(wx, -H - 0.1, 0)
	add_child(tube)
	# Earth at true apparent size: 6371 km radius seen from 420 km up,
	# scaled 1 m = 10 km so it sits inside the camera's far plane.
	_earth = MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 637.1
	em.height = 1274.2
	em.radial_segments = 96
	em.rings = 48
	_earth.mesh = em
	# vc182 Earth that looks like Earth from 420 km: the NASA Blue Marble
	# map (2k) is too coarse for a close look, so the shader adds real-
	# looking fine detail on top of it: moving cloud fields (several sizes),
	# land texture, sunglint on the ocean, and the thin blue atmosphere at
	# the edge. Map: NASA Blue Marble, public domain. Cloud/detail layers
	# are simulated (procedural), not today's real clouds.
	var emat := ShaderMaterial.new()
	emat.shader = Shader.new()
	emat.shader.code = """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform sampler2D earth_tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 v_obj;
float h3(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z); }
float fbm(vec3 p){ float a = 0.5; float s = 0.0; for (int k = 0; k < 6; k++) { s += a * n3(p); p = p * 2.03 + 1.7; a *= 0.5; } return s; }
void vertex(){ v_obj = VERTEX; }
void fragment(){
	vec3 base = texture(earth_tex, UV).rgb;
	vec3 q = v_obj;                                     // metres on a 637 m Earth (1 m = 10 km)
	float ocean = smoothstep(0.02, 0.10, base.b - max(base.r, base.g) * 0.85);
	float d = fbm(q * 0.08);
	vec3 land = base * (0.80 + 0.45 * d);               // fields, ridges, deserts break up
	vec3 sea = base * (0.90 + 0.15 * fbm(q * 0.03)) + vec3(0.02, 0.05, 0.10);
	vec3 col = mix(land, sea, ocean);
	// clouds: big weather systems + small puffy cumulus, drifting slowly
	float c1 = fbm(q * 0.012 + vec3(TIME * 0.0008, 0.0, 0.0));
	float c2 = fbm(q * 0.07 + vec3(0.0, TIME * 0.002, 3.0));
	float cl = smoothstep(0.60, 0.78, c1 * 0.75 + c2 * 0.35);
	col = mix(col, vec3(0.97, 0.98, 1.0), cl * 0.92);
	// a little sunglint on the ocean
	float glint = pow(max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 40.0) * ocean * (1.0 - cl);
	col += vec3(0.25, 0.27, 0.30) * glint;
	// atmosphere: bluer and hazier toward the edge of the disc
	float rim = 1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	col = mix(col, vec3(0.45, 0.65, 1.0), pow(rim, 2.5) * 0.8);
	ALBEDO = col;
}
"""
	var tex: Texture2D = load(EARTH_TEX) if ResourceLoader.exists(EARTH_TEX) else null
	if tex != null:
		emat.set_shader_parameter("earth_tex", tex)
	_earth.material_override = emat
	_earth.position = Vector3(wx, -H - 42.0 - 637.1, 0)
	# Equator facing up toward the window (the sphere's top is the North
	# Pole by default, which is why the window showed dark polar sea).
	# The Earth keeps turning under you, one orbit every ~93 min.
	_earth.rotation = Vector3(deg_to_rad(90.0 - 28.4), 0.0, deg_to_rad(81.8 - 90.0))
	add_child(_earth)
	# Thin glowing atmosphere shell, visible as the blue limb.
	var atm := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 643.0
	am.height = 1286.0
	am.radial_segments = 96
	am.rings = 48
	atm.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = Shader.new()
	amat.shader.code = "shader_type spatial; render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled; void fragment(){ float rim = 1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0); ALBEDO = vec3(0.30, 0.55, 1.0) * pow(rim, 3.0) * 1.4; }"
	atm.material_override = amat
	atm.position = _earth.position
	add_child(atm)
	# Black space with stars all around (also stops the real room showing
	# through anywhere, since passthrough is always on).
	var space := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3000.0
	sm.height = 6000.0
	space.mesh = sm
	var spm := ShaderMaterial.new()
	spm.shader = Shader.new()
	spm.shader.code = "shader_type spatial; render_mode unshaded, cull_front, fog_disabled; varying vec3 v_d; void vertex(){ v_d = normalize(VERTEX); } float h(vec3 p){ return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); } void fragment(){ vec3 c = floor(v_d * 400.0); float s = step(0.9985, h(c)); ALBEDO = vec3(s * 0.9); }"
	space.material_override = spm
	space.position = Vector3(0, 0, 0)
	add_child(space)

func _build_floaters() -> void:
	# A few loose items drifting, like real crew photos: drink pouch, pen,
	# a cargo bag on a tether. Slow, small motion only (comfort).
	var items: Array = [
		[Vector3(0.12, 0.18, 0.04), Color(0.85, 0.85, 0.9), Vector3(0.8, 0.2, 0.4)],
		[Vector3(0.14, 0.012, 0.012), Color(0.1, 0.2, 0.7), Vector3(-1.2, -0.1, -0.3)],
		[Vector3(0.42, 0.26, 0.30), Color(0.93, 0.93, 0.90), Vector3(2.0, 0.45, 0.5)],
		[Vector3(0.22, 0.03, 0.16), Color(0.12, 0.12, 0.13), Vector3(-2.2, 0.3, 0.55)],
	]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var ph: float = 0.0
	for it in items:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(st, it[0], Transform3D.IDENTITY, it[1])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.position = it[2]
		add_child(mi)
		_floaters.append({"node": mi, "base": it[2], "phase": ph})
		ph += 1.7

func _ready() -> void:
	_build()
	# vc182 easter egg: two Quest 3-style headsets drifting in zero-g.
	_add_headset(Vector3(1.1, 0.25, -0.35), Vector3(0.2, 0.6, 0.1), 0.0)
	_add_headset(Vector3(-2.6, -0.2, 0.45), Vector3(-0.5, 2.2, 0.3), 2.3)

# vc182 EASTER EGG (user 2026-11-04): Meta Quest 3-style VR headsets floating
# with no gravity. Built in code at real size from the published shape:
# 184 x 160 x 98 mm, white slim front, three vertical dark "pill" sensor
# housings on the front (cameras left and right, depth sensor centre),
# dark facial interface, grey side arms and a split fabric strap.
# Shape only: no logos, no lettering, no Meta branding.
func _add_headset(pos: Vector3, rot: Vector3, phase: float) -> void:
	var root := Node3D.new()
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.94, 0.94, 0.93)
	white.roughness = 0.45
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.06, 0.07)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.56, 0.58)
	grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color(0.80, 0.80, 0.79)
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Main body: a wide rounded "pill" 184 mm wide, 98 mm tall, ~65 mm deep.
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.049
	cap.height = 0.184
	cap.radial_segments = 24
	cap.rings = 6
	body.mesh = cap
	body.rotation.z = PI / 2.0
	body.scale = Vector3(1.0, 1.0, 0.66)
	body.material_override = white
	root.add_child(body)
	# Slightly darker back half so the body reads as 3D in unshaded light.
	var back := MeshInstance3D.new()
	back.mesh = cap
	back.rotation.z = PI / 2.0
	back.scale = Vector3(0.97, 0.97, 0.6)
	back.position = Vector3(0.0, 0.0, -0.006)
	back.material_override = shade
	root.add_child(back)
	# Three vertical pill sensor housings on the front face.
	for px in [-0.058, 0.0, 0.058]:
		var pill := MeshInstance3D.new()
		var pm := CapsuleMesh.new()
		pm.radius = 0.0105
		pm.height = 0.05 if px != 0.0 else 0.042
		pm.radial_segments = 12
		pm.rings = 4
		pill.mesh = pm
		pill.position = Vector3(px, 0.0, 0.031)
		pill.scale = Vector3(1.0, 1.0, 0.35)
		pill.material_override = dark
		root.add_child(pill)
	# Facial interface (dark foam) at the back.
	var face := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.165, 0.075, 0.03)
	face.mesh = fm
	face.position = Vector3(0.0, -0.004, -0.045)
	face.material_override = dark
	root.add_child(face)
	# Side arms and split fabric strap looping round the back.
	for sx in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.012, 0.022, 0.11)
		arm.mesh = am
		arm.position = Vector3(sx * 0.088, 0.0, -0.095)
		arm.material_override = grey
		root.add_child(arm)
	for sy in [-0.016, 0.016]:
		var strap := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.084
		tm.outer_radius = 0.094
		tm.rings = 6
		tm.ring_segments = 32  # vc195 fix: same torus swap - main circle was 6, hexagonal strap loop
		strap.mesh = tm
		strap.position = Vector3(0.0, sy, -0.15)
		strap.scale = Vector3(1.0, 0.35, 0.85)
		strap.material_override = grey
		root.add_child(strap)
	root.position = pos
	root.rotation = rot
	add_child(root)
	_floaters.append({"node": root, "base": pos, "phase": phase})

func _process(delta: float) -> void:
	if not visible:
		return
	var t: float = Time.get_unix_time_from_system()
	for f: Dictionary in _floaters:
		var node: Node3D = f["node"]
		var base: Vector3 = f["base"]
		var ph: float = float(f["phase"])
		node.position = base + Vector3(sin(t * 0.21 + ph) * 0.06, sin(t * 0.33 + ph) * 0.05, cos(t * 0.27 + ph) * 0.05)
		node.rotation += Vector3(0.07, 0.11, 0.05) * delta
	# Earth turns under you: one orbit (~93 min), moving aft along the module.
	if _earth != null:
		_earth.rotate_z(-TAU / 5560.0 * delta)
