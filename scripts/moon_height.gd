# vc115 Moon height function — USER-SUPPLIED, verbatim, except the
# marked comment slot, which is filled with a deterministic
# large-scale trig undulation (see below). Hash-based craters in
# 4 size layers, deterministic, so they never pop in as LOD rings
# move: the same function is used for rendering, footprint/track
# placement, and (via MarsWorld.ground_height) any ground query.
class_name MoonHeight
extends RefCounted

# [cell size m, crater probability per cell, min radius m, max radius m]
const LAYERS := [
	[600.0, 0.55, 60.0, 220.0],
	[160.0, 0.60, 15.0, 60.0],
	[40.0, 0.65, 4.0, 16.0],
	[10.0, 0.70, 1.0, 4.0],
]
const SUMMIT_CLEAR := 6.0   # vc154: was 25 m, so the ground at your feet looked smooth and crater-free. 6 m keeps the standing spot itself flat, craters start just past it.

static func _h(ix: int, iz: int, salt: int) -> float:
	var n := (ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0

static func crater_profile(d: float, depth: float, rim: float) -> float:
	if d < 1.0:
		return -depth * (1.0 - d * d) + rim   # bowl
	return rim * pow(1.0 / d, 3.0)             # rim fading into ejecta

static func get_height(x: float, z: float) -> float:
	var r0 := Vector2(x, z).length()
	var h := 28.0 * exp(-pow(r0 / 140.0, 2.0))          # the hill
	# vc115: large-scale undulation filling the marked comment slot.
	# Deterministic trig (MoonHeight is static, so no FastNoiseLite
	# instance is available here, and MarsWorld noise is NOT used,
	# so MoonHeight.get_height alone stays the full height function).
	# Amplitude ~1.8 m, wavelength ~1.5-5 km: gentle, never fights
	# the 28 m hill or the craters, and the summit stays gentle.
	h += 1.2 * sin(x * 0.004) * cos(z * 0.0035) + 0.6 * sin(x * 0.0012 + 2.0)
	var mask := smoothstep(SUMMIT_CLEAR, SUMMIT_CLEAR + 24.0, r0)
	for li in LAYERS.size():
		var L = LAYERS[li]
		var cell: float = L[0]
		var ix := int(floor(x / cell))
		var iz := int(floor(z / cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cx := ix + dx
				var cz := iz + dz
				if _h(cx, cz, li * 7 + 1) > L[1]:
					continue
				var px := (cx + _h(cx, cz, li * 7 + 2)) * cell
				var pz := (cz + _h(cx, cz, li * 7 + 3)) * cell
				var rad: float = lerpf(L[2], L[3], pow(_h(cx, cz, li * 7 + 4), 2.5))
				var d := Vector2(x - px, z - pz).length() / rad
				if d > 4.0:
					continue
				var age := _h(cx, cz, li * 7 + 5)             # 0 fresh, 1 old
				var depth := rad * lerpf(0.20, 0.07, age)     # fresh craters are deeper
				var rim := rad * lerpf(0.04, 0.012, age)
				h += crater_profile(d, depth, rim) * mask
	return h
