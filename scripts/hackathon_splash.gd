# Hackathon splash, added 2026-10-29, user-approved final logo.
# Fixed 2026-10-29 after vc47 headset test (user verdict):
# - Logo sometimes showed, sometimes did not, and spawned in the wrong place.
#   Root cause: splash was a world node, positioned from camera global
#   transform once per frame, starting at world origin before XR camera
#   moved. If the user was not looking at world origin, it was out of view.
#   Fix: sprite is now a CHILD of the XRCamera itself, at local (0,0,-1.2),
#   so it is always in your face, wherever you look, not too close,
#   and never world-fixed. It cannot spawn in the wrong place now.
# - Timing was too quick, no fade in. Fix: fade IN 1 s, wait 4 s, fade OUT 1 s.
#   Total 6 s per logo, then free itself. Pinch NEVER dismisses splash
#   (vc48 fix, main.gd): it always runs its full timing.
# vc112 SPLASH SEQUENCE ONLY: official Star Bridge logo FIRST (6 s),
# then hackathon logo SECOND (6 s), total 12 s, then sky. No words,
# no menus, no buttons. Glimmer stars are hackathon-logo only, because
# their positions were laid out for that 1080px logo, not the official logo.
# - Logo 1: res://data/splash/star_bridge_official_logo.png — official app
#   logo JPG (white background) converted with PIL: near-white -> alpha,
#   ramp 200..245 on min channel, dark blue/cyan logo survives, 750x750.
#   No dark quad, no white square: passthrough is the background.
# - Logo 2: res://data/hackathon-logo-transparent.png (final v3)
extends Node3D

const LOGO_PATH: String = "res://data/hackathon-logo-transparent.png"
const OFFICIAL_LOGO_PATH: String = "res://data/splash/star_bridge_official_logo.png"
const FADE_IN_SECONDS: float = 1.0
const HOLD_SECONDS: float = 4.0
const FADE_OUT_SECONDS: float = 1.0

var _sprite: Sprite3D = null
var _camera: XRCamera3D = null
var _start_unix: float = 0.0
var _dismissed: bool = false
var _glimmers: Array = []
var _phase: int = 0  # vc112: 0 = official logo, 1 = hackathon logo

func _ready() -> void:
	_start_unix = Time.get_unix_time_from_system()
	_sprite = Sprite3D.new()
	# vc152 Star Bridge logo farther: 1.8 m out (was 1.2 m, too close).
	# Scale up by 1.8/1.2 so it looks the same size, just farther away:
	# 750 * 0.002 * 1.185 = 1.78 m wide at 1.8 m, same angle as before.
	_sprite.texture = load(OFFICIAL_LOGO_PATH)
	_sprite.pixel_size = 0.002
	_sprite.scale = Vector3(1.185, 1.185, 1.185)
	_sprite.visible = false
	add_child(_sprite)
	# vc152: no glimmers — twinkling stars removed, see header.

func _create_glimmers() -> void:
	var width_m: float = 1.188
	for gx in [100, 200, 300, 400, 500, 600, 700, 800, 900]:
		for gy in [400, 500, 600, 700, 800]:
			if gx > 120 and gx < 620 and gy > 430 and gy < 660:
				continue
			if gx > 700 and gx < 800 and gy > 500 and gy < 600:
				continue
			var lab: Label3D = Label3D.new()
			lab.text = "✦"
			lab.font_size = 24
			lab.pixel_size = 0.0015
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.modulate = Color(1.0, 1.0, 1.0, 1.0)
			lab.position = Vector3((float(gx) - 540.0) / 1080.0 * width_m, -(float(gy) - 540.0) / 1080.0 * width_m, 0.01)
			_sprite.add_child(lab)
			_glimmers.append({"node": lab, "phase": float(gx + gy) * 0.37, "speed": 1.5 + float((gx * gy) % 10) * 0.2})

func _set_glimmers_visible(v: bool) -> void:
	for g: Dictionary in _glimmers:
		(g["node"] as Label3D).visible = v

func set_camera(camera: XRCamera3D) -> void:
	_camera = camera
	if _sprite != null and camera != null:
		# Move sprite under the camera, so it follows head direction exactly, every frame, no _process positioning needed.
		_sprite.get_parent().remove_child(_sprite)
		camera.add_child(_sprite)
		_sprite.position = Vector3(0.0, 0.0, -1.8)  # vc152 Star Bridge logo farther
		_sprite.visible = true
		# Restart timing at camera attach, so fade-in starts when it is actually in front of the user, not at app boot before XR moves.
		_start_unix = Time.get_unix_time_from_system()

func is_active() -> bool:
	# vc125: true until both logos (12s total) are done and the sprite is freed.
	return _sprite != null and not _dismissed

func dismiss() -> void:
	_dismissed = true
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null

func _process(_delta: float) -> void:
	if _dismissed or _sprite == null or not _sprite.visible:
		return
	var elapsed: float = Time.get_unix_time_from_system() - _start_unix
	var total: float = FADE_IN_SECONDS + HOLD_SECONDS + FADE_OUT_SECONDS
	if elapsed > total:
		if _phase == 0:
			# vc112: official logo done -> hackathon logo, same 1/4/1 timing.
			_phase = 1
			_sprite.texture = load(LOGO_PATH)
			# 1080 * 0.002 * 0.55 = 1.188 m wide, as before, at 1.2 m (unchanged).
			_sprite.scale = Vector3(0.55, 0.55, 0.55)
			_sprite.position = Vector3(0.0, 0.0, -1.2)
			_start_unix = Time.get_unix_time_from_system()
			return
		dismiss()
		return
	var logo_alpha: float = 1.0
	if elapsed < FADE_IN_SECONDS:
		logo_alpha = elapsed / FADE_IN_SECONDS
	elif elapsed > FADE_IN_SECONDS + HOLD_SECONDS:
		logo_alpha = 1.0 - (elapsed - FADE_IN_SECONDS - HOLD_SECONDS) / FADE_OUT_SECONDS
	_sprite.modulate = Color(1.0, 1.0, 1.0, clamp(logo_alpha, 0.0, 1.0))
	# vc152: no glimmer animation — twinkling stars removed.
