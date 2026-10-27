# Star App main, written fresh 2026-10-26, hand-tracking step added
# 2026-10-26 (pinch tap-to-identify + one-time Moon calibration).
# Rules from the user, locked in the plan:
# - Passthrough the whole time, hand tracking first, controllers
#   optional, nothing requires a controller or keyboard.
# - No city typing, no settings: location from WiFi/network in
#   the shipped app (headless default is still Clermont, FL, until
#   the platform location call lands), time from the headset clock.
# - Calibration is ONE pinch, once ever, saved: click the real
#   Moon in the sky (or a bright star/planet if the Moon is not
#   out). WiFi gives location, the Moon pinch gives orientation
#   (yaw) — WiFi alone cannot replace it, because it says what
#   town you are in, not which way you are facing.
# - If a pinch is not sure, the panel says so instead of guessing.
extends Node3D

const AstroMathScript = preload("res://scripts/astro_math.gd")
const CALIBRATION_PATH: String = "user://starapp_calibration.cfg"

var xr_interface: XRInterface = null
var selected_object: String = ""
var calibration_done: bool = false
var calibration_source: String = ""
var yaw_offset_deg: float = 0.0

var _sky: Node = null
var _planets: Node = null
var _panel: Node = null
var _hands: Node = null
var _voice: Node = null
var _teacher: Node = null
var _camera: XRCamera3D = null
var _pt_reported: bool = false
var _ready_unix: float = 0.0
var _pinch_count: int = 0
var _last_diag_unix: float = 0.0
var _star_orb: MeshInstance3D = null
var _star_orb_name: String = ""
# v22 zoom dial drag state (Main only, not lock/teacher).
var _dial_dragging: bool = false
var _dial_hand: String = ""
var _dial_last_y: float = 0.0

func _ready() -> void:
	_ready_unix = Time.get_unix_time_from_system()
	_setup_xr()
	_sky = get_node_or_null("SkyCore")
	_planets = get_node_or_null("PlanetsCore")
	_panel = get_node_or_null("IdentifyPanel")
	_hands = get_node_or_null("HandTracking")
	_voice = get_node_or_null("VoiceUI")
	_teacher = get_node_or_null("TeacherClient")
	if _teacher != null:
		_teacher.answer_ready.connect(_on_teacher_answer)
	_camera = get_node_or_null("XROrigin/XRCamera") as XRCamera3D
	if _panel != null and _camera != null:
		_panel.set_camera(_camera)
	if _hands != null:
		_hands.pinch_detected.connect(_on_pinch)
		_hands.pinch_drag_detected.connect(_on_pinch_drag)
		_hands.pinch_released.connect(_on_pinch_release)
	_load_calibration()
	# Glasses-first boot message: this app is built for Meta VR
	# glasses, hand tracking and hand oriented. No controller is
	# required, ever — if the headset asks for one, that is a
	# headset prompt, not an app requirement.
	if _panel != null:
		if calibration_done:
			# v15: boot now confirms a saved lock, with its source,
			# instead of asking to lock again. A saved lock that
			# looks like "not locked yet" was part of the
			# 2026-10-27 "pinches aren't functional" report.
			var src: String = calibration_source if calibration_source != "" else "a sky object"
			_panel.show_object("Star App v21", "Sky locked — saved from " + src + "\nHands only — look and pinch.")
		else:
			_panel.show_object("Star App", "Hands only — look at the real Moon\nand pinch once to lock the sky.")

