# Fresh sky math, written 2026-10-26 from the validated math spec
# (research document, not copied code). All angles degrees at
# function boundaries, radians only inside trig. All math in
# 64-bit float, Vector3 only at final placement.
# Note: this v1 uses the public HYG star file without proper-motion
# columns, so high-proper-motion stars can be off by ~0.01 degrees.
# That is far below what an eye can see in-headset, and proper motion
# is a polish add if time allows. It is NOT claimed as spec-exact.
# Global class registration happens on editor import; scripts use preload instead.

const D2R: float = PI / 180.0
const SKY_RADIUS: float = 90.0

static func fmod360(x: float) -> float:
	return fposmod(x, 360.0)

static func jds_from_unix(sim_unix: float) -> Dictionary:
	var jd_utc: float = sim_unix / 86400.0 + 2440587.5
	var jd_tt: float = jd_utc + 69.0 / 86400.0
	var jd_ut1: float = jd_utc
	return {"utc": jd_utc, "tt": jd_tt, "ut1": jd_ut1}

static func gmst_deg(jd_ut1: float) -> float:
	var t: float = (jd_ut1 - 2451545.0) / 36525.0
	var g: float = 280.46061837 + 360.98564736629 * (jd_ut1 - 2451545.0) + 0.000387933 * t * t - (t * t * t) / 38710000.0
	return fposmod(g, 360.0)

static func unit_from_radec(ra_h: float, dec_deg: float) -> Vector3:
	var a: float = ra_h * 15.0 * D2R
	var d: float = dec_deg * D2R
	return Vector3(cos(d) * cos(a), cos(d) * sin(a), sin(d))

static func radec_from_vector(v: Vector3) -> Dictionary:
	var ra_h: float = fposmod(atan2(v.y, v.x), 2.0 * PI) / (15.0 * D2R)
	var dec_deg: float = asin(v.z / v.length()) / D2R
	return {"ra_h": ra_h, "dec_deg": dec_deg}

static func rot_z(v: Vector3, a_rad: float) -> Vector3:
	var c: float = cos(a_rad)
	var s: float = sin(a_rad)
	return Vector3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)

static func rot_y(v: Vector3, a_rad: float) -> Vector3:
	var c: float = cos(a_rad)
	var s: float = sin(a_rad)
	return Vector3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)

# J2000 -> of-date via IAU-1976 precession. Order matters:
# v' = Rz(+zeta) * Ry(-theta) * Rz(+z) * v
static func precess_j2000_to_of_date(ra_h: float, dec_deg: float, jd_tt: float) -> Dictionary:
	var t: float = (jd_tt - 2451545.0) / 36525.0
	var zeta: float = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600.0 * D2R
	var z: float = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600.0 * D2R
	var theta: float = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600.0 * D2R
	var v: Vector3 = unit_from_radec(ra_h, dec_deg)
	v = rot_z(v, z)
	v = rot_y(v, -theta)
	v = rot_z(v, zeta)
	return radec_from_vector(v)

static func alt_az(ra_h: float, dec_deg: float, jd_ut1: float, lat_deg: float, lon_deg: float) -> Dictionary:
	var lst: float = fposmod(gmst_deg(jd_ut1) + lon_deg, 360.0)
	var ha: float = fposmod(lst - ra_h * 15.0 + 540.0, 360.0) - 180.0
	var phi: float = lat_deg * D2R
	var dec: float = dec_deg * D2R
	var ha_r: float = ha * D2R
	var alt: float = asin(sin(dec) * sin(phi) + cos(dec) * cos(phi) * cos(ha_r)) / D2R
	var az: float = atan2(sin(ha_r), cos(ha_r) * sin(phi) - tan(dec) * cos(phi)) / D2R
	az = fposmod(az + 180.0, 360.0)
	return {"alt": alt, "az": az}

static func world_dir_from_alt_az(alt_deg: float, az_deg: float, yaw_offset_deg: float = 0.0, alt_offset_deg: float = 0.0) -> Vector3:
	var alt: float = (alt_deg + alt_offset_deg) * D2R
	var az: float = (az_deg + yaw_offset_deg) * D2R  # vc78 PRECISE: alt_offset corrects height, yaw corrects direction
	return Vector3(cos(alt) * sin(az), sin(alt), -cos(alt) * cos(az))

# Full pipeline for a catalog star: J2000 -> of-date -> alt/az -> world dir.
static func star_world_dir(ra_h: float, dec_deg: float, jd_tt: float, jd_ut1: float, lat_deg: float, lon_deg: float, yaw_offset_deg: float = 0.0, alt_offset_deg: float = 0.0) -> Vector3:
	var of_date: Dictionary = precess_j2000_to_of_date(ra_h, dec_deg, jd_tt)
	var aa: Dictionary = alt_az(of_date["ra_h"], of_date["dec_deg"], jd_ut1, lat_deg, lon_deg)
	return world_dir_from_alt_az(aa["alt"], aa["az"], yaw_offset_deg, alt_offset_deg)

