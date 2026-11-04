# Fresh hand-tracking pinch, written 2026-10-26.
# Pinch = thumb tip and index tip close together, on either hand.
# Uses XRHandTracker joint transforms (Godot 4.3, OpenXR hand
# tracking), NOT controllers. Controllers remain optional and are
# never required. Gaze selects, pinch confirms: the pinch signal
# carries no object itself — Main decides what the user was
# looking at when the pinch happened. That keeps a wrong pinch
# from naming a wrong object.
# In-headset note: joint transforms are in origin space, so the
# pinch point is transformed by the XROrigin. If the headset
# reports a different frame, the in-headset verdict is the proof.
extends Node3D

signal pinch_detected(hand_name: String, pinch_point: Vector3)
# v22 dial drag: emitted while a pinch is held (every frame),
# and once on release. Calibration / identify only listen to
# pinch_detected, so these new signals cannot change lock or
# identify behaviour — Main uses them for the zoom dial only.
signal pinch_drag_detected(hand_name: String, pinch_point: Vector3)
signal pinch_released(hand_name: String)
signal grab_started(hand_name: String, grab_point: Vector3)
signal grab_drag_detected(hand_name: String, grab_point: Vector3)
signal grab_released(hand_name: String)

const THUMB_TIP: int = 5
const INDEX_TIP: int = 10
# v15 pinch fix — user 2026-10-27: "pinches aren't fully functional yet".
# 0.035 m was too tight for noisy low-light tracking (dark backyard,
# head tilted back to a high Moon): tips jitter around the threshold
# and a real pinch never crosses it, or flickers. 0.045 m on, 0.055 m
# off (hysteresis) is still a real thumb-index pinch, not a grab,
# and survives jitter. Per-hand cooldown, not global: the old global
# 0.5 s cooldown returned from _process entirely, so a second hand's
# pinch inside that window was dropped, and _pinching flags were
# never cleared while cooling down.
# vc69 STRICT PINCH, user 2026-10-29 22:17 video: 'it should only pinch once these two fingers touch each other'.
# Old 0.045m fired when a hand was just raised, fingers apart but relaxed, so planets showed up before any pinch and jumped.
# New: touch only (<0.025m), release at >0.035m, and re-arm only after a WIDE open (>0.080m), so a relaxed hand never re-arms.
const PINCH_DISTANCE_M: float = 0.025
const PINCH_RELEASE_M: float = 0.035
const PINCH_ARM_M: float = 0.080
const PINCH_COOLDOWN_S: float = 0.5
# Trippy hand outline: one shared rim-glow material painted onto the
# real hand meshes (OpenXRHand children), so the hands you use for
# everything trace light. Pinch thresholds above are untouched.
const HAND_GLOW_SHADER: Shader = preload("res://scripts/hand_glow.gdshader")

var _pinching: Dictionary = {"left": false, "right": false}
var _grabbing: Dictionary = {"left": false, "right": false}
var _seen_open_grab: Dictionary = {"left": false, "right": false}
var _seen_open: Dictionary = {"left": false, "right": false}
var _start_unix: float = 0.0
var _last_pinch_unix: Dictionary = {"left": -10.0, "right": -10.0}
var _glow_mat: ShaderMaterial = null
var _hand_nodes: Array = []
var _glow_tick: float = 1.0

func _ready() -> void:
	_start_unix = Time.get_unix_time_from_system()
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = HAND_GLOW_SHADER
	var main: Node = get_parent()
	if main != null:
		for h: String in ["LeftHand", "RightHand"]:
			var hn: Node = main.get_node_or_null("XROrigin/" + h)
			if hn != null:
				_hand_nodes.append(hn)

func _paint_hands() -> void:
	# OpenXRHand rebuilds its meshes; repaint anything unpainted.
	if _glow_mat == null:
		return
	for hn: Variant in _hand_nodes:
		if not is_instance_valid(hn):
			continue
		var meshes: Array = (hn as Node).find_children("*", "MeshInstance3D", true, false)
		for mi: Variant in meshes:
			if (mi as MeshInstance3D).material_override != _glow_mat:
				(mi as MeshInstance3D).material_override = _glow_mat