func _process(_delta: float) -> void:
	# v5 passthrough diagnostic — passthrough FIRST, before
	# anything else. After 2 seconds, the panel reports the
	# three settings that decide whether the room shows, in
	# plain words, so the next video tells us exactly which
	# step failed instead of just "black". The real test is
	# still visual: is your real room showing behind the panel?
	# NOTE on the old check: is_passthrough_enabled() is the
	# Facebook passthrough LAYER flag, not the compositor
	# passthrough. NNR v91 showed the room with blend=alpha
	# + transparent_bg=true and NO start_passthrough() call at
	# all — that is the recipe v5 follows. The FB flag below
	# is informational only, never the verdict.
	# v9 live diagnostic — v8 verdict: panel said Hands NONE
	# for the whole video, but that panel was written ONCE at
	# 2 seconds, while the user was still on the controller
	# from launching. Hand status at 2s is stale, not proof
	# that hands never tracked later. v9 updates every second,
	# but only while the panel is still the diagnostic panel
	# (starts with "Star App") — once a pinch identifies or
	# calibrates, that panel wins and diagnostic stops
	# overwriting it. Pinch count proves pinch fired even if
	# calibration then says "Not sure".
	if _panel != null and Time.get_unix_time_from_system() > _last_diag_unix + 1.0:
		var cur: String = _panel.current_text()
		# v15: diagnostic must never overwrite a lock confirmation,
		# including the boot lock message ("Star App\nSky locked...").
		# The old "begins with Star App" rule overwrote the boot
		# lock message 1 s after launch, which is why a saved lock
		# looked like "not locked yet" in 2026-10-27 testing.
		if cur == "" or (cur.begins_with("Star App") and not cur.contains("Sky locked")):
			_last_diag_unix = Time.get_unix_time_from_system()
			var blend_str: String = "OTHER"
			var modes_str: String = "?"
			if xr_interface != null:
				blend_str = "ALPHA" if xr_interface.environment_blend_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND else "OPAQUE"
				var modes: Array = xr_interface.get_supported_environment_blend_modes()
				var parts: Array = []
				for m: int in modes:
					if m == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
						parts.append("ALPHA")
					elif m == XRInterface.XR_ENV_BLEND_MODE_ADDITIVE:
						parts.append("ADD")
					elif m == XRInterface.XR_ENV_BLEND_MODE_OPAQUE:
						parts.append("OPAQUE")
					else:
						parts.append(str(m))
				modes_str = ",".join(parts)
			var bg_str: String = "CLEAR" if get_viewport().transparent_bg else "OPAQUE"
			var hand_str: String = "L:" + _hand_status("left") + " R:" + _hand_status("right")
			# v11 night-test aid — calibration is blind without this:
			# Moon lock only checks ALTITUDE within 5 degrees, then
			# sets yaw from azimuth. If you pinch a street light
			# (low) while the Moon is high, altitude mismatches and
			# you get "Not sure" with no clue why. Show the numbers
			# live until calibration succeeds, so the user can tilt
			# until gaze altitude matches Moon altitude, then pinch.
			# Test aid only: remove before final submission build.
			var aim_str: String = ""
			if not calibration_done:
				var moon_aa: Dictionary = _moon_alt_az()
				var gaze_alt: float = _alt_from_dir(_gaze_dir())
				if moon_aa.size() > 0:
					aim_str = "\nMoon alt: %.1f Gaze alt: %.1f" % [moon_aa["alt"], gaze_alt]
			_panel.show_object("Star App", "Blend: %s BG: %s\nModes: %s\nHands: %s\nPinches: %d%s" % [blend_str, bg_str, modes_str, hand_str, _pinch_count, aim_str])

func _hand_status(hand_name: String) -> String:
	# v6 diagnostic: is a hand tracker even present, and does
	# it have tracking data? NONE = no tracker at all (extension
	# / runtime issue, not a pinch bug). NO = tracker exists
	# but no data (hands not in view, controllers in hand, or
	# hand tracking off in headset settings). OK = data present.
	# Try the correct path first, then the old path, so the
	# panel tells us which one (if either) the runtime uses.
	var tracker: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/" + hand_name) as XRHandTracker
	if tracker != null:
		return "OK" if tracker.get_has_tracking_data() else "NO"
	var old_tracker: XRHandTracker = XRServer.get_tracker("/user/hand/" + hand_name) as XRHandTracker
	if old_tracker != null:
		return "OK2" if old_tracker.get_has_tracking_data() else "NO2"
	return "NONE"

