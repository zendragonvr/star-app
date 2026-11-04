class_name Ephemeris
extends RefCounted
## Positions of the planets and the interstellar comet 3I/ATLAS.
## Heliocentric, ecliptic J2000, in AU, right-handed (x toward the vernal equinox, z north).
##
## 3I/ATLAS elements: JPL Small-Body Database solution #29 (epoch JD 2460882.5 TDB).
## Planets: Standish approximate elements for 1800-2050 (good to about 0.01 AU or better).
## Positions are geometric: no light-time, no aberration. That is fine for display
## (error is well under 0.1 degree for 3I/ATLAS at 12+ AU).
##
## Usage:
##   var jd := Ephemeris.now_jd()
##   var helio := Ephemeris.atlas_helio(jd)              # Vector3, ecliptic AU
##   var godot_pos := Ephemeris.ecl_to_godot(helio)       # for a solar-system view
##   var sky := Ephemeris.atlas_sky(jd)                   # {ra_h, dec_deg, dist_au, helio_au}
##   var aa := Ephemeris.alt_az(sky.ra_h, sky.dec_deg, jd, lat_deg, lon_deg_east)
##   var dir := Ephemeris.altaz_to_godot_dir(aa.alt, aa.az)  # east=+X, up=+Y, north=-Z

const K := 0.01720209895           # Gaussian gravitational constant
const MU := K * K                  # GM of the Sun in AU^3/day^2
const AU_KM := 149597870.7

# ---- 3I/ATLAS (hyperbolic) ----
const ATLAS_E := 6.137369905616049
const ATLAS_Q := 1.356062963460816
const ATLAS_I_DEG := 175.1128860522239
const ATLAS_NODE_DEG := 322.1527181958458
const ATLAS_W_DEG := 128.012084236624
const ATLAS_TP_JD := 2460977.983370982484   # perihelion, 2025-10-29.48 TDB

