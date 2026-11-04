# ============================================================
# EXPERIMENTAL SKY LOCK v2 — RESEARCH ONLY. NOT WIRED IN.
# Added 2026-10-28 for JOB 4 (find a solid lock mechanism).
#
# This file is NOT referenced by scenes/main.tscn, scripts/main.gd,
# or any other live code. Nothing here runs in the app. The live
# lock (main.gd calibrate_from_object + user:// cfg save) is
# UNTOUCHED and keeps working exactly as before.
#
# Needs NO new permission, NO new sensor, NO network call: pure
# math over gaze directions the app already measures, plus a
# read-only look at the existing saved lock. Location handling is
# untouched — nothing here sends anything anywhere.
# ============================================================
extends RefCounted

# Two sights must agree within this, or there is no lock at all
# (saying "not sure" beats locking to the wrong object).
const AGREE_TOLERANCE_DEG: float = 4.0
# Recenter step: beyond this drift the saved lock should be redone.
const DRIFT_RELOCK_DEG: float = 3.0

static func _wrap360(x: float) -> float:
	var r: float = fmod(x, 360.0)
	if r < 0.0:
		r += 360.0
	return r

static func ang_diff_deg(a: float, b: float) -> float:
	return _wrap360(a - b + 180.0) - 180.0

# One sight: yaw that would put the predicted azimuth where the
# user actually looked. Same relation the live lock uses.
static func yaw_from_sight(az_meas_deg: float, az_pred_deg: float) -> float:
	return ang_diff_deg(az_meas_deg, az_pred_deg)

# Two sights (Moon + a bright star/planet, or any pair): lock only
# if both sights vote the same yaw. Returns {"ok", "yaw_deg",
# "disagreement_deg"}. A wrongly-pinched object fails the altitude
# gate first (live code); if it slips through, it fails HERE by
# disagreeing with the other sight — never a silent wrong lock.
static func solve_yaw_two_sight(az_meas_1: float, az_pred_1: float, az_meas_2: float, az_pred_2: float, tolerance_deg: float = AGREE_TOLERANCE_DEG) -> Dictionary:
	var y1: float = yaw_from_sight(az_meas_1, az_pred_1)
	var y2: float = yaw_from_sight(az_meas_2, az_pred_2)
	var disagreement: float = absf(ang_diff_deg(y1, y2))
	if disagreement > tolerance_deg:
		return {"ok": false, "yaw_deg": 0.0, "disagreement_deg": disagreement}
	# Circular mean (safe for small separations): base + half the
	# wrapped delta, re-wrapped to [-180, 180).
	var yaw: float = _wrap360(y1 + ang_diff_deg(y2, y1) * 0.5 + 180.0) - 180.0
	return {"ok": true, "yaw_deg": yaw, "disagreement_deg": disagreement}

# Drift recenter check: face a known reference (e.g. Polaris / true
# north) and pinch; compare the fresh yaw against the saved lock.
# Small drift = keep the saved lock, large = re-lock outdoors.
# Returns {"drift_deg", "needs_relock"}. Advisory only.
static func check_drift(saved_yaw_deg: float, measured_yaw_deg: float, threshold_deg: float = DRIFT_RELOCK_DEG) -> Dictionary:
	var drift: float = absf(ang_diff_deg(measured_yaw_deg, saved_yaw_deg))
	return {"drift_deg": drift, "needs_relock": drift > threshold_deg}

# Read-only look at the EXISTING saved lock (same keys the live
# code writes). Never writes, never deletes, never migrates.
# Returns {"done", "yaw_deg", "source", "saved_unix"}.
static func read_saved_lock(path: String) -> Dictionary:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return {"done": false, "yaw_deg": 0.0, "source": "", "saved_unix": 0.0}
	return {
		"done": bool(cfg.get_value("calibration", "done", false)),
		"yaw_deg": float(cfg.get_value("calibration", "yaw_offset_deg", 0.0)),
		"source": str(cfg.get_value("calibration", "source", "")),
		"saved_unix": float(cfg.get_value("calibration", "saved_unix", 0.0)),
	}

# Cloudy nights: there is no first lock without a real object, so
# any future cloudy/demo path MUST label itself with exactly this.
# A saved lock from a clear night may be reused (labelled "saved"),
# but a first lock is never faked.
static func demo_label() -> String:
	return "Demo sky — NOT locked (clouds). Real lock needs one pinch on the real Moon or a bright star."