func _setup_xr() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface == null:
		print("Star App: OpenXR not available here (editor/headless) — continuing without XR.")
		return
	# v5 passthrough, NNR v91 recipe, passthrough FIRST:
	# blend=ALPHA before initialize + transparent viewport +
	# transparent environment (alpha 0 in main.tscn) = room
	# shows through wherever the app draws nothing. NO
	# start_passthrough() call — NNR never called it, and v1-v4
	# calling it did not produce a room, and the FB layer flag
	# it sets is not the compositor passthrough. If v5 is still
	# black with Blend: ALPHA and BG: CLEAR on the panel, the
	# blocker is outside the app (headset passthrough
	# permission / system setting), not this code.
	xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	get_viewport().transparent_bg = true
	if not xr_interface.initialize():
		print("Star App: OpenXR initialize returned false.")
		return
	get_viewport().use_xr = true
	print("Star App: OpenXR initialized, blend ALPHA, transparent_bg true, hands first (no controller required).")

# --- Calibration: saved, once ever ---

func _load_calibration() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CALIBRATION_PATH) != OK:
		return
	yaw_offset_deg = float(cfg.get_value("calibration", "yaw_offset_deg", 0.0))
	calibration_done = bool(cfg.get_value("calibration", "done", false))
	calibration_source = str(cfg.get_value("calibration", "source", ""))
	if calibration_done:
		_apply_yaw()

func _save_calibration() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("calibration", "yaw_offset_deg", yaw_offset_deg)
	cfg.set_value("calibration", "done", true)
	cfg.set_value("calibration", "source", calibration_source)
	cfg.set_value("calibration", "saved_unix", Time.get_unix_time_from_system())
	cfg.save(CALIBRATION_PATH)

func _apply_yaw() -> void:
	if _sky != null:
		_sky.yaw_offset_deg = yaw_offset_deg
	if _planets != null:
		_planets.yaw_offset_deg = yaw_offset_deg

static func _az_from_dir(dir: Vector3) -> float:
	return AstroMathScript.fmod360(rad_to_deg(atan2(dir.x, -dir.z)))

static func _alt_from_dir(dir: Vector3) -> float:
	return rad_to_deg(asin(clamp(dir.y, -1.0, 1.0)))

static func _angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clamp(a.normalized().dot(b.normalized()), -1.0, 1.0)))

# Lock yaw from one real object the user looked at and pinched.
# Returns true only when the altitude check passes — altitude is
# independent of yaw, so a bad altitude means this is not that
# object, or the location/time is wrong, and locking would be wrong.
func calibrate_from_object(predicted_alt_deg: float, predicted_az_deg: float, measured_dir: Vector3, source: String = "") -> bool:
	# v15: altitude tolerance 5° -> 8°. Head tilted back to a
	# high Moon (80°+) makes gaze altitude noisy, and a 5°
	# gate rejected real Moon pinches. 8° still rejects street
	# lights and porch lights by a huge margin (Moon ~70-83°,
	# lights ~0-10°, gap >50°), so the wrong-object protection
	# is intact, just less brittle for a high Moon.
	var alt_meas: float = _alt_from_dir(measured_dir)
	if abs(alt_meas - predicted_alt_deg) > 8.0:
		return false
	var az_meas: float = _az_from_dir(measured_dir)
	var yaw: float = az_meas - predicted_az_deg
	yaw = fmod(yaw + 180.0, 360.0) - 180.0
	yaw_offset_deg = yaw
	calibration_done = true
	calibration_source = source
	_apply_yaw()
	_save_calibration()
	return true

func _moon_alt_az() -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	var lat: float = 28.5496
	var lon: float = -81.7729
	if _sky != null:
		lat = _sky.lat_deg
		lon = _sky.lon_deg
	var radec: Dictionary = AstroMathScript.moon_radec_j2000(jds["tt"], jds["ut1"], lat, lon, true)
	var aa: Dictionary = AstroMathScript.alt_az(radec["ra_h"], radec["dec_deg"], jds["ut1"], lat, lon)
	aa["ra_h"] = radec["ra_h"]
	aa["dec_deg"] = radec["dec_deg"]
	return aa

# --- Pinch handling: gaze selects, pinch confirms ---