static func star_alt_az(ra_h: float, dec_deg: float, jd_tt: float, jd_ut1: float, lat_deg: float, lon_deg: float) -> Dictionary:
	var of_date: Dictionary = precess_j2000_to_of_date(ra_h, dec_deg, jd_tt)
	return alt_az(of_date["ra_h"], of_date["dec_deg"], jd_ut1, lat_deg, lon_deg)

# --- Planets + Sun, JPL approximate Keplerian elements, public domain ---
# Element order: a, e, I, L, perihelion, node, then rates per century.
static func _planet_elements() -> Dictionary:
	return {
		"Mercury": [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593, 0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081],
		"Venus": [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255, 0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418],
		"Earth": [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0, 0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0],
		"Mars": [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891, 0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343],
		"Jupiter": [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909, -0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106],
		"Saturn": [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448, -0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794],
		"Uranus": [19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503, -0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589],
		"Neptune": [30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574, 0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664],
	}

static func _helio_ecliptic(name: String, jd_tt: float) -> Vector3:
	var el: Array = _planet_elements()[name]
	var t: float = (jd_tt - 2451545.0) / 36525.0
	var a: float = el[0] + el[6] * t
	var e: float = el[1] + el[7] * t
	var incl: float = el[2] + el[8] * t
	var l_deg: float = fposmod(el[3] + el[9] * t, 360.0)
	var peri: float = el[4] + el[10] * t
	var node: float = el[5] + el[11] * t
	var omega: float = peri - node
	var m_deg: float = fposmod(l_deg - peri, 360.0)
	var m: float = m_deg * D2R
	var ecc_anom: float = m + e * sin(m)
	for _i: int in range(12):
		ecc_anom -= (ecc_anom - e * sin(ecc_anom) - m) / (1.0 - e * cos(ecc_anom))
	var xp: float = a * (cos(ecc_anom) - e)
	var yp: float = a * sqrt(1.0 - e * e) * sin(ecc_anom)
	var o: float = omega * D2R
	var n: float = node * D2R
	var inc: float = incl * D2R
	var x: float = (cos(o) * cos(n) - sin(o) * sin(n) * cos(inc)) * xp + (-sin(o) * cos(n) - cos(o) * sin(n) * cos(inc)) * yp
	var y: float = (cos(o) * sin(n) + sin(o) * cos(n) * cos(inc)) * xp + (-sin(o) * sin(n) + cos(o) * cos(n) * cos(inc)) * yp
	var z: float = (sin(o) * sin(inc)) * xp + (cos(o) * sin(inc)) * yp
	return Vector3(x, y, z)

static func _ecliptic_to_equatorial(v: Vector3) -> Vector3:
	var eps: float = 23.4392911 * D2R
	return Vector3(v.x, v.y * cos(eps) - v.z * sin(eps), v.y * sin(eps) + v.z * cos(eps))

# Geocentric RA/Dec, J2000 frame, for a planet or "Sun".
static func planet_radec_j2000(name: String, jd_tt: float) -> Dictionary:
	var earth: Vector3 = _helio_ecliptic("Earth", jd_tt)
	var geo: Vector3
	if name == "Sun":
		geo = -earth
	else:
		geo = _helio_ecliptic(name, jd_tt) - earth
	return radec_from_vector(_ecliptic_to_equatorial(geo))

static func planet_world_dir(name: String, jd_tt: float, jd_ut1: float, lat_deg: float, lon_deg: float, yaw_offset_deg: float = 0.0, alt_offset_deg: float = 0.0) -> Vector3:
	var rd: Dictionary = planet_radec_j2000(name, jd_tt)
	var of_date: Dictionary = precess_j2000_to_of_date(rd["ra_h"], rd["dec_deg"], jd_tt)
	var aa: Dictionary = alt_az(of_date["ra_h"], of_date["dec_deg"], jd_ut1, lat_deg, lon_deg)
	return world_dir_from_alt_az(aa["alt"], aa["az"], yaw_offset_deg, alt_offset_deg)

# --- Moon, simplified series + topocentric correction, spec section 9 ---
static func _sin_deg(x_deg: float) -> float:
	return sin(x_deg * D2R)