func _process(_delta: float) -> void:
	_glow_tick += _delta
	if _glow_tick >= 0.5:
		_glow_tick = 0.0
		_paint_hands()
	var now: float = Time.get_unix_time_from_system()
	for hand_name: String in ["left", "right"]:
		# vc68 GRAB, not pinch: a fist (all four fingertips close to palm) grabs a planet.
		# Pinch is thumb+index only; a fist must NOT also fire a pinch/identify, or grabbing jumps planets.
		var grab_pt: Vector3 = grab_point(hand_name)
		var grab_max: float = grab_max_tip_dist(hand_name)
		if grab_max >= 0.0:
			if grab_max >= 0.13:
				_seen_open_grab[hand_name] = true
			if grab_max < 0.10 and not _grabbing[hand_name]:
				if _seen_open_grab[hand_name] and now - _start_unix >= 2.0 and grab_pt != Vector3.ZERO:
					_grabbing[hand_name] = true
					grab_started.emit(hand_name, grab_pt)
			elif _grabbing[hand_name] and grab_max < 0.13:
				grab_drag_detected.emit(hand_name, grab_pt)
			elif _grabbing[hand_name] and grab_max >= 0.13:
				_grabbing[hand_name] = false
				grab_released.emit(hand_name)
		if _grabbing[hand_name]:
			continue
		var dist: float = pinch_distance(hand_name)
		if dist < 0.0:
			# vc69: tracking lost — reset, so a reappearing hand cannot fire a stale pinch, and must be seen wide open first.
			if _pinching[hand_name]:
				_pinching[hand_name] = false
				pinch_released.emit(hand_name)
			_seen_open[hand_name] = false
			continue
		# vc60: no auto-pinch on open. A hand must first be seen OPEN, and
		# 2s must pass since app start, before any pinch counts. Otherwise
		# a hand that starts closed fires a "random planet" on open, without
		# the user pinching at all — exactly the vc59 video defect.
		if dist >= PINCH_ARM_M:
			_seen_open[hand_name] = true
		if dist < PINCH_DISTANCE_M and not _pinching[hand_name]:
			if not _seen_open[hand_name] or now - _start_unix < 2.0:
				continue
			if now - _last_pinch_unix[hand_name] < PINCH_COOLDOWN_S:
				continue
			_pinching[hand_name] = true
			_seen_open[hand_name] = false
			_last_pinch_unix[hand_name] = now
			var pt: Vector3 = pinch_point(hand_name)
			pinch_detected.emit(hand_name, pt)
		elif dist >= PINCH_RELEASE_M:
			if _pinching[hand_name]:
				_pinching[hand_name] = false
				pinch_released.emit(hand_name)
		elif _pinching[hand_name]:
			# Held pinch: drag point for the zoom dial only.
			pinch_drag_detected.emit(hand_name, pinch_point(hand_name))

func _tracker(hand_name: String) -> XRHandTracker:
	# v8 fix — v7 verdict: Hands L:NONE R:NONE. Root cause:
	# Godot 4.3 hand trackers live at /user/hand_tracker/left
	# and /user/hand_tracker/right (Godot docs + demo project),
	# NOT /user/hand/left. The old path always returned null,
	# so pinch never fired and the diagnostic reported NONE
	# even if the runtime had hand tracking. This was a code
	# bug, not a runtime failure.
	var tracker: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/" + hand_name) as XRHandTracker
	if tracker != null:
		return tracker
	return XRServer.get_tracker("/user/hand/" + hand_name) as XRHandTracker

func pinch_distance(hand_name: String) -> float:
	# -1 when no hand tracking data is available (headless, or
	# hands not tracked). Never fake a pinch from missing data.
	var tracker: XRHandTracker = _tracker(hand_name)
	if tracker == null or not tracker.get_has_tracking_data():
		return -1.0
	var thumb_flags: int = tracker.get_hand_joint_flags(THUMB_TIP)
	var index_flags: int = tracker.get_hand_joint_flags(INDEX_TIP)
	if (thumb_flags & 8) == 0 or (index_flags & 8) == 0:
		return -1.0
	var thumb: Vector3 = tracker.get_hand_joint_transform(THUMB_TIP).origin
	var index: Vector3 = tracker.get_hand_joint_transform(INDEX_TIP).origin
	return thumb.distance_to(index)

func pinch_point(hand_name: String) -> Vector3:
	var tracker: XRHandTracker = _tracker(hand_name)
	if tracker == null:
		return Vector3.ZERO
	var thumb: Vector3 = tracker.get_hand_joint_transform(THUMB_TIP).origin
	var index: Vector3 = tracker.get_hand_joint_transform(INDEX_TIP).origin
	var mid: Vector3 = (thumb + index) * 0.5
	# Joint transforms are in origin space; apply the XROrigin's
	# transform so the point is in world space.
	var main: Node = get_parent()
	if main != null:
		var origin: Node3D = main.get_node_or_null("XROrigin") as Node3D
		if origin != null:
			return origin.global_transform * mid
	return mid


func grab_max_tip_dist(hand_name: String) -> float:
	var tracker: XRHandTracker = _tracker(hand_name)
	if tracker == null or not tracker.get_has_tracking_data():
		return -1.0
	var palm_flags: int = tracker.get_hand_joint_flags(0)
	if (palm_flags & 8) == 0:
		return -1.0
	var palm: Vector3 = tracker.get_hand_joint_transform(0).origin
	var maxd: float = 0.0
	for tip: int in [10, 15, 20, 25]:
		var f: int = tracker.get_hand_joint_flags(tip)
		if (f & 8) == 0:
			return -1.0
		var d: float = tracker.get_hand_joint_transform(tip).origin.distance_to(palm)
		if d > maxd:
			maxd = d
	return maxd

func grab_point(hand_name: String) -> Vector3:
	var tracker: XRHandTracker = _tracker(hand_name)
	if tracker == null:
		return Vector3.ZERO
	var palm: Vector3 = tracker.get_hand_joint_transform(0).origin
	var main: Node = get_parent()
	if main != null:
		var origin: Node3D = main.get_node_or_null("XROrigin") as Node3D
		if origin != null:
			return origin.global_transform * palm
	return palm

# Headless / test hook: emit a pinch without a hand.
func test_pinch(hand_name: String = "right", point: Vector3 = Vector3.ZERO) -> void:
	pinch_detected.emit(hand_name, point)