func _gaze_dir() -> Vector3:
	if _camera != null:
		return -_camera.global_transform.basis.z
	return Vector3(0, 0, -1)

func _on_pinch(hand_name: String, pinch_point: Vector3) -> void:
	_pinch_count += 1
	# v22 dial tap: pinch on the dial steps zoom, starts a drag,
	# never identifies. Room mode only; dial is hidden otherwise,
	# and hidden before lock, so lock behaviour is unchanged.
	if calibration_done and _planets != null and _planets.focused_body() != "" and _planets.telescope_body() == "" and _planets.travel_body() == "":
		if pinch_point.distance_to(_planets.dial_position()) < 0.35:
			_dial_dragging = true
			_dial_hand = hand_name
			_dial_last_y = pinch_point.y
			_planets.step_zoom()
			if _voice != null:
				_voice.play_sound("sound_click")
			return
	if _voice != null:
		_voice.play_sound("sound_click")
	var gaze: Vector3 = _gaze_dir()
	if not calibration_done:
		_try_calibrate(gaze)
		return
	# v20: REMOVED the v13 re-lock fallback. That fallback is
	# why v19 "kept saying locked" with the lock voice: every
	# pinch that failed to identify (empty sky, room, a dim
	# object) fell through to _try_calibrate, and indoors a
	# head tilt often matched a planet/star altitude within
	# 8°, so it re-locked, played the lock voice, and
	# overwrote the yaw — over and over. Once locked, a
	# pinch now only identifies. If it cannot, it says
	# "Not sure" and nothing else. No re-lock, no lock voice.
	# A bad lock is fixed by uninstall + reinstall, then one
	# real outdoor lock — that is honest, and it cannot
	# happen by accident in the living room again.
	_identify(gaze)

func _on_pinch_drag(hand_name: String, pinch_point: Vector3) -> void:
	# v22 dial drag: held pinch moves zoom smoothly, 1x-10x.
	# Up = zoom in, down = out. Dial/identify/lock untouched.
	if not _dial_dragging or hand_name != _dial_hand:
		return
	if _planets == null or _planets.focused_body() == "" or _planets.telescope_body() != "" or _planets.travel_body() != "":
		_dial_dragging = false
		return
	var dy: float = pinch_point.y - _dial_last_y
	_dial_last_y = pinch_point.y
	_planets.set_zoom(_planets.zoom_factor() + dy * 6.0)

func _on_pinch_release(hand_name: String) -> void:
	if _dial_dragging and hand_name == _dial_hand:
		_dial_dragging = false
		_dial_hand = ""

func _planet_alt_az(name: String) -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	var lat: float = 28.5496
	var lon: float = -81.7729
	if _sky != null:
		lat = _sky.lat_deg
		lon = _sky.lon_deg
	var radec: Dictionary = AstroMathScript.planet_radec_j2000(name, jds["tt"])
	var of_date: Dictionary = AstroMathScript.precess_j2000_to_of_date(radec["ra_h"], radec["dec_deg"], jds["tt"])
	var aa: Dictionary = AstroMathScript.alt_az(of_date["ra_h"], of_date["dec_deg"], jds["ut1"], lat, lon)
	aa["ra_h"] = radec["ra_h"]
	aa["dec_deg"] = radec["dec_deg"]
	return aa