# ---- Planets: [a, e, I, L, long.peri, long.node] and rates per Julian century ----
const PLANETS := {
	"mercury": [[0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
				[0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]],
	"venus": [[0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
				[0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]],
	"earth": [[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
				[0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]],
	"mars": [[1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
				[0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]],
	"jupiter": [[5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
				[-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]],
	"saturn": [[9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
				[-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]],
	"uranus": [[19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
				[-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]],
	"neptune": [[30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
				[0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]],
}


# ------------------------------------------------------------------ time
static func jd_from_unix(unix_seconds: float) -> float:
	return unix_seconds / 86400.0 + 2440587.5


static func now_jd() -> float:
	return jd_from_unix(Time.get_unix_time_from_system())


static func jd_from_utc(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> float:
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": second})
	return jd_from_unix(unix)


# ------------------------------------------------------------------ 3I/ATLAS
static func atlas_helio(jd: float) -> Vector3:
	var a := ATLAS_Q / (ATLAS_E - 1.0)                 # |semi-major axis|, AU
	var n := sqrt(MU / (a * a * a))                    # rad/day
	var m := n * (jd - ATLAS_TP_JD)                    # hyperbolic mean anomaly
	var h := asinh(m / ATLAS_E) if absf(m) > 1.0 else m
	for i in 60:
		var f := ATLAS_E * sinh(h) - h - m
		var step := f / (ATLAS_E * cosh(h) - 1.0)
		h -= step
		if absf(step) < 1e-13:
			break
	var x := a * (ATLAS_E - cosh(h))
	var y := a * sqrt(ATLAS_E * ATLAS_E - 1.0) * sinh(h)
	return _orbital_to_ecliptic(x, y, ATLAS_I_DEG, ATLAS_NODE_DEG, ATLAS_W_DEG)


## Speed relative to the Sun in km/s (about 58 at infinity, 68 at perihelion).
static func atlas_speed_kms(jd: float) -> float:
	var r := atlas_helio(jd).length()
	var a := ATLAS_Q / (ATLAS_E - 1.0)
	var v2 := MU * (2.0 / r + 1.0 / a)                 # vis-viva for a hyperbola
	return sqrt(v2) * AU_KM / 86400.0


## Geocentric view of the comet.
## Returns {ra_h, dec_deg, dist_au, helio_au, elong_deg}. RA/Dec are for the date (apparent frame, no aberration).
static func atlas_sky(jd: float) -> Dictionary:
	var helio := atlas_helio(jd)
	var earth := planet_helio("earth", jd)
	var geo := helio - earth
	var eq := ecl_to_equatorial_of_date(geo, jd)
	var to_sun := -earth
	var elong := rad_to_deg(acos(clampf(geo.normalized().dot(to_sun.normalized()), -1.0, 1.0)))
	return {
		"ra_h": eq.ra_h, "dec_deg": eq.dec_deg,
		"dist_au": geo.length(), "helio_au": helio.length(), "elong_deg": elong,
	}


## Sample the trajectory for drawing a path line. Returns PackedVector3Array in ecliptic AU.
static func atlas_path(jd_start: float, jd_end: float, step_days: float = 10.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var jd := jd_start
	while jd <= jd_end:
		pts.append(atlas_helio(jd))
		jd += step_days
	return pts


# ------------------------------------------------------------------ planets
static func planet_helio(name: String, jd: float) -> Vector3:
	var el: Array = PLANETS[name][0]
	var rt: Array = PLANETS[name][1]
	var t := (jd - 2451545.0) / 36525.0
	var a: float = el[0] + rt[0] * t
	var e: float = el[1] + rt[1] * t
	var inc: float = el[2] + rt[2] * t
	var l: float = el[3] + rt[3] * t
	var w: float = el[4] + rt[4] * t       # longitude of perihelion
	var node: float = el[5] + rt[5] * t
	var m := deg_to_rad(fposmod(l - w, 360.0))
	var ea := m + e * sin(m)
	for i in 50:
		var d := (ea - e * sin(ea) - m) / (1.0 - e * cos(ea))
		ea -= d
		if absf(d) < 1e-13:
			break
	var xp := a * (cos(ea) - e)
	var yp := a * sqrt(1.0 - e * e) * sin(ea)
	return _orbital_to_ecliptic(xp, yp, inc, node, w - node)


# ------------------------------------------------------------------ geometry helpers
static func _orbital_to_ecliptic(x: float, y: float, inc_deg: float, node_deg: float, arg_peri_deg: float) -> Vector3:
	var co := cos(deg_to_rad(node_deg))
	var so := sin(deg_to_rad(node_deg))
	var ci := cos(deg_to_rad(inc_deg))
	var si := sin(deg_to_rad(inc_deg))
	var cw := cos(deg_to_rad(arg_peri_deg))
	var sw := sin(deg_to_rad(arg_peri_deg))
	return Vector3(
		(co * cw - so * sw * ci) * x + (-co * sw - so * cw * ci) * y,
		(so * cw + co * sw * ci) * x + (-so * sw + co * cw * ci) * y,
		(sw * si) * x + (cw * si) * y)


## Ecliptic J2000 -> Godot axes (x stays, ecliptic north becomes +Y, ecliptic y becomes -Z).
static func ecl_to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## Ecliptic J2000 vector (e.g., geocentric) -> {ra_h, dec_deg} for the date, applying
## general precession in longitude and the obliquity of date.
static func ecl_to_equatorial_of_date(v: Vector3, jd: float) -> Dictionary:
	var t := (jd - 2451545.0) / 36525.0
	var lon := atan2(v.y, v.x) + deg_to_rad((5028.796195 * t + 1.1054348 * t * t) / 3600.0)
	var lat := atan2(v.z, sqrt(v.x * v.x + v.y * v.y))
	var eps := deg_to_rad(23.439291111 - 0.0130042 * t)
	var xe := cos(lat) * cos(lon)
	var ye := cos(lat) * sin(lon) * cos(eps) - sin(lat) * sin(eps)
	var ze := cos(lat) * sin(lon) * sin(eps) + sin(lat) * cos(eps)
	var ra := fposmod(rad_to_deg(atan2(ye, xe)), 360.0) / 15.0
	var dec := rad_to_deg(atan2(ze, sqrt(xe * xe + ye * ye)))
	return {"ra_h": ra, "dec_deg": dec}


## Observer on Earth (lat north+, lon EAST+, degrees). Returns {alt, az} in degrees.
## az is measured from north toward east. No refraction.
static func alt_az(ra_h: float, dec_deg: float, jd: float, lat_deg: float, lon_deg_east: float) -> Dictionary:
	var gmst_h := fposmod(18.697374558 + 24.06570982441908 * (jd - 2451545.0), 24.0)
	var lst_h := fposmod(gmst_h + lon_deg_east / 15.0, 24.0)
	var ha := deg_to_rad((lst_h - ra_h) * 15.0)
	var dec := deg_to_rad(dec_deg)
	var lat := deg_to_rad(lat_deg)
	var sin_alt := sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(ha)
	var alt := asin(clampf(sin_alt, -1.0, 1.0))
	var north := sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(ha)
	var east := -cos(dec) * sin(ha)
	var az := fposmod(rad_to_deg(atan2(east, north)), 360.0)
	return {"alt": rad_to_deg(alt), "az": az}


## World direction for a sky position: east = +X, up = +Y, north = -Z.
## If your world is rotated to a different heading, rotate the result around Y.
static func altaz_to_godot_dir(alt_deg: float, az_deg: float) -> Vector3:
	var alt := deg_to_rad(alt_deg)
	var az := deg_to_rad(az_deg)
	return Vector3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt))
