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
const PINCH_DISTANCE_M: float = 0.045
const PINCH_RELEASE_M: float = 0.055
const PINCH_COOLDOWN_S: float = 0.5

var _pinching: Dictionary = {"left": false, "right": false}
var _last_pinch_unix: Dictionary = {"left": -10.0, "right": -10.0}

func _process(_delta: float) -> void:
	var now: float = Time.get_unix_time_from_system()
	for hand_name: String in ["left", "right"]:
		var dist: float = pinch_distance(hand_name)
		if dist < 0.0:
			continue
		if dist < PINCH_DISTANCE_M and not _pinching[hand_name]:
			if now - _last_pinch_unix[hand_name] < PINCH_COOLDOWN_S:
				continue
			_pinching[hand_name] = true
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

# Headless / test hook: emit a pinch without a hand.
func test_pinch(hand_name: String = "right", point: Vector3 = Vector3.ZERO) -> void:
	pinch_detected.emit(hand_name, point)