func _try_calibrate(gaze: Vector3) -> void:
	# v20 guard: never re-lock if already locked, even if a
	# future code path calls this by mistake. Lock voice
	# only ever fires from a first lock, never repeatedly.
	if calibration_done:
		return
	# First choice: the Moon, if it is above the horizon.
	var moon: Dictionary = _moon_alt_az()
	if moon["alt"] > 0.0:
		if calibrate_from_object(moon["alt"], moon["az"], gaze, "Moon"):
			if _panel != null:
				_panel.show_calibrated_from("Moon")
			if _voice != null:
				_voice.play_sound("sound_lock")
				_voice.play_voice("voice_sky_locked")
			return
		# Moon is up but the gaze altitude does not match it — the
		# user may be pinching a planet or a star instead.
	# v13 Mars lock: planets are calibration candidates too,
	# same alt check as the Moon, same yaw-from-az math.
	# Mars first (the user's case), then the other bright
	# planets. Sun is deliberately excluded — never lock
	# from the Sun, and never ask the user to look at it.
	for planet_name: String in ["Mars", "Jupiter", "Saturn", "Venus", "Mercury"]:
		var paa: Dictionary = _planet_alt_az(planet_name)
		if paa["alt"] > 0.0 and calibrate_from_object(paa["alt"], paa["az"], gaze, planet_name):
			if _panel != null:
				_panel.show_calibrated_from(planet_name)
			if _voice != null:
				_voice.play_sound("sound_lock")
				_voice.play_voice("voice_sky_locked")
			return
	# Fallback: a bright named star the user is looking at.
	if _sky != null:
		var best: Dictionary = _closest_named_star(gaze)
		if best.has("name"):
			var aa: Dictionary = _sky.star_alt_az_by_name(best["name"])
			if aa.size() > 0 and calibrate_from_object(aa["alt"], aa["az"], gaze, best["name"]):
				if _panel != null:
					_panel.show_calibrated_from(best["name"])
				if _voice != null:
					_voice.play_sound("sound_lock")
					_voice.play_voice("voice_sky_locked")
				return
	if _panel != null:
		_panel.show_not_sure()
	if _voice != null:
		_voice.play_voice("voice_not_sure")