static func moon_radec_j2000(jd_tt: float, jd_ut1: float, lat_deg: float, lon_deg: float, topocentric: bool = true) -> Dictionary:
	var d: float = jd_tt - 2451543.5
	var node: float = fposmod(125.1228 - 0.0529538083 * d, 360.0)
	var incl: float = 5.1454
	var w: float = fposmod(318.0634 + 0.1643573223 * d, 360.0)
	var a_er: float = 60.2666
	var e: float = 0.0549
	var m_deg: float = fposmod(115.3654 + 13.0649929509 * d, 360.0)
	var ms_deg: float = fposmod(356.0470 + 0.9856002585 * d, 360.0)
	var lm: float = fposmod(node + w + m_deg, 360.0)
	var ls: float = fposmod(280.4665 + 0.98564736 * d, 360.0)
	var elong: float = fposmod(lm - ls, 360.0)
	var f_arg: float = fposmod(lm - node, 360.0)
	var m: float = m_deg * D2R
	var ecc_anom: float = m + e * sin(m) * (1.0 + e * cos(m))
	for _i: int in range(3):
		ecc_anom -= (ecc_anom - e * sin(ecc_anom) - m) / (1.0 - e * cos(ecc_anom))
	var xv: float = a_er * (cos(ecc_anom) - e)
	var yv: float = a_er * sqrt(1.0 - e * e) * sin(ecc_anom)
	var v_ang: float = atan2(yv, xv)
	var r_er: float = sqrt(xv * xv + yv * yv)
	var vw: float = v_ang + w * D2R
	var n_rad: float = node * D2R
	var i_rad: float = incl * D2R
	var xh: float = r_er * (cos(n_rad) * cos(vw) - sin(n_rad) * sin(vw) * cos(i_rad))
	var yh: float = r_er * (sin(n_rad) * cos(vw) + cos(n_rad) * sin(vw) * cos(i_rad))
	var zh: float = r_er * (sin(vw) * sin(i_rad))
	var lon_ecl: float = atan2(yh, xh) / D2R
	var lat_ecl: float = atan2(zh, sqrt(xh * xh + yh * yh)) / D2R
	lon_ecl += -1.274 * _sin_deg(m_deg - 2.0 * elong) + 0.658 * _sin_deg(2.0 * elong) - 0.186 * _sin_deg(ms_deg) - 0.059 * _sin_deg(2.0 * m_deg - 2.0 * elong) - 0.057 * _sin_deg(m_deg - 2.0 * elong + ms_deg) + 0.053 * _sin_deg(m_deg + 2.0 * elong) + 0.046 * _sin_deg(2.0 * elong - ms_deg) + 0.041 * _sin_deg(m_deg - ms_deg) - 0.035 * _sin_deg(elong) - 0.031 * _sin_deg(m_deg + ms_deg) - 0.015 * _sin_deg(2.0 * f_arg - 2.0 * elong) + 0.011 * _sin_deg(m_deg - 4.0 * elong)
	lat_ecl += -0.173 * _sin_deg(f_arg - 2.0 * elong) - 0.055 * _sin_deg(m_deg - f_arg - 2.0 * elong) - 0.046 * _sin_deg(m_deg + f_arg - 2.0 * elong) + 0.033 * _sin_deg(f_arg + 2.0 * elong) + 0.017 * _sin_deg(2.0 * m_deg + f_arg)
	r_er += -0.58 * cos((m_deg - 2.0 * elong) * D2R) - 0.46 * cos(2.0 * elong * D2R)
	var r_au: float = r_er * 6378.14 / 149597870.7
	var v_ecl: Vector3 = r_au * Vector3(cos(lon_ecl * D2R) * cos(lat_ecl * D2R), sin(lon_ecl * D2R) * cos(lat_ecl * D2R), sin(lat_ecl * D2R))
	var v_eq: Vector3 = _ecliptic_to_equatorial(v_ecl)
	if not topocentric:
		return radec_from_vector(v_eq)
	var phi: float = lat_deg * D2R
	var u: float = atan(0.99664719 * tan(phi))
	var rho_sin: float = 0.99664719 * sin(u) + (0.0 / 6378140.0) * sin(phi)
	var rho_cos: float = cos(u) + (0.0 / 6378140.0) * cos(phi)
	var theta: float = (gmst_deg(jd_ut1) + lon_deg) * D2R
	var observer_er: Vector3 = Vector3(rho_cos * cos(theta), rho_cos * sin(theta), rho_sin)
	var moon_er: Vector3 = v_eq * (149597870.7 / 6378.14)
	var topo: Vector3 = moon_er - observer_er
	return radec_from_vector(topo)

static func moon_world_dir(jd_tt: float, jd_ut1: float, lat_deg: float, lon_deg: float, yaw_offset_deg: float = 0.0, alt_offset_deg: float = 0.0) -> Vector3:
	var rd: Dictionary = moon_radec_j2000(jd_tt, jd_ut1, lat_deg, lon_deg, true)
	var of_date: Dictionary = precess_j2000_to_of_date(rd["ra_h"], rd["dec_deg"], jd_tt)
	var aa: Dictionary = alt_az(of_date["ra_h"], of_date["dec_deg"], jd_ut1, lat_deg, lon_deg)
	return world_dir_from_alt_az(aa["alt"], aa["az"], yaw_offset_deg, alt_offset_deg)