func _closest_named_star(gaze: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_angle: float = 2.5
	for item: Dictionary in _sky.named_star_directions():
		var ang: float = _angle_between(gaze, item["dir"])
		if ang < best_angle:
			best_angle = ang
			best = item
	return best

func _identify(gaze: Vector3) -> bool:
	# v19 room check FIRST: if a body or star orb is already
	# in the room, and gaze points at it, identify it — even
	# if its sky direction is elsewhere. This fixes the v18
	# video defect: planet in room + "Not sure" panel, because
	# the old code only checked sky directions, never the
	# room position the user was actually looking at.
	# Threshold 0.44 rad (~25°): bring-to-you planets are
	# ~19° wide, telescope planets fill the view, so 25°
	# catches a centre look without catching the whole sky.
	if _camera != null and _planets != null:
		var fb: String = _planets.focused_body()
		if fb != "":
			var fnode: Node = _planets.get_node_or_null(fb)
			if fnode != null:
				var rdir: Vector3 = (fnode.global_position - _camera.global_position).normalized()
				if _angle_between(gaze, rdir) < 0.44:
					select_object(fb)
					_show_panel_for({"name": fb, "kind": "body"})
					if _teacher != null:
						_teacher.ask_about_selected(fb)
					return true
	if _camera != null and _star_orb != null and _star_orb_name != "":
		var sdir: Vector3 = (_star_orb.global_position - _camera.global_position).normalized()
		if _angle_between(gaze, sdir) < 0.44:
			var sentry: Dictionary = _sky.named_star_entry(_star_orb_name) if _sky != null else {}
			select_object(_star_orb_name)
			_show_panel_for({"name": _star_orb_name, "kind": "star", "entry": sentry})
			return true
	# Collect candidates: planets/Moon/Sun, then named stars.
	var candidates: Array = []
	if _planets != null:
		for name: String in _planets.body_directions().keys():
			candidates.append({"name": name, "dir": _planets.body_directions()[name], "kind": "body"})
	if _sky != null:
		for item: Dictionary in _sky.named_star_directions():
			candidates.append({"name": item["name"], "dir": item["dir"], "kind": "star", "entry": item["entry"]})
	var best: Dictionary = {}
	var best_angle: float = 2.5
	var second_angle: float = 999.0
	for c: Dictionary in candidates:
		var ang: float = _angle_between(gaze, c["dir"])
		if ang < best_angle:
			second_angle = best_angle
			best_angle = ang
			best = c
		elif ang < second_angle:
			second_angle = ang
	if best.is_empty():
		if _panel != null:
			_panel.show_not_sure()
		if _voice != null:
			_voice.play_voice("voice_not_sure")
		return false
	if second_angle - best_angle < 1.0:
		# Two objects almost equally close — guessing would be worse
		# than saying not sure.
		if _panel != null:
			_panel.show_not_sure()
		if _voice != null:
			_voice.play_voice("voice_not_sure")
		return false
	select_object(best["name"])
	_show_panel_for(best)
	if _teacher != null:
		_teacher.ask_about_selected(best["name"])
	return true

func _on_teacher_answer(_object_name: String, answer: String, source_label: String) -> void:
	if _panel != null:
		_panel.show_teacher(answer, source_label)

func _show_panel_for(obj: Dictionary) -> void:
	if _panel == null:
		return
	var name: String = obj["name"]
	var detail: String = ""
	if obj["kind"] == "body":
		_clear_star_orb()
		# v17 travel flow, no icon UI yet (keeps us moving):
		# 1st pinch = describe + bring to you.
		# 2nd pinch on the SAME body = telescope zoom.
		# 3rd pinch = rover travel (Mars only, real panorama).
		# 4th pinch = back to your room, body back in sky.
		# Non-Mars bodies: 3rd pinch = back to room/sky.
		# The real telescope/travel icons replace the pinch
		# sequence in a later build; the behaviour is here.
		var already_focused: bool = _planets != null and _planets.focused_body() == name
		var in_telescope: bool = _planets != null and _planets.telescope_body() == name
		var in_travel: bool = _planets != null and _planets.travel_body() == name
		if already_focused and in_travel:
			if _planets != null:
				_planets.clear_travel()
				_planets.clear_focus()
			selected_object = ""
			if _voice != null:
				_voice.play_sound("sound_back")
				_voice.play_voice("voice_back_room")
			detail = name + "\nBack in your room\nPinch again to bring it back"
		elif already_focused and in_telescope:
			if _planets != null and _planets.has_travel(name):
				_planets.set_travel(name)
				if _voice != null:
					_voice.play_sound("sound_travel")
					_voice.play_voice("voice_rover_travel")
				detail = "Mars\nROVER TRAVEL — real panorama\nCuriosity, Rocknest, Gale Crater\nOct-Nov 2012, NASA/JPL-Caltech/MSSS\nNot live — pinch again to go back"
			else:
				if _planets != null:
					_planets.clear_focus()
				selected_object = ""
				if _voice != null:
					_voice.play_sound("sound_back")
					_voice.play_voice("voice_back_room")
				detail = name + "\nBack in your room\nPinch a planet to bring it back"
		elif already_focused:
			if _planets != null:
				_planets.set_telescope(name)
			if _voice != null:
				_voice.play_sound("sound_zoom")
			if _planets != null and _planets.has_travel(name):
				if _voice != null:
					_voice.play_voice("voice_telescope_real")
				detail = name + "\nTELESCOPE — real scan\nRotation: time-lapse, 1 sec = 10 min\nNext: [Travel] - pinch again for rover travel"
			elif _planets != null and _planets.is_real_scan(name):
				if _voice != null:
					_voice.play_voice("voice_telescope_real")
				detail = name + "\nTELESCOPE — real scan\nRotation: time-lapse, 1 sec = 10 min\nNext: [Back] - pinch again to go back"
			else:
				if _voice != null:
					_voice.play_voice("voice_telescope_sim")
				detail = name + "\nTELESCOPE — simulated\nNo rover here — model from real science\nRotation: time-lapse, 1 sec = 10 min\nNext: [Back] - pinch again to go back"
		else:
			if _planets != null:
				_planets.clear_travel()
				_planets.select_body(name)
			if _voice != null:
				_voice.play_voice("voice_" + name.to_lower() + "_in_room")
			# v18 storm facts, real places only, not invented storms.
			var storm: String = ""
			if name == "Jupiter":
				storm = "\nGreat Red Spot, storm at 20° south, bigger than Earth"
			elif name == "Saturn":
				storm = "\nHexagon jet at north pole, Great White Spot every ~30 years"
			elif name == "Mars":
				storm = "\nDust storms, global in dust season, can cover the planet"
			elif name == "Neptune":
				storm = "\nDark storms, fastest winds, over 2,000 km/h"
			elif name == "Venus":
				storm = "\nClouds circle in 4 Earth days, faster than the planet"
			var jds: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
			if name == "Moon":
				var aa: Dictionary = _moon_alt_az()
				detail = "Moon\nRA %.2fh Dec %.2f°\nAlt %.1f° Az %.1f°\nNext: [Telescope] - pinch again" % [aa["ra_h"], aa["dec_deg"], aa["alt"], aa["az"]]
			else:
				# planet_radec_j2000 handles "Sun" itself (opposite Earth).
				var radec: Dictionary = AstroMathScript.planet_radec_j2000(name, jds["tt"])
				detail = "%s\nRA %.2fh Dec %.2f°%s\nNext: [Telescope] - pinch again" % [name, radec["ra_h"], radec["dec_deg"], storm]
	else:
		var entry: Dictionary = obj["entry"]
		var aa: Dictionary = _sky.star_alt_az_by_name(name) if _sky != null else {}
		# v16: all stars — panel now carries the real science
		# from HYG v41, not just mag/RA/Dec. Distance in light
		# years = parsecs × 3.26156. Stars are NOT textured
		# surfaces — their look is colour + light, so the orb
		# in your room is a glowing sphere in the star's real
		# spectral colour, sized by brightness, not a fake
		# surface texture. Second pinch on the same star
		# removes the orb again.
		var dist_ly: float = float(entry.get("dist_pc", 0.0)) * 3.26156
		var con: String = str(entry.get("con", ""))
		var spect: String = str(entry.get("spect", ""))
		var con_str: String = (" in " + con) if con != "" else ""
		var spect_str: String = (" " + spect) if spect != "" else ""
		if _star_orb_name == name and _star_orb != null:
			_clear_star_orb()
			detail = "%s\nStar orb back in the sky" % name
		else:
			_show_star_orb(entry)
			detail = "%s%s%s, mag %.1f\n%.0f light years away\nRA %.2fh Dec %.2f°\nAlt %.1f° Az %.1f°\nPinch again to put it back" % [name, con_str, spect_str, entry.get("mag", 0.0), dist_ly, entry.get("ra_h", 0.0), entry.get("dec_deg", 0.0), aa.get("alt", 0.0), aa.get("az", 0.0)]
	_panel.show_object(name, detail)

func _show_star_orb(entry: Dictionary) -> void:
	_clear_star_orb()
	var orb: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	# Brighter = bigger orb. Mag -1.44 (Sirius) -> 0.30 m,
	# mag 6 -> 0.06 m. Same scale logic as sky points, larger
	# so it reads as an object in the room, not a dot.
	var r: float = clamp(0.30 - float(entry.get("mag", 3.0)) * 0.04, 0.06, 0.45)
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	orb.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var col: Color = entry.get("color", Color(1.0, 1.0, 1.0))
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb.material_override = mat
	# v19 orb glow: a star is light, not a solid ball. A
	# larger transparent shell in the same colour, child of
	# the orb so clearing the orb clears the glow too.
	var glow: MeshInstance3D = MeshInstance3D.new()
	var gsphere: SphereMesh = SphereMesh.new()
	gsphere.radius = r * 2.5
	gsphere.height = r * 5.0
	gsphere.radial_segments = 16
	gsphere.rings = 8
	glow.mesh = gsphere
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.albedo_color = Color(col.r, col.g, col.b, 0.20)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = gmat
	orb.add_child(glow)
	orb.position = Vector3(0.0, 0.0, -3.0)
	add_child(orb)
	_star_orb = orb
	_star_orb_name = str(entry.get("name", ""))

func _clear_star_orb() -> void:
	if _star_orb != null:
		_star_orb.queue_free()
		_star_orb = null
	_star_orb_name = ""

# Kept for the teacher step: records the selection, and for a
# body also brings it to the user in passthrough.
func select_object(object_name: String) -> void:
	selected_object = object_name
	print("Star App: selected ", object_name)
