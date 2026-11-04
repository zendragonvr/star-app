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
var _saved_lock_available: bool = false
var _saved_lock_source: String = ""
var _fail_streak: int = 0
var calibration_source: String = ""
var yaw_offset_deg: float = 0.0
var alt_offset_deg: float = 0.0  # vc78 PRECISE: height correction, set by Moon lock pinch, clamped to +-10deg
var _desc_playing: bool = false

var _sky: Node = null
var _planets: Node = null
var _atlas: Node = null
var _iss: Node = null  # vc131 ISS
var _iss_interior: Node = null  # vc153 ISS interior
var _iss_travelling: bool = false  # vc153 ISS travel
var _earth: Node = null  # vc146 Earth model
var _voice_teacher_object: String = ""  # vc131: object actually asked, for answer matching
var _listen_start_unix: float = -1.0  # vc134: auto-send after 6s listening
var _listen_panel_last: float = 0.0
var _atlas_system: Node = null
var _atlas_last_update: float = 0.0
var _iss_last_update: float = 0.0  # vc133: ISS needs its OWN timer, not atlas's
var _ride_scene: Node = null
var _pinch_hold_start: Dictionary = {}
var _panel: Node = null
var _hands: Node = null
var _voice: Node = null
var _sfx: AudioStreamPlayer = null
var _teacher: Node = null
var _teacher_speech: Node = null
var _camera: XRCamera3D = null
var _pt_reported: bool = false
var _ready_unix: float = 0.0
var _pinch_count: int = 0
var _last_diag_unix: float = 0.0
var _star_orb: MeshInstance3D = null
var _star_orb_name: String = ""
# vc72 TEMPORARY DEBUG NUMBERS (user 2026-10-29 23:18 EDT: so I can see where he is looking in the recording).
# A small top-left numbers panel, always on in this test build ONLY. It shows LOOK az/alt (headset gaze, app space)
# and MOON true az/alt (astro math, Clermont, headset clock, independent of headset facing).
# When he faces the REAL Moon, LOOK should equal MOON true if aligned; the difference between the two
# numbers in the SAME video frame is the sky shift, in degrees. Remove this whole block before demo/submission.
var _debug_label: Label3D = null
var _travel_label: Label3D = null  # vc91 TRAVEL BUTTON: above a brought planet, pinch it to travel, pinch BACK to return
var _travel_button: MeshInstance3D = null  # vc93: real rectangle button behind the TRAVEL/BACK words, highlights on hover
var _travel_button_mat: StandardMaterial3D = null
var _talk_label: Label3D = null  # vc121 TALK TO TEACHER BUTTON: visible, TRAVEL-style light-up
var _talk_button: MeshInstance3D = null
var _talk_button_mat: StandardMaterial3D = null
var _loc_label: Label3D = null
var _loc_button: MeshInstance3D = null
var _loc_button_mat: StandardMaterial3D = null
var _loc_perm_requested: bool = false  # vc155: location asked via system dialog once, like mic — never a button in view
var _perm_boot_stage: int = 0  # vc159 permissions BEFORE logos: 0=not started, 1=mic requested, 2=location requested, 3=done/splash ready
var _perm_boot_time: float = -1.0
var _splash_created: bool = false
var _talk_hovered: bool = false
var _voice_teacher_pending: bool = false  # vc121: only a voice-asked teacher answer goes on screen
var _voice_heard: String = ""  # vc125: exact transcribed words, shown before acting
var _debug_acc: float = 0.0
# vc73 APPLYING LOCK (test only): first pinch = lock, not identify. User faces Moon direction from Star Chart phone (cloudy-proof, no need to see Moon), pinches, app sets yaw_offset = LookAz - MoonAz, so virtual Moon moves to where he is facing. Subsequent pinches identify normally. Restart app to re-lock.
var _debug_locked: bool = false  # vc176 SUN LOCK (user 2026-11-03, park demo): first pinch while facing the Sun locks the sky. Replaces vc174 north lock. No button, no words, no gate - see _on_pinch top.
var _sync_choice: String = ""  # vc150 Real Time Star Sync: "" = not chosen, "moon" or "north"
var _sync_title: Label3D = null
var _sync_moon_label: Label3D = null
var _sync_moon_button: MeshInstance3D = null
var _sync_moon_mat: StandardMaterial3D = null
var _sync_north_label: Label3D = null
var _sync_north_button: MeshInstance3D = null
var _sync_north_mat: StandardMaterial3D = null
# v22 zoom dial drag state (Main only, not lock/teacher).
var _dial_dragging: bool = false
var _dial_hand: String = ""
var _dial_last_y: float = 0.0
# Hand-grab: which held hand is carrying the room planet ("" = none).
var _grab_hand: String = ""
var _pending_desc: String = ""  # vc67: desc voice waits until typing finishes, then reads
# vc36 REAL MODE: test_mode = false. vc34 test mode is kept in code
# but OFF. Real sky distance, real Moon lock, ZIP pad shows on first
# run if no zip saved. Test mode can be re-enabled only by code change.
# Zip place: 34711, Clermont, FL (28.5496, -81.7729, already the default
# lat/lon). No Moon lock required in test mode. Planets sit in the room
# (see planets_core test_mode), labelled TEST MODE on the panel.
# Real sky lock mode is test_mode = false.
var test_mode: bool = false
const TEST_ZIP: String = "34711"
const TEST_ZIP_LAT: float = 28.5496
const TEST_ZIP_LON: float = -81.7729
# vc35 cherry-pick from Muse Code laptop zip (2026-10-28 evening):
# ZIP number pad + Launch Watch journey, additive only. Kept OUT:
# laptop main.tscn worker_url = "" (kept real relay URL),
# laptop planets_core 8k-at-globe-creation (kept 8k on-demand only),
# laptop dial hidden in telescope (kept dial visible when focused),
# laptop sky_core/planets_core wholesale (kept single-source versions).
const JourneyScript = preload("res://scripts/journey.gd")
var _journey: Node3D = null
# Hackathon splash 2026-10-29: final logo on open, passthrough background, transparent.
const SplashScript = preload("res://scripts/hackathon_splash.gd")
const StarshipScript = preload("res://starship/starship_launch.gd")
var _splash: Node3D = null
var _ship_sun_t: float = -10.0  # vc181
var _zodiac: Node3D = null  # vc184 zodiac figures in the sky, on request only
var _zodiac_wait_obj: String = ""  # vc185 today's horoscope request in flight
var _sky_sync: Node3D = null  # vc180 SKY SYNC menu (left MENU button): sync Moon or Sun
var _starship: Node3D = null  # vc162 Starship launch, starship/ only, minimum hooks
# Voice listen Method B 2026-10-29, user chose B, user said "we can do that".
const VoiceListenScript = preload("res://scripts/voice_listen.gd")
const VoiceTranscribeScript = preload("res://scripts/voice_transcribe_client.gd")
const VoiceCommandScript = preload("res://scripts/voice_command.gd")
# vc105 particle AI face, Phase 1 only. Hidden by default, shows
# only while VoiceUI is playing. See scripts/ai_face.gd.
const AiFaceScript = preload("res://scripts/ai_face.gd")
var _ai_face: Node3D = null
var _voice_listen: Node3D = null
var _transcribe: Node = null
var _voice_parser: Node = null
var _transcribe_wake: Node = null
var _wake_timer: float = 0.0
var _wake_busy: bool = false
var _wake_sent_unix: float = 0.0  # vc170 watchdog: when the current wake clip was sent
var _wake_command_active: bool = false
var _wake_command_timer: float = 0.0
var _bring_to_you_next: bool = false
# vc37 fixed location (user zip, no pad, no lookup): 34714,
# Clermont, FL, 28.4152, -81.7879. ZIP gives town only, Moon
# pinch gives facing. The pad script file stays on disk unused;
# deleting old files is forbidden, so only its wiring is gone.
var loc_zip: String = "34714"
var loc_place: String = "Clermont, FL"
var loc_lat: float = 28.4152
var loc_lon: float = -81.7879

func _create_splash() -> void:
	if _splash_created:
		return
	_splash_created = true
	_splash = SplashScript.new()
	add_child(_splash)
	if _camera != null:
		_splash.set_camera(_camera)

func _start_boot_permissions() -> void:
	_perm_boot_time = Time.get_unix_time_from_system()
	# Mic first, then location, in that order, via single-permission requests and the Godot permission-result signal.
	var _tree = get_tree()
	if _tree != null and _tree.has_signal("on_request_permissions_result"):
		if not _tree.is_connected("on_request_permissions_result", _on_boot_perm):
			_tree.on_request_permissions_result.connect(_on_boot_perm)
	if not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		_perm_boot_stage = 1
		OS.request_permission("android.permission.RECORD_AUDIO")
		return
	if not "android.permission.ACCESS_FINE_LOCATION" in OS.get_granted_permissions():
		_perm_boot_stage = 2
		OS.request_permission("android.permission.ACCESS_FINE_LOCATION")
		return
	_perm_boot_stage = 3
	_create_splash()

func _on_boot_perm(perm: String, granted: bool) -> void:
	if _perm_boot_stage == 1 and perm.contains("RECORD_AUDIO"):
		# Mic answered, now location, regardless of granted/denied — never re-ask, never hang.
		if not "android.permission.ACCESS_FINE_LOCATION" in OS.get_granted_permissions():
			_perm_boot_stage = 2
			OS.request_permission("android.permission.ACCESS_FINE_LOCATION")
		else:
			_perm_boot_stage = 3
			_create_splash()
		return
	if _perm_boot_stage == 2 and perm.contains("ACCESS_FINE_LOCATION"):
		_perm_boot_stage = 3
		_create_splash()
		return

func _ready() -> void:
	_ready_unix = Time.get_unix_time_from_system()
	_setup_xr()
	_sky = get_node_or_null("SkyCore")
	_planets = get_node_or_null("PlanetsCore")
	_atlas = get_node_or_null("AtlasSky")
	_iss = get_node_or_null("IssSky")
	_iss_interior = load("res://scripts/iss_interior.gd").new()
	_iss_interior.visible = false
	add_child(_iss_interior)
	_earth = get_node_or_null("EarthSky")
	_atlas_system = get_node_or_null("AtlasSystemView")
	# vc118 FIX (vc117 bug): _camera was assigned at line ~142, AFTER this
	# block, so `if _camera != null` was always false and setup() never ran —
	# the ride scene stayed empty and TRAVEL could not work. Assign the camera
	# FIRST, then set up the ride.
	_camera = get_node_or_null("XROrigin/XRCamera") as XRCamera3D
	# vc117 3I/ATLAS ride: scene built in code, camera assigned, comfort asked on first launch.
	_ride_scene = AtlasRideScene.new()
	_ride_scene.name = "AtlasRideScene"
	add_child(_ride_scene)
	if _camera != null:
		_ride_scene.setup(_camera)
	if not AtlasRideScene.has_saved_comfort():
		_ride_scene.show_comfort_prompt()
	_panel = get_node_or_null("IdentifyPanel")
	_hands = get_node_or_null("HandTracking")
	_voice = get_node_or_null("VoiceUI")
	# vc64 SFX: separate player from voice, so pinch click is not cut off by name voice.
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_teacher = get_node_or_null("TeacherClient")
	if _teacher != null:
		_teacher.answer_ready.connect(_on_teacher_answer)
		_teacher.ask_started.connect(_on_teacher_ask_started)
	_teacher_speech = get_node_or_null("TeacherSpeech")
	if _teacher_speech != null and _teacher != null:
		_teacher_speech.worker_url = _teacher.worker_url
	_camera = get_node_or_null("XROrigin/XRCamera") as XRCamera3D
	if _panel != null and _camera != null:
		_panel.set_camera(_camera)
		_panel.typing_finished.connect(_on_typing_finished)
	if _voice != null:
		_voice.finished.connect(_on_voice_finished)  # vc78 FADE: after desc voice ends, panel fades out
	# vc132 AI FACE REMOVED (user 2026-11-02): no face in the sky at all.
	# ai_face.gd stays on disk for a new, improved face later, but nothing
	# creates it here. face_node stays null, so place_face / keep_clear skip.
	# vc171 LOGOS FIRST, THEN PERMISSIONS (user 2026-11-03: logos did not show).
	# vc159 put permissions before logos so dialogs would not hide them, but
	# if the permission signal never fires the logos waited on a 20 s timeout
	# and looked missing at the start. Now logos run first, always, 12 s total,
	# and permissions are requested only after the splash finishes (see _process).
	# If permissions are already granted, nothing extra happens after the logos.
	_create_splash()
	_perm_boot_stage = 0
	_perm_boot_time = 0.0
	# vc162 Starship: node only, no solar system / sky / teacher changes here.
	_starship = StarshipScript.new()
	add_child(_starship)
	if _starship.has_method("set_camera"):
		_starship.set_camera(_camera)
	# Voice listen Method B: Listen button in front of you, centre-bottom, push-to-talk, planets first.
	_voice_listen = VoiceListenScript.new()
	add_child(_voice_listen)
	if _voice_listen.has_signal("status"):
		_voice_listen.status.connect(_on_voice_listen_status)
	if _camera != null:
		_voice_listen.set_camera(_camera)
	_transcribe = VoiceTranscribeScript.new()
	add_child(_transcribe)
	if _teacher != null:
		_transcribe.worker_url = _teacher.worker_url
	if _voice_listen != null and _voice_listen.has_signal("audio_ready"):
		_voice_listen.audio_ready.connect(_transcribe.send)
	if _transcribe.has_signal("transcribed"):
		_transcribe.transcribed.connect(_on_voice_text)
	if _transcribe.has_signal("status"):
		_transcribe.status.connect(_on_voice_listen_status)
	if _transcribe.has_signal("transcribe_failed"):
		_transcribe.transcribe_failed.connect(_on_voice_transcribe_failed)
	_transcribe_wake = VoiceTranscribeScript.new()
	add_child(_transcribe_wake)
	if _teacher != null:
		_transcribe_wake.worker_url = _teacher.worker_url
	_transcribe_wake.text_ready.connect(_on_wake_text)
	# vc169 WAKE DEATH FIX: _transcribe_wake.transcribe_failed was NEVER connected,
	# so one failed wake clip (HTTP error/timeout/relay busy) left _wake_busy true
	# forever and _process returned early on every frame after that - wake worked
	# at first, then stopped working for the rest of the session. Now a failure
	# clears _wake_busy so the next 3 s clip is tried again.
	if _transcribe_wake.has_signal("transcribe_failed"):
		_transcribe_wake.transcribe_failed.connect(_on_wake_transcribe_failed)
	# vc145 WAKE: start rolling wake capture at boot. Talk button stays
	# as backup (travel button removal is LATER tonight, not now).
	if _voice_listen != null and _voice_listen.has_method("start_wake"):
		_voice_listen.start_wake()
	# vc53 mic icon: wake word PARKED (user 2026-10-29, vc52 wake did not work in-headset).
	# No rolling clips, no auto wake. Mic icon click is the only voice start.
	_voice_parser = VoiceCommandScript.new()
	add_child(_voice_parser)
	# vc37 user instruction 2026-10-28: ZIP pad REMOVED. No pad, no lookup,
	# no auto 34711. Location is the user's own zip, 34714, Clermont, FL,
	# 28.4152, -81.7879, set here and applied to sky + planets.
	# ZIP still gives town only, Moon pinch still gives facing.
	_apply_location()
	# vc182: Artemis II replay REMOVED (user 2026-11-04). Not created at all.
	if false:
		_journey = JourneyScript.new()
		add_child(_journey)
		_journey.setup(self, _camera)
	# vc184 ZODIAC: "Star Bridge, show me Taurus" -> figure + emblem in the real sky.
	_zodiac = load("res://scripts/zodiac.gd").new()
	_zodiac.name = "Zodiac"
	add_child(_zodiac)
	# vc180 SKY SYNC menu: left MENU button -> SYNC MOON / SYNC SUN -> ring -> pinch.
	_sky_sync = load("res://scripts/sky_sync.gd").new()
	_sky_sync.name = "SkySync"
	add_child(_sky_sync)
	_sky_sync.camera = _camera
	_sky_sync.synced.connect(_on_sky_synced)
	_sky_sync.message.connect(_on_sky_sync_message)
	_sky_sync.teacher_requested.connect(_start_talk)
	if _hands != null:
		_hands.pinch_detected.connect(_on_pinch)
		_hands.pinch_drag_detected.connect(_on_pinch_drag)
		_hands.pinch_released.connect(_on_pinch_release)
		# vc68 GRAB: fist, not pinch, picks up a planet and sets it anywhere.
		_hands.grab_started.connect(_on_grab_started)
		_hands.grab_drag_detected.connect(_on_grab_drag)
		_hands.grab_released.connect(_on_grab_released)
	# vc45 LOCK PARKED (user 2026-10-28: lock does NOT WORK yet, focus on functions working first).
	# Lock code stays in the file, dormant, for later — it is NOT called, NOT applied, NOT a gate.
	# Pinch identifies immediately, every launch, yaw 0, no lock step, no saved lock, no re-lock.
	calibration_done = true
	calibration_source = ""
	yaw_offset_deg = 0.0
	alt_offset_deg = 0.0
	_apply_yaw()
	if test_mode:
		calibration_done = true
		calibration_source = "TEST MODE zip " + TEST_ZIP
		if _planets != null:
			_planets.test_mode = true
		if _sky != null:
			_sky.lat_deg = TEST_ZIP_LAT
			_sky.lon_deg = TEST_ZIP_LON
		if _planets != null:
			_planets.lat_deg = TEST_ZIP_LAT
			_planets.lon_deg = TEST_ZIP_LON
	# vc50 boot, user verdict 2026-10-29: logo is perfect, words must NOT
	# cover it. No panel words on open at all — splash logo alone, visual
	# only. The instruction text is kept here in code comments only, not
	# shown. Panel stays hidden until the FIRST pinch, then it shows that
	# pinched object only. Test mode location is still applied above.
	if _panel != null:
		_panel.hide_panel()
	# vc72 TEMPORARY DEBUG NUMBERS, see var comment above. Top-left, small, always on.
	# vc74 CLEAN: debug numbers OFF for demo/submission. Label not created, update code stays null-safe.
	_debug_label = Label3D.new()
	_debug_label.visible = false  # vc74 CLEAN: debug numbers exist in code but are hidden, never shown in demo/submission
	_debug_label.font_size = 16
	_debug_label.pixel_size = 0.0012
	_debug_label.width = 380
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.modulate = Color(1.0, 1.0, 0.3)
	_debug_label.outline_size = 2
	_debug_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_debug_label.text = "DEBUG TEST ONLY"
	add_child(_debug_label)
	# vc91 TRAVEL BUTTON: created once, positioned every frame in _process, hidden unless a travel world is brought in close or travelling.
	_travel_label = Label3D.new()
	_travel_label.visible = false
	_travel_label.font_size = 48
	_travel_label.pixel_size = 0.0012  # vc155: was 0.0025, button was ~0.95 m wide — much smaller now
	_travel_label.width = 380
	_travel_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_travel_label.modulate = Color(1.0, 1.0, 1.0)
	_travel_label.outline_size = 4
	_travel_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_travel_label.text = "TRAVEL"
	add_child(_travel_label)
	# vc93 BUTTON: small dark rectangle behind the words, so it reads as a button, not just text.
	_travel_button_mat = StandardMaterial3D.new()
	_travel_button_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_travel_button_mat.albedo_color = Color(0.05, 0.18, 0.40)
	var _tbmesh: BoxMesh = BoxMesh.new()
	_tbmesh.size = Vector3(0.46, 0.16, 0.03)  # vc155: was 0.85 x 0.32
	_travel_button = MeshInstance3D.new()
	_travel_button.mesh = _tbmesh
	_travel_button.material_override = _travel_button_mat
	_travel_button.visible = false
	add_child(_travel_button)
	# vc121 TALK TO TEACHER BUTTON: same TRAVEL button recipe, centre-bottom
	# at the voice-listen position. Visible at open by user choice (this
	# button only - the identify panel still stays hidden until first pinch).
	_talk_label = Label3D.new()
	_talk_label.visible = true
	_talk_label.font_size = 48
	_talk_label.pixel_size = 0.0005  # vc155: 440*0.0005=0.22 m wide, was 0.40 m — much smaller, pinch still works by aim, not by touching the box
	_talk_label.width = 440
	_talk_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_talk_label.modulate = Color(1.0, 1.0, 1.0)
	_talk_label.outline_size = 4
	_talk_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_talk_label.text = "TALK TO TEACHER"
	add_child(_talk_label)
	_talk_button_mat = StandardMaterial3D.new()
	_talk_button_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_talk_button_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_talk_button_mat.albedo_color = Color(0.05, 0.18, 0.40, 0.0)  # vc159: Talk box transparent, user 2026-11-02 — no blue box, just the white TALK TO TEACHER text. Pinch still works by aim, not by touching the box.
	var _tkmesh: BoxMesh = BoxMesh.new()
	_tkmesh.size = Vector3(0.22, 0.09, 0.03)  # vc155: was 0.40 x 0.16
	_talk_button = MeshInstance3D.new()
	_talk_button.mesh = _tkmesh
	_talk_button.material_override = _talk_button_mat
	_talk_button.visible = true
	add_child(_talk_button)

	# vc146 ALLOW PRECISE LOCATION BUTTON: sits left of Talk, visible
	# only until ACCESS_FINE_LOCATION is granted. Pinch it -> system
	# permission dialog (mic + location, since both are in the manifest).
	_loc_label = Label3D.new()
	_loc_label.visible = false
	_loc_label.font_size = 32
	_loc_label.pixel_size = 0.0007
	_loc_label.width = 600
	_loc_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_loc_label.modulate = Color(1.0, 1.0, 1.0)
	_loc_label.outline_size = 4
	_loc_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_loc_label.text = "ALLOW PRECISE LOCATION"
	add_child(_loc_label)
	_loc_button_mat = StandardMaterial3D.new()
	_loc_button_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_loc_button_mat.albedo_color = Color(0.05, 0.18, 0.40)
	var _locmesh: BoxMesh = BoxMesh.new()
	_locmesh.size = Vector3(0.42, 0.16, 0.03)
	_loc_button = MeshInstance3D.new()
	_loc_button.mesh = _locmesh
	_loc_button.material_override = _loc_button_mat
	_loc_button.visible = false
	add_child(_loc_button)

	# vc150 REAL TIME STAR SYNC choice: Moon pinch OR phone compass.
	# User 2026-11-02: "moon pinch or open phone compass" — Sun shadow
	# option dropped from the list at his word. Two buttons only.
	_sync_title = Label3D.new()
	_sync_title.visible = false
	_sync_title.font_size = 40
	_sync_title.pixel_size = 0.0005  # vc155: was 0.0009, title was ~0.54 m wide
	_sync_title.width = 600
	_sync_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sync_title.modulate = Color(1.0, 1.0, 1.0)
	_sync_title.outline_size = 4
	_sync_title.outline_modulate = Color(0.0, 0.0, 0.0)
	_sync_title.text = "REAL TIME STAR SYNC"
	add_child(_sync_title)
	for _pair in [["SYNC MOON", "moon"], ["SYNC NORTH", "north"]]:
		var _lbl: Label3D = Label3D.new()
		_lbl.visible = false
		_lbl.font_size = 36
		_lbl.pixel_size = 0.0005  # vc155: was 0.0008, SYNC buttons were ~0.40 m wide
		_lbl.width = 480
		_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_lbl.modulate = Color(1.0, 1.0, 1.0)
		_lbl.outline_size = 4
		_lbl.outline_modulate = Color(0.0, 0.0, 0.0)
		_lbl.text = _pair[0]
		add_child(_lbl)
		var _mat: StandardMaterial3D = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(0.05, 0.18, 0.40)
		var _mesh: BoxMesh = BoxMesh.new()
		_mesh.size = Vector3(0.24, 0.09, 0.03)  # vc155: was 0.42 x 0.16
		var _btn: MeshInstance3D = MeshInstance3D.new()
		_btn.mesh = _mesh
		_btn.material_override = _mat
		_btn.visible = false
		add_child(_btn)
		if _pair[1] == "moon":
			_sync_moon_label = _lbl
			_sync_moon_button = _btn
			_sync_moon_mat = _mat
		else:
			_sync_north_label = _lbl
			_sync_north_button = _btn
			_sync_north_mat = _mat

func _process(_delta: float) -> void:
	# vc181: feed the real Sun direction (with Sky Sync yaw) to Starship once a second.
	if _starship != null and _planets != null and _starship.has_method("set_sun_dir"):
		var _snow: float = Time.get_unix_time_from_system()
		if abs(_snow - _ship_sun_t) >= 1.0:
			_ship_sun_t = _snow
			var _sj: Dictionary = AstroMathScript.jds_from_unix(_snow)
			_starship.set_sun_dir(AstroMathScript.planet_world_dir("Sun", _sj["tt"], _sj["ut1"], _planets.lat_deg, _planets.lon_deg, yaw_offset_deg, alt_offset_deg))
	if _zodiac != null and _planets != null:
		_zodiac.set("lat_deg", _planets.lat_deg)
		_zodiac.set("lon_deg", _planets.lon_deg)
		if _planets.travel_body() != "" and _zodiac.visible:
			_zodiac.visible = false  # never inside a travel world
	if _sky_sync != null:
		if _planets != null:
			_sky_sync.lat_deg = _planets.lat_deg
			_sky_sync.lon_deg = _planets.lon_deg
		_sky_sync.blocked = (_planets != null and _planets.travel_body() != "") or _iss_travelling or (_splash != null and _splash.has_method("is_active") and _splash.is_active())
	# vc116 3I/ATLAS: update the sky comet once a second, like the planets.
	if _atlas != null and _atlas.has_method("update_for_unix"):
		var _now: float = Time.get_unix_time_from_system()
		if abs(_now - _atlas_last_update) >= 1.0:
			_atlas_last_update = _now
			_atlas.update_for_unix(_now)
	# vc133 ISS FIX: ISS used atlas's timer, which atlas had JUST reset to now,
	# so the ISS check was always <1s and never ran. ISS stayed at (0,0,0),
	# the spawn point, so the user opened inside the station model. Own timer now.
	if _iss != null and _iss.has_method("update_for_unix"):
		var _now2: float = Time.get_unix_time_from_system()
		if abs(_now2 - _iss_last_update) >= 1.0:
			_iss_last_update = _now2
			_iss.update_for_unix(_now2)
	# vc153 ISS interior: follows camera position, rotation world-fixed, exterior hidden inside.
	if _iss_interior != null:
		# vc180: place the interior ONCE when you enter (was every frame, so
		# the whole module moved with your head). Aisle points where you face.
		if _iss_travelling and not _iss_interior.visible and _camera != null:
			var _ifwd: Vector3 = -_camera.global_transform.basis.z
			_ifwd.y = 0.0
			if _ifwd.length() < 0.01:
				_ifwd = Vector3(0, 0, -1)
			_ifwd = _ifwd.normalized()
			_iss_interior.global_position = _camera.global_position
			_iss_interior.rotation = Vector3(0.0, atan2(-_ifwd.z, _ifwd.x), 0.0)
		_iss_interior.visible = _iss_travelling
	if _iss != null:
		if _iss_travelling:
			_iss.visible = false
	# vc134 LISTENING ALIVE: panel updates every second with elapsed time,
	# so you can SEE it is still hearing you, and it auto-sends after 6s
	# even if you never pinch again. True word-by-word live captions are
	# not possible with this voice service — it needs the full clip first —
	# so the elapsed timer is the live proof, and "I heard: <your words>"
	# lands the second it stops, before the answer.
	if _voice_listen != null and _voice_listen.is_listening() and _listen_start_unix > 0.0:
		var _elapsed: float = Time.get_unix_time_from_system() - _listen_start_unix
		if _elapsed >= 6.0:
			# vc135: voice_listen already auto-stops at 6s and emits audio_ready.
			# This is only a fallback stop; do NOT transcribe here, or it double-sends.
			_listen_start_unix = -1.0
			_voice_listen.stop()
		# vc135: live listening display now comes from voice_listen.status
			# (4x/sec, level + frame count), not this 1s main update.
	# vc72 TEMPORARY DEBUG NUMBERS: update 4x/sec, camera-relative top-left.
	if _camera != null and _debug_label != null:
		_debug_acc += _delta
		if _debug_acc >= 0.25:
			_debug_acc = 0.0
			var _g: Vector3 = _gaze_dir().normalized()
			var _look_az: float = fposmod(rad_to_deg(atan2(_g.x, -_g.z)), 360.0)
			var _look_alt: float = rad_to_deg(asin(clamp(_g.y, -1.0, 1.0)))
			var _maa: Dictionary = _moon_alt_az()
			var _diff: float = fposmod(float(_maa.get("az", 0.0)) - _look_az + 540.0, 360.0) - 180.0
			var _virt_az: float = fposmod(float(_maa.get("az", 0.0)) + yaw_offset_deg, 360.0)
			var _vdiff: float = fposmod(_virt_az - _look_az + 540.0, 360.0) - 180.0
			_debug_label.text = "DEBUG TEST ONLY\nLOOK Az %.0f Alt %.0f\nMOON true Az %.0f Alt %.0f\nYAW %.0f VIRTUAL Az %.0f\nDiff to virtual %.0f deg\nLOCKED: %s Picked: %s" % [_look_az, _look_alt, float(_maa.get("az", 0.0)), float(_maa.get("alt", 0.0)), yaw_offset_deg, _virt_az, _vdiff, ("YES" if _debug_locked else "NO - first pinch locks"), selected_object]
		var _cb: Basis = _camera.global_transform.basis
		_debug_label.global_position = _camera.global_position + _cb * Vector3(-0.55, 0.40, -1.2)
	# vc91 TRAVEL BUTTON: above a brought travel planet only (user 2026-10-30: button above each planet, click to travel, nothing else changed).
	if _travel_label != null and _planets != null:
		var _tb: String = _planets.travel_body()
		if _tb != "":
			# vc96: NO BACK button in travel - user 2026-10-30 21:29: any pinch brings you back to baseline, button was in the way of the view.
			_travel_label.visible = false
		elif selected_object == "3I/ATLAS" and _atlas != null:
			# vc117: TRAVEL button for the comet, above its sky marker.
			_travel_label.text = "TRAVEL"
			_travel_label.visible = true
			_travel_label.global_position = _atlas.global_position + Vector3.UP * 1.5
		elif selected_object == "ISS" and _iss != null and bool(_iss.get("brought")):
			# vc153 TRAVEL button for ISS, above the brought station.
			_travel_label.text = "TRAVEL"
			_travel_label.visible = true
			_travel_label.global_position = _iss.global_position + Vector3.UP * 2.0
		elif _planets.focused_body() != "" and _planets.is_brought(_planets.focused_body()) and _planets.can_travel(_planets.focused_body()):
			_travel_label.text = "TRAVEL"
			_travel_label.visible = true
			_travel_label.global_position = _planets.focused_position() + Vector3.UP * (_planets.brought_radius() + 0.5)
			# vc114: keep-clear guard calls (main paths). Brought planet guard
			# runs in planets_core.apply_face_guard via _planets below; travel
			# label and panel are guarded here — both already sit at >=40
			# deg from the face, so the guard returns early (no move).
			if _planets != null and _planets.has_method("apply_face_guard"):
				_planets.apply_face_guard()
		else:
			_travel_label.visible = false
		# vc182: NO travel buttons anywhere (user 2026-11-04). Travel is by
		# voice only ("Star Bridge, take me to Mars"); any pinch brings you back.
		_travel_label.visible = false
		# vc93 BUTTON: follows the label, faces the camera, lights up green when a hand hovers over it.
		if _travel_button != null:
			_travel_button.visible = _travel_label.visible
			if _travel_label.visible and _camera != null:
				var _btn_dir: Vector3 = (_travel_label.global_position - _camera.global_position).normalized()
				_travel_button.global_position = _travel_label.global_position + _btn_dir * 0.03
				_travel_button.look_at(_camera.global_position, Vector3.UP)
				# vc94 HOVER BY AIM, NOT DISTANCE: the button is 1.8m out, a hand is ~0.6m out, so hand-to-button distance is never <0.60 - that is why vc93 never highlighted and never fired. Aim angle from the camera is what a pinch actually means.
				var _hovered: bool = false
				if _hands != null and _camera != null:
					var _bdir: Vector3 = (_travel_button.global_position - _camera.global_position).normalized()
					for _hn in ["left", "right"]:
						var _hpt: Vector3 = _hands.pinch_point(_hn)
						var _hdir: Vector3 = (_hpt - _camera.global_position).normalized()
						if _bdir.dot(_hdir) > 0.966:  # within ~15 degrees of the button
							_hovered = true
				if _travel_button_mat != null:
					_travel_button_mat.albedo_color = Color(0.10, 0.90, 0.35) if _hovered else Color(0.05, 0.18, 0.40)
	# vc121 TALK BUTTON: follows the voice-listen position every frame,
	# faces the camera, lights up green on aim (same 15-degree rule as
	# TRAVEL), stays green while listening, so a pinch on it is never
	# confused with a random star or planet.
	if _talk_label != null and _talk_button != null and _camera != null and _voice_listen != null:
		var _travelling_now: bool = _planets != null and _planets.travel_body() != ""
		# vc125: Talk button hidden until logos fade out (12s total, official + hackathon).
		var _splash_now: bool = _splash != null and _splash.has_method("is_active") and _splash.is_active()
		# vc181: Talk to Teacher moved into the left-hand menu (AI TEACHER).
		# The floating button is never shown, and cannot be pinched.
		_talk_label.visible = false
		_talk_button.visible = false
		var _tpos: Vector3 = _voice_listen.listen_position()
		_talk_label.global_position = _tpos
		var _tdir: Vector3 = (_tpos - _camera.global_position).normalized()
		_talk_button.global_position = _tpos + _tdir * 0.03
		_talk_button.look_at(_camera.global_position, Vector3.UP)
		_talk_hovered = false
		if _hands != null:
			for _hn in ["left", "right"]:
				var _hpt: Vector3 = _hands.pinch_point(_hn)
				var _hdir: Vector3 = (_hpt - _camera.global_position).normalized()
				if _tdir.dot(_hdir) > 0.966:
					_talk_hovered = true
		if _talk_button_mat != null:
			# vc159: keep Talk box transparent always, even on hover/listening — no blue box, no green box, just text.
			_talk_button_mat.albedo_color = Color(0.05, 0.18, 0.40, 0.0)
		# vc159: permissions are BOOT ONLY, before logos — never after logos, never a button in view.
		if _loc_label != null and _loc_button != null:
			_loc_label.visible = false
			_loc_button.visible = false
		# vc171: logos are done (splash dismissed) and permissions are still
		# unstarted - now request mic, then location, in that order. This runs
		# once: _start_boot_permissions moves stage to 1/2/3, so it will not
		# re-fire. If permissions are already granted, it creates no dialog
		# and just marks stage 3.
		if _splash_created and not (_splash != null and _splash.has_method("is_active") and _splash.is_active()) and _perm_boot_stage == 0 and OS.get_name() == "Android":
			if not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions() or not "android.permission.ACCESS_FINE_LOCATION" in OS.get_granted_permissions():
				_start_boot_permissions()
			else:
				_perm_boot_stage = 3
		# Timeout fallback: if the system never callbacks (already answered, denied, or signal missing), start logos after 20 s so the app never hangs on permissions.
		if not _splash_created and _perm_boot_stage in [1, 2] and _perm_boot_time > 0.0 and Time.get_unix_time_from_system() - _perm_boot_time > 20.0:
			_perm_boot_stage = 3
			_create_splash()
		# vc151 PHONE COMPASS ONLY (user 2026-11-02, simplified): one button, centred.
		# Moon button removed from view, Sun shadow never added. Pinching
		# SYNC NORTH while facing north IS the lock — no second pinch.
		# vc159 SYNC REMOVED: no SYNC title, no SYNC NORTH, no SYNC MOON, ever. _show_sync is always false.
		if _sync_title != null:
			_sync_title.visible = false
		if _sync_moon_label != null:
			_sync_moon_label.visible = false
		if _sync_moon_button != null:
			_sync_moon_button.visible = false
		if _sync_north_label != null:
			_sync_north_label.visible = false
		if _sync_north_button != null:
			_sync_north_button.visible = false
	# vc48 user verdict 2026-10-29: panel must NOT change when you
	# look around. Only a pinch changes it. The old diagnostic
	# panel updated every second (Blend, Hands, Pinches, Moon/Gaze
	# alt), so words kept changing as hands moved and head turned,
	# even with no pinch. That diagnostic is now OFF - it was a test
	# aid, not a user feature. Boot panel stays static until first
	# pinch, then only pinch (and its teacher answer) changes it.
	# Passthrough / hand diagnostics now go to console log only, if needed.
	# vc145 WAKE ON: rolling 3s clips while not push-listening. If a clip
	# contains star+bridge, start push listening for 6s, then auto-stop/send.
	# contains star+bridge, start push listening for 6s, then auto-stop/send.
	if _voice_listen == null:
		return
	if _voice_listen.is_listening():
		if _wake_command_active:
			_wake_command_timer -= _delta
			if _wake_command_timer <= 0.0:
				_wake_command_active = false
				# vc135: stop() emits audio_ready -> transcribe.send, no double send.
				_voice_listen.stop()
				if _voice_listen != null:
					_voice_listen.start_wake()
		return
	_wake_timer += _delta  # vc183: keeps counting while a clip is in flight
	if _wake_busy:
		# vc170 WATCHDOG (Claude reliability prompt, 2026-11-03): a hung wake
		# request must never stick wake again. Transcribe timeout is 20 s,
		# so 25 s with no answer means the request is dead - clear and retry.
		if _wake_sent_unix > 0.0 and Time.get_unix_time_from_system() - _wake_sent_unix > 25.0:
			_wake_busy = false
			_wake_sent_unix = 0.0
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
		return
	if _wake_timer >= 2.0:  # vc182: 4 s clips every 2.5 s, overlapping by 1.5 s
		_wake_timer = 0.0
		var clip: PackedByteArray = _voice_listen.drain_clip()
		if clip.size() > 44 and _transcribe_wake != null:
			_wake_busy = true
			_wake_sent_unix = Time.get_unix_time_from_system()
			_transcribe_wake.transcribe_wav(clip)

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
	# vc114: passthrough back ON (reverts vc113 test-only OFF, permanent).
	xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	get_viewport().transparent_bg = true
	if not xr_interface.initialize():
		print("Star App: OpenXR initialize returned false.")
		return
	get_viewport().use_xr = true
	print("Star App: OpenXR initialized, vc114 blend ALPHA passthrough ON, hands first.")

func _location_line() -> String:
	return "ZIP " + loc_zip + " · " + loc_place

func _apply_location() -> void:
	# Town moves the sky. Facing (yaw) still comes only from the Moon
	# pinch — a ZIP knows the town, not the turn.
	if _sky != null:
		_sky.lat_deg = loc_lat
		_sky.lon_deg = loc_lon
	if _planets != null:
		_planets.lat_deg = loc_lat
		_planets.lon_deg = loc_lon
	if _atlas != null:
		_atlas.lat_deg = loc_lat
		_atlas.lon_deg_east = loc_lon

# --- Calibration: saved, once ever ---

func _load_calibration() -> void:
	# vc45 PARKED: lock does not work yet, do not load a saved lock.
	pass

func _save_calibration() -> void:
	# vc45 PARKED: do not save a lock.
	pass

func _apply_yaw() -> void:
	if _sky != null:
		_sky.yaw_offset_deg = yaw_offset_deg
		_sky.alt_offset_deg = alt_offset_deg
	if _planets != null:
		_planets.yaw_offset_deg = yaw_offset_deg
		_planets.alt_offset_deg = alt_offset_deg
	if _atlas != null:
		_atlas.yaw_offset_deg = yaw_offset_deg
		_atlas.alt_offset_deg = alt_offset_deg
	if _iss != null:
		_iss.set("yaw_offset_deg", yaw_offset_deg)  # vc180: ISS turns with the sky sync too
	if _zodiac != null:
		_zodiac.set("yaw_offset_deg", yaw_offset_deg)  # vc184: zodiac pinned to the synced sky
		_zodiac.set("alt_offset_deg", alt_offset_deg)

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
	# vc45 PARKED: lock disabled, never calibrates.
	return false

func _moon_alt_az() -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	var lat: float = 28.4152
	var lon: float = -81.7879
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

func _on_wake_text(text: String) -> void:
	_wake_busy = false
	if text.strip_edges() == "":
		return
	var low: String = text.to_lower()
	if _try_voice_sync(low):
		return
	# vc181 Starship voice: spawn / launch / reset / indoor (no buttons).
	if _starship_voice(low):
		return
	var _after: String = _wake_split(low)
	if _after != "-":
		# vc182: "Star Bridge, show me Mars" in one breath runs the request
		# straight away; "Star Bridge" alone starts listening for 6 s.
		if _after.split(" ", false).size() >= 2 and not (_voice_listen != null and _voice_listen.is_listening()):
			if _voice != null:
				_voice.play_sound("sound_click")
			_voice_heard = _after
			_on_voice_text(_after)
			return
		if _voice_listen != null and not _voice_listen.is_listening():
			# vc145: same noise as a pinch when wake activates, so you
			# know it heard "Star Bridge" before you start your question.
			if _voice != null:
				_voice.play_sound("sound_click")
			if _panel != null:
				_panel.show_object("Voice", "🎤 Listening... talk now")
			_voice_listen.start_listen()
			_wake_command_active = true
			_wake_command_timer = 6.0

func _on_voice_listen_status(text: String) -> void:
	# Grok vc135: every voice state goes on the panel, persistent, so the
	# hide timer can never clear a listening/transcribing caption.
	if _panel != null:
		if _panel.has_method("show_persistent"):
			_panel.show_persistent("Voice", text)
		else:
			_panel.show_object("Voice", text)

func _on_voice_text(text: String) -> void:
	# Voice Method B result: text from relay /transcribe, e.g. "show me Mars".
	_voice_heard = text
	if text == "":
		if _panel != null:
			_panel.show_object("Voice", "I didn't hear anything.\nTry again: pinch Talk to Teacher, say show me Mars, pinch Talk to Teacher again.")
		# vc172: an empty transcription must NOT kill wake. Before this, this
		# return skipped start_wake, so one silent Talk left voice dead.
		if _voice_listen != null and _voice_listen.has_method("start_wake"):
			_voice_listen.start_wake()
		return
	# vc145 TRAVEL BY VOICE: "travel" / "travel to Mars" — Travel button
	# stays for now (removal is later tonight, not now), voice is added.
	var _low: String = text.to_lower()
	# vc168 Starship entry: command is "spawn starship" (user 2026-11-03).
	# "launch starship" still works as an alias. Plain "launch" alone is NOT a trigger,
	# so it cannot fire by accident while talking about something else.
	if _starship_voice(_low):
		if _voice_listen != null and _voice_listen.has_method("start_wake"):
			_voice_listen.start_wake()
		return
	if _zodiac_voice(_low):
		if _voice_listen != null and _voice_listen.has_method("start_wake"):
			_voice_listen.start_wake()
		return
	if _try_voice_sync(_low):
		if _voice_listen != null and _voice_listen.has_method("start_wake"):
			_voice_listen.start_wake()
		return
	var _in_travel_now: bool = _iss_travelling or (_planets != null and _planets.travel_body() != "")
	var _travel_words: bool = _low.contains("travel") or _low.contains("take me to") or _low.contains("fly me to") or _low.contains("bring me to")
	if _in_travel_now and (_low.contains("go back") or _low.contains("take me home") or _low.contains("take me back") or _low.contains("exit") or _low.contains("leave")):
		_travel_words = true
	if _travel_words:
		if _iss_travelling:
			_iss_travelling = false
			if _panel != null:
				_panel.fade_out_now()
			if _voice != null:
				_voice.play_sound("sound_click")
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
			return
		if _planets != null and _planets.travel_body() != "":
			_planets.clear_travel()
			if _panel != null:
				_panel.fade_out_now()
			if _voice != null:
				_voice.play_sound("sound_click")
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
			return
		if selected_object == "3I/ATLAS" and _ride_scene != null:
			_ride_scene.start_ride()
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
			return
		# vc153 voice travel to ISS: "travel to space station" / "travel to iss".
		if _low.contains("space station") or (" " + _low + " ").contains(" iss ") or _low.contains("i.s.s") or selected_object == "ISS":
			_iss_travelling = true
			if _panel != null:
				_panel.clear_anchor()
				_panel.fade_out_now()  # vc182: no words in travel worlds, scenery only
			if _voice != null:
				_voice.play_sound("sound_click")
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
			return
		var _tname: String = ""
		for _b in ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]:
			if _low.contains(_b.to_lower()):
				_tname = _b
				break
		if _tname == "" and _planets != null:
			_tname = _planets.focused_body()
		if _tname == "" :
			_tname = selected_object
		if _tname != "" and _planets != null:
			show_body_by_name(_tname)
			_planets.set_travel(_tname)
			if _panel != null:
				_panel.clear_anchor()
				_panel.fade_out_now()  # vc182: no description words on arrival, scenery only
			if _voice != null:
				_voice.play_sound("sound_click")
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
			return
	if _voice_parser == null:
		return
	var body_name: String = _voice_parser.parse_command(text)
	if body_name == "":
		# vc131 GENERAL TEACHER: ask ANYTHING, no pinch-first requirement.
		# Selected object is context only, not a limit (relay v8 answers anything).
		if _teacher != null:
			_voice_teacher_pending = true
			_voice_teacher_object = selected_object if selected_object != "" else "general"
			if _panel != null:
				if selected_object != "":
					_panel.show_object("Voice", "I heard: " + text + "\nAsking teacher about " + selected_object + "...")
				else:
					_panel.show_object("Voice", "I heard: " + text + "\nAsking teacher...")
			_teacher.ask(_voice_teacher_object, text)
			_voice_heard = ""
			if _voice_listen != null and _voice_listen.has_method("start_wake"):
				_voice_listen.start_wake()
			return
		if _panel != null:
			_panel.show_object("Voice", "I heard: " + text + "\nTeacher is not ready yet.")
		_voice_heard = ""
		# vc172: same wake-death as empty text - restart wake before returning.
		if _voice_listen != null and _voice_listen.has_method("start_wake"):
			_voice_listen.start_wake()
		return
	# vc145: push listening is over, wake resumes for the next "Star Bridge".
	if _voice_listen != null and _voice_listen.has_method("start_wake"):
		_voice_listen.start_wake()
	# Same as pinching that body: panel, bring-to-you, voice, teacher.
	show_body_by_name(body_name)

func _on_wake_transcribe_failed() -> void:
	# vc169: a failed wake clip must never kill wake for the session.
	_wake_busy = false
	if _voice_listen != null and _voice_listen.has_method("start_wake"):
		_voice_listen.start_wake()

func _on_voice_transcribe_failed() -> void:
	# vc122: distinct from silence. text_ready("") now means only "relay answered, no words".
	if _panel != null:
		_panel.show_object("Voice", "Transcribe failed - the relay didn't answer.\nTry again, or pinch a planet instead.")
	# vc169: a failed Talk transcription must not leave wake off either.
	if _voice_listen != null and _voice_listen.has_method("start_wake"):
		_voice_listen.start_wake()

func _on_pinch(hand_name: String, pinch_point: Vector3) -> void:
	# vc69: a pinch point far from / behind the camera is not a real hand pinch (stale zero joints) — ignore it, no identify, no jump.
	if _camera != null:
		var _rel: Vector3 = pinch_point - _camera.global_position
		if _rel.length() > 1.5 or _rel.dot(_camera.global_transform.basis * Vector3(0.0, 0.0, -1.0)) < 0.0:
			return
	# vc178 SUN LOCK, REPEATABLE + ALTITUDE-GATED (replaces vc176 first-pinch lock).
	# vc176 FAILED at the park on vc177: the FIRST pinch of a session is
	# almost never the Sun pinch - it is a mic/location button, Talk, or a
	# panel pinch while looking straight ahead, so the sky locked to the
	# wrong direction and the real Sun pinch (second, third, ...) could
	# never overwrite it. Now ANY pinch re-locks, but ONLY when you are
	# actually looking up at the Sun: gaze altitude within 15 deg of the
	# Sun's true altitude right now. Button/panel pinches are at eye
	# level (~0 deg) and never trigger it; a Sun pinch at ~30-40 deg in
	# the afternoon does. Face the Sun (Star Chart shows the direction,
	# works cloudy), pinch, and the sky re-syncs on the spot - no restart,
	# no re-download, and handing the headset to someone else cannot
	# break it, because you can re-lock in one pinch.
	# yaw = LookAz - SunTrueAz (AstroMath, yaw 0, same as old Moon lock).
	# NO button, NO panel words, NO lock sound, and it does NOT return:
	# the same pinch goes on to Talk / Starship / identify as before.
	# vc181 SKY SYNC MENU GESTURE: the headset never passes its menu button
	# to the app with hand tracking, so we detect it ourselves: LEFT palm
	# facing you + pinch (same move as the Quest menu gesture) opens/closes it.
	if hand_name == "left" and _sky_sync != null and not _sky_sync.blocked and _left_palm_facing_you():
		if _sky_sync.mode == "off":
			_sky_sync.open_menu()
		else:
			_sky_sync.close()
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# vc180 SKY SYNC: menu buttons / ring confirm take the pinch first.
	if _sky_sync != null and _sky_sync.handle_pinch(pinch_point):
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# vc180: automatic Sun lock OFF. It re-turned the whole sky on ANY pinch
	# made at about the Sun's height (planet pinches too), so the sky jumped.
	# Syncing is now only on purpose: left MENU -> SYNC SUN / SYNC MOON.
	if false and _camera != null and _planets != null:
		var _jds178: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
		var _sun_dir178: Vector3 = AstroMathScript.planet_world_dir("Sun", _jds178["tt"], _jds178["ut1"], _planets.lat_deg, _planets.lon_deg, 0.0, 0.0)
		var _gaze178: Vector3 = _gaze_dir()
		if abs(_alt_from_dir(_gaze178) - _alt_from_dir(_sun_dir178)) < 15.0:
			yaw_offset_deg = fposmod(_az_from_dir(_gaze178) - _az_from_dir(_sun_dir178) + 540.0, 360.0) - 180.0
			alt_offset_deg = 0.0
			_apply_yaw()
			_debug_locked = true
	_pinch_count += 1
	# vc127 FIX: gaze must be declared here, before the Talk/Travel near-miss checks use it.
	# vc126 used gaze at lines 663/714 before its declaration at 737, so main.gd failed to
	# parse, the whole scene failed to load, and 126 opened to passthrough only.
	var gaze: Vector3 = _gaze_dir()
	# vc180 Bug 1: button_at FIRST, then placing. Before, is_placing() returned on every pinch,
	# so UP/DOWN/INDOOR/RESET (placement-only buttons) could never be pressed.
	# button_at() now also requires head looking at the button, so a low placement pinch
	# cannot hit a button by accident.
	if _starship != null and _starship.has_method("button_at"):
		var _sb: String = _starship.button_at(pinch_point)
		if _sb != "":
			if _starship.has_method("press_button"):
				_starship.press_button(_sb)
			if _voice != null:
				_voice.play_sound("sound_click")
			return
	if _starship != null and _starship.has_method("is_placing") and _starship.is_placing():
		if _starship.has_method("place"):
			_starship.place()
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	_pinch_hold_start[hand_name] = Time.get_unix_time_from_system()
	# vc117 ride comfort prompt: a button pinch picks the comfort, anything else falls through.
	if _ride_scene != null and _ride_scene.prompt_active and _ride_scene.try_pick_comfort(pinch_point):
		return
	# vc122 RIDE EXIT ON ANY CLICK: a normal click during the comet ride
	# used to do nothing (only a 1s hold or a joypad button ended it), so the
	# user was stuck in the ride. Any pinch now ends it at once, like planets.
	if _ride_scene != null and _ride_scene.ride_active:
		_ride_scene.instant_stop()
		if _panel != null:
			_panel.fade_out_now()
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# Voice Listen first, vc51 fix 2026-10-29: user pinched Listen, panel said
	# "Listening...", then said "show me Mars" and nothing happened.
	# Two failure modes were possible: (a) second pinch missed the button
	# and fell through to a star pinch, overwriting Listening, (b) relay ASR
	# itself 400-failed (proven from here with real audio + silence).
	# Fix (a) here: once listening, ANY pinch stops listening and sends —
	# push-to-talk means pinch to start, pinch anywhere to stop, no second
	# button hit required. A star pinch while listening is now a stop, not
	# an identify, so Listening can never be overwritten by a star panel.
	if _voice_listen != null and _voice_listen.is_listening():
		_listen_start_unix = -1.0
		# vc135: stop() emits audio_ready -> transcribe.send. No wav here, no double send.
		_voice_listen.stop()
		# vc172: stop() with <0.3 s of audio ("Too short") emits NO audio_ready,
		# so _on_voice_text never runs and wake is never restarted - one quick
		# accidental Talk pinch killed voice for the rest of the session.
		# Restarting wake here is harmless when audio_ready does fire, because
		# _on_voice_text also restarts wake (start_wake just re-arms capture).
		if _voice_listen != null and _voice_listen.has_method("start_wake"):
			_voice_listen.start_wake()
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# Voice Listen button: pinch near Listen starts listening, never identifies.
	# vc50 fix: old radius 0.30 m missed real pinches — a hand pinches at
	# ~0.5 m out, the old button sat at 1.0 m, so distance was ~0.5 m and
	# the pinch fell through to sky identify instead. Button is now at
	# 0.75 m, centre-bottom, radius 0.40 m catches a real front-of-you pinch.
	if false and _voice_listen != null and pinch_point.distance_to(_voice_listen.listen_position()) < 0.60:
		if _voice_listen.is_listening():
			# vc135: stop() emits audio_ready -> transcribe.send, no double send.
			_voice_listen.stop()
		else:
			_voice_listen.start_listen()
			if _panel != null:
				_panel.show_object("Voice", "🎤 Listening... talk now")
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# vc121 TALK BUTTON pinch, checked before journey/travel/identify:
	# on-button (aim dot > 0.966, same as TRAVEL) starts listening, never
	# identifies. Near-miss (dot > 0.940) does nothing, never picks a
	# random star while aiming at the button. Listening stop is handled
	# above (any pinch stops and sends).
	# vc155: location button removed — no pinch check, permission is asked by the system dialog in _process, like mic.
	if _camera != null and _talk_button != null and _talk_button.visible and _voice_listen != null and not _voice_listen.is_listening() and not (_planets != null and _planets.travel_body() != "") and not (_splash != null and _splash.has_method("is_active") and _splash.is_active()):
		var _tbdir: Vector3 = (_talk_button.global_position - _camera.global_position).normalized()
		var _phdir: Vector3 = (pinch_point - _camera.global_position).normalized()
		var _tdot: float = _tbdir.dot(_phdir)
		if _tdot > 0.966:
			# vc136 ROOT CAUSE FIX: old code showed "Listening..." AFTER start(),
			# overwriting start()'s failure status (Input OFF / Mic DENIED /
			# Mic bus NO CAPTURE), so a failed start looked like a stuck
			# listening prompt and nothing ever ran. Now: no main prompt at
			# all, voice_listen.status is the only panel text. If start()
			# fails, its failure stays on screen. If it succeeds, status is
			# "Listening… 0s" then level/frames 4x/sec.
			if _teacher_speech != null and _teacher_speech.has_method("stop"):
				_teacher_speech.stop()
			var _started: bool = _voice_listen.start_listen()
			if _started:
				_listen_start_unix = Time.get_unix_time_from_system()
				_listen_panel_last = _listen_start_unix
			if _voice != null:
				_voice.play_sound("sound_click")
			return
		if _tdot > 0.940 and _camera != null and _tbdir.dot(gaze) > 0.940:
			# vc126: near-miss only swallows a pinch when HEAD is also aiming at Talk.
			# Hand alone near Talk used to swallow a planet re-pinch and make it look dead.
			return
	# vc48 fix 2026-10-29: splash must NOT dismiss on first pinch.
	# That was why it "didn't show at all" - user pinches at open to test,
	# splash vanished instantly, before fade-in finished, looking like it never showed.
	# Splash now always runs its full fade-in 1 s + wait 4 s + fade-out 1 s,
	# then frees itself. Pinch during splash still identifies below, splash stays on top until its time is done.
	# _splash is cleared by its own _process dismiss, not here.
	# Launch Watch first: only its own presses consume (""); anything
	# else falls through untouched to dial / lock / identify.
	if _journey != null:
		var jres: String = _journey.press_at(pinch_point)
		if jres != "":
			if _voice != null:
				_voice.play_sound("sound_click")
			return
	# vc153 ISS travel exit: any pinch inside brings you back out.
	if _iss_travelling:
		_iss_travelling = false
		if _panel != null:
			_panel.fade_out_now()
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# vc96: while travelling, ANY pinch brings you back to baseline - no BACK button to find.
	if _planets != null and _planets.travel_body() != "":
		_planets.clear_travel()
		if _panel != null:
			_panel.fade_out_now()
		if _voice != null:
			_voice.play_sound("sound_click")
		return
	# vc91 TRAVEL BUTTON: pinch the TRAVEL label above a brought planet to travel. Checked before identify, so it never fights the planet pinch.
	if _travel_label != null and _travel_label.visible and _planets != null and _camera != null:
		# vc94: pinch the button by AIM, not hand-to-button distance (see hover fix above).
		var _bdir2: Vector3 = (_travel_label.global_position - _camera.global_position).normalized()
		var _pdir2: Vector3 = (pinch_point - _camera.global_position).normalized()
		var _bang: float = _bdir2.dot(_pdir2)
		# vc94 ORDER MATTERS: on-button first, near-miss second. The first vc94 build checked near-miss first, so every on-button pinch was swallowed as a near-miss and travel never fired - caught before delivery.
		if _bang > 0.966:  # within ~15 degrees = on the button
			if _planets.travel_body() != "":
				_planets.clear_travel()
				if _panel != null:
					_panel.fade_out_now()
			elif selected_object == "3I/ATLAS" and _ride_scene != null:
				# vc117 TRAVEL flow for 3I/ATLAS: start the comet ride, not a planet world.
				_ride_scene.start_ride()
			elif selected_object == "ISS":
				# vc153 start ISS interior travel.
				_iss_travelling = true
				if _panel != null:
					_panel.clear_anchor()
					_panel.fade_out_now()  # vc182: no words in travel worlds, scenery only
			else:
				var _tname: String = _planets.focused_body()
				if _tname != "":
					_planets.set_travel(_tname)
					if _panel != null:
						_panel.clear_anchor()  # vc92: travel words in front of camera, not at the hidden Mars anchor
						_panel.fade_out_now()  # vc182: no description words on arrival, scenery only
			if _voice != null:
				_voice.play_sound("sound_click")
			return
		if _bang > 0.940 and _bdir2.dot(gaze) > 0.940:  # vc126: near-miss only when HEAD is also on the button, else a planet pinch below it must still reach identify
			if _voice != null:
				_voice.play_sound("sound_click")
			return
	# v22 dial tap: pinch on the dial steps zoom, starts a drag,
	# never identifies. Room mode only; dial is hidden otherwise,
	# and hidden before lock, so lock behaviour is unchanged.
	# vc56 PLAYTEST: dial DISABLED — zoom is for the finished product, not the playtest.
	# Pinch brings to you, dial does nothing, so strangers cannot accidentally zoom.
	if false and calibration_done and _planets != null and _planets.focused_body() != "" and _planets.travel_body() == "":
		if pinch_point.distance_to(_planets.dial_position()) < 0.60:
			_dial_dragging = true
			_dial_hand = hand_name
			_dial_last_y = pinch_point.y
			_planets.step_zoom()
			if _voice != null:
				_voice.play_sound("sound_click")
			return
	if _voice != null:
		_voice.play_sound("sound_click")
	# vc59 ANY-ANGLE: gaze already declared at the top of _on_pinch (vc127 fix).
	var pinch_dir: Vector3 = gaze
	if _camera != null:
		pinch_dir = (pinch_point - _camera.global_position).normalized()
	# vc174: old SYNC NORTH button block removed - no button, no words.
	# Lock already happened at the top of _on_pinch on the first pinch.
	_identify(gaze, pinch_dir)
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

func _on_pinch_drag(hand_name: String, pinch_point: Vector3) -> void:
	# vc165 Starship placement: pinch-drag forward/back changes placement distance, before dial/grab.
	if _starship != null and _starship.has_method("is_placing") and _starship.is_placing() and _starship.has_method("adjust_distance"):
		_starship.adjust_distance(pinch_point)
		return
	# Dial drag first (zoom), else hand-grab: a held pinch near the
	# room planet carries it. Identify-on-press is untouched — grab
	# only steers a planet that pinch already selected. Room mode
	# only, never telescope/travel, never the dial hand.
	if _dial_dragging and hand_name == _dial_hand:
		if _planets == null or _planets.focused_body() == "" or _planets.telescope_body() != "" or _planets.travel_body() != "":
			_dial_dragging = false
			return
		var dy: float = pinch_point.y - _dial_last_y
		_dial_last_y = pinch_point.y
		_planets.set_zoom(_planets.zoom_factor() + dy * 6.0)
		return
	if _grab_hand != "" and hand_name != _grab_hand:
		return
	if _planets == null or _planets.focused_body() == "" or _planets.telescope_body() != "" or _planets.travel_body() != "":
		_release_grab()
		return
	if _grab_hand == "":
		if pinch_point.distance_to(_planets.focused_position()) > _planets.grab_radius():
			return
		_grab_hand = hand_name
	_planets.hold_focused(pinch_point)

func _release_grab() -> void:
	_grab_hand = ""
	if _planets != null:
		_planets.release_hold()


func _on_grab_started(hand_name: String, grab_point: Vector3) -> void:
	# vc68: fist near the brought planet grabs it. No identify, no pinch, no jump.
	if _planets == null or _planets.focused_body() == "" or _planets.telescope_body() != "" or _planets.travel_body() != "":
		return
	if _grab_hand != "":
		return
	if grab_point.distance_to(_planets.focused_position()) > _planets.grab_radius():
		return
	_grab_hand = hand_name
	_planets.hold_focused(grab_point)

func _on_grab_drag(hand_name: String, grab_point: Vector3) -> void:
	if _grab_hand != hand_name or _planets == null:
		return
	_planets.hold_focused(grab_point)

func _on_grab_released(hand_name: String) -> void:
	if _grab_hand == hand_name:
		_release_grab()

func _on_pinch_release(hand_name: String) -> void:
	if _starship != null:
		_starship.set("_last_drag", 0.0)
	# vc117 instant stop: pinch-and-hold (>= 1.0 s) during the ride fades out and ends it at once.
	if _ride_scene != null and _ride_scene.ride_active and _pinch_hold_start.has(hand_name):
		if Time.get_unix_time_from_system() - float(_pinch_hold_start[hand_name]) >= 1.0:
			_ride_scene.instant_stop()
	_pinch_hold_start.erase(hand_name)
	if _dial_dragging and hand_name == _dial_hand:
		_dial_dragging = false
		_dial_hand = ""
	if _grab_hand != "" and hand_name == _grab_hand:
		_release_grab()

func _input(event: InputEvent) -> void:
	# vc117 instant stop, controller button: any joypad button press during the ride ends it.
	if event is InputEventJoypadButton and event.pressed and _ride_scene != null and _ride_scene.ride_active:
		_ride_scene.instant_stop()

func _planet_alt_az(name: String) -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	var jds: Dictionary = AstroMathScript.jds_from_unix(now)
	var lat: float = 28.4152
	var lon: float = -81.7879
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
	# vc45 PARKED: lock disabled, pinch goes straight to identify.
	pass

func _closest_named_star(gaze: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_angle: float = 5.0
	for item: Dictionary in _sky.named_star_directions():
		var ang: float = _angle_between(gaze, item["dir"])
		if ang < best_angle:
			best_angle = ang
			best = item
	return best

func _identify(gaze: Vector3, pinch_dir: Vector3 = Vector3.ZERO) -> bool:
	# vc180 PINCH ACCURACY: every pick below uses the AIM ray = eye -> your
	# pinching fingers. Pinch ON the planet (fingers covering it as you see
	# it) and it comes up; pinch anywhere else and nothing happens. Head
	# gaze is only a sanity check (you must be roughly looking there).
	var aim: Vector3 = pinch_dir if pinch_dir != Vector3.ZERO else gaze
	if _camera != null and aim.angle_to(gaze) > deg_to_rad(40.0):
		return false  # hand far off to the side / low: stray pinch, ignore
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
				# vc126 GAZE-CLOSEST ROOM: room planet wins iff it is the closest object to HEAD.
				# vc125 still blocked re-pinching Uranus to send it back: _other_close counted
				# HAND within 10deg of any sky body, and a pinch hand is rarely on the planet,
					# so the reverse never ran and the fall-through picked Capella instead.
				# Hand is out of this check entirely. Switching still works: if another sky
				# body is closer to HEAD than the room planet, sky selection below wins.
				var _room_ang: float = _angle_between(gaze, rdir)
				var _other_close: bool = false
				for _oname: String in _planets.body_directions().keys():
					if _oname != fb and _angle_between(gaze, _planets.body_directions()[_oname]) < _room_ang:
						_other_close = true
				# vc180 FIX: _angle_between returns DEGREES, the old "< 0.44" meant
				# 0.44 deg, so re-pinching a brought planet almost never sent it back
				# and the pinch fell through and picked some other planet.
				# Now: aim ray inside the brought planet's visible disc + 6 deg.
				var _fdist: float = max(fnode.global_position.distance_to(_camera.global_position), 0.1)
				var _frad: float = rad_to_deg(atan(_planets.target_brought_radius(fb) / _fdist)) + 6.0
				_other_close = false
				if _planets.is_brought(fb) and _angle_between(aim, rdir) < _frad:
					# vc83 REVERSE: re-pinching a brought planet sends it back to the sky, it does NOT switch to another planet or re-show its panel.
					if _planets.is_brought(fb):
						_planets.send_back(fb)
						_planets.clear_focus()
						selected_object = ""
						_desc_playing = false
						_pending_desc = ""  # vc94: reverse stops the voice, not just the words - no desc voice after going back
						if _voice != null and _voice.has_method("stop_all"):
							_voice.stop_all()
						elif _voice != null:
							_voice.stop()
						if _panel != null:
							_panel.stop_typing()
							_panel.fade_out_now()  # vc87: words fade away as the planet goes back
						return true
					select_object(fb)
					_show_panel_for({"name": fb, "kind": "body"})
					if _teacher != null:
						_teacher.ask_about_selected(fb)
					return true
	# vc129 STAR ORB ROOM: Capella had NO room check, only planets did. Re-pinching the
	# Capella orb in front of you fell through to sky directions, where the orb's sky
	# position is elsewhere, so it never sent back and looked dead. Now the orb itself,
	# at its room position, wins if it is closest to HEAD within 25deg, and clears.
	if _camera != null and _star_orb != null and _star_orb_name != "":
		var _s_rdir: Vector3 = (_star_orb.global_position - _camera.global_position).normalized()
		var _s_room_ang: float = _angle_between(gaze, _s_rdir)
		var _s_other_close: bool = false
		if _planets != null:
			for _oname2: String in _planets.body_directions().keys():
				if _angle_between(gaze, _planets.body_directions()[_oname2]) < _s_room_ang:
					_s_other_close = true
		if _angle_between(aim, _s_rdir) < 20.0:  # vc180: was 0.44 (degrees bug)
			_clear_star_orb()
			selected_object = ""
			if _panel != null:
				_panel.stop_typing()
				_panel.fade_out_now()
			if _voice != null and _voice.has_method("stop_all"):
				_voice.stop_all()
			return true
	# TEST MODE: any room planet, not just the focused one, counts if
	# you look at it within 15 degrees. Room planets are large (4 m out),
	# so 15 degrees catches a centre look without catching neighbours
	# 40 degrees apart around the circle.
	if test_mode and _camera != null and _planets != null:
		var tbest: String = ""
		var tang: float = 999.0
		for tname: String in ["Saturn", "Jupiter", "Mars", "Moon", "Venus", "Mercury", "Neptune", "Uranus", "Sun"]:
			var tpos: Vector3 = _planets.body_global_position(tname)
			var tdir: Vector3 = (tpos - _camera.global_position).normalized()
			var ta: float = _angle_between(gaze, tdir)
			if ta < tang:
				tang = ta
				tbest = tname
		if tbest != "" and tang < 15.0:
			select_object(tbest)
			_show_panel_for({"name": tbest, "kind": "body"})
			if _teacher != null:
				_teacher.ask_about_selected(tbest)
			return true
	# vc116 3I/ATLAS: pinchable like a planet, same 30 deg capture and
	# below-horizon-only-when-looking-down rule as the bodies below.
	# vc119: a brought comet is in the room, so check the room direction,
	# not the sky direction, for the re-pinch reverse.
	if _atlas != null and _atlas.brought and _camera != null:
		var _rdir: Vector3 = (_atlas.global_position - _camera.global_position).normalized()
		# vc125 GAZE-LED: brought comet re-pinch needs head within 25deg, hand is not the intent.
		if _angle_between(aim, _rdir) < 20.0:  # vc180: was 0.44 (degrees bug)
			_atlas.send_back()
			if _panel != null:
				_panel.stop_typing()
				_panel.fade_out_now()
			selected_object = ""
			return true
	if _atlas != null and _atlas.global_position.length() > 0.0:
		var _adir: Vector3 = _atlas.global_position.normalized()
		# vc125 GAZE-LED: comet needs head within 20deg. Hand direction is not required.
		var _aang: float = _angle_between(aim, (_atlas.global_position - _camera.global_position).normalized()) if _camera != null else 999.0  # vc180 aim ray
		var _alook_down: bool = gaze.y < -0.087 or pinch_dir.y < -0.087
		if _aang < 6.0:  # vc180: was head within 20 deg, popped up on near-misses
			# vc119: pinch brings it to you, like a planet, before the panel.
			# (Re-pinch reverse is handled by the room-direction check above.)
			if _camera != null:
				_atlas.bring_to_front(_camera)
			select_object("3I/ATLAS")
			_show_panel_for({"name": "3I/ATLAS", "kind": "atlas"})
			if _teacher != null:
				_teacher.ask_about_selected("3I/ATLAS")
			return true
	# vc131 ISS: pinchable like a planet, HEAD within 10deg, brought like atlas.
	# Room re-pinch sends it back, like planets and the comet.
	if _iss != null and _camera != null:
		if bool(_iss.get("brought")):
			var _iss_rdir: Vector3 = (_iss.global_position - _camera.global_position).normalized()
			if _angle_between(aim, _iss_rdir) < 20.0:  # vc180: was 0.44 (degrees bug)
				_iss.send_back()
				if _panel != null:
					_panel.stop_typing()
					_panel.fade_out_now()
				selected_object = ""
				return true
		var _iss_dir: Vector3 = (_iss.global_position - _camera.global_position).normalized() if _iss.global_position.length() > 0.0 else Vector3.ZERO
		if _iss_dir != Vector3.ZERO and _iss.visible and _angle_between(aim, _iss_dir) < 6.0:  # vc180 aim ray, only when really above the horizon
			select_object("ISS")
			_show_panel_for({"name": "ISS", "kind": "iss"})
			return true  # vc159: was missing, so the code fell through to planet candidates and overwrote the ISS panel with Not sure, making ISS look dead and its words vanish.
	# vc146 Earth: brought send-back, sky pinch at 10deg like ISS.
	if _earth != null and _camera != null:
		if bool(_earth.get("brought")):
			var _earth_rdir: Vector3 = (_earth.global_position - _camera.global_position).normalized()
			if _angle_between(aim, _earth_rdir) < 20.0:  # vc180: was 0.44 (degrees bug)
				_earth.send_back()
				if _panel != null:
					_panel.fade_out_now()
				return true
		var _earth_dir: Vector3 = (_earth.global_position - _camera.global_position).normalized()
		if _angle_between(aim, _earth_dir) < 6.0:  # vc180 aim ray
			select_object("Earth")
			_show_panel_for({"name": "Earth", "kind": "earth"})
			return true
	# vc58: stars NOT clickable (back to vc54). Pinching a star must not give 48 Cet / random dim stars.
	# Only Sun/Moon/planets below. Star orb, if any, is cleared on next body pinch.
	# Collect candidates: planets/Moon/Sun, then named stars.
	var candidates: Array = []
	if _planets != null:
		for name: String in _planets.body_directions().keys():
			# vc75 FULL SKY: below-horizon bodies CAN be picked, but ONLY when looking/pinching down (alt < -5deg).
			# vc71 filter blocked all below-horizon picks, which stopped the Mercury horizontal false-pick, but also blocked looking down at the Sun on purpose (user 2026-10-30 00:26 EDT).
			# Horizontal gaze must never pick a below-horizon body; a deliberate look-down does.
			var _looking_down: bool = gaze.y < -0.087 or pinch_dir.y < -0.087
			# vc180: _looking_down was almost always true (a pinch hand is below
			# your eyes), so planets UNDER the floor were picked all the time.
			# The aim ray now decides: you must pinch where the planet is drawn.
			if _planets.is_brought(name):
				continue
			var _bpos: Vector3 = _planets.body_global_position(name)
			var _bdir: Vector3 = (_bpos - _camera.global_position).normalized() if (_camera != null and _bpos != Vector3.ZERO) else _planets.body_directions()[name]
			candidates.append({"name": name, "dir": _bdir, "kind": "body"})
	# vc58: NO star candidates. A pinch that misses all 9 bodies says Not sure, never a dim star.
	# vc56 PLAYTEST: candidates are bodies + stars, planet wins if within 10 deg, else closest star.
	# Planets beat stars (old rule, now moot): Saturn/Neptune are big, named, and what the user
	# is actually pinching at. A dense star field means a star is almost
	# always within 1 degree of a planet, so the old second-angle rule
	# kept saying "two objects equally close" and doing nothing.
	# Rule now (vc39: 10 deg, was 5): if any planet/body is within
	# 10 degrees, pick the closest body, ignore stars. Stars only
	# count if no body is close. Test mode clicked fine because
	# planets were big and capture was 15 deg; real-sky dots
	# need a wider capture than 5 deg or a rough aim misses.
	var best: Dictionary = {}
	var best_angle: float = 5.0
	var second_angle: float = 999.0
	var second: Dictionary = {}
	var closest: Dictionary = {}
	var closest_angle: float = 999.0
	var body_best: Dictionary = {}
	var body_best_angle: float = 999.0
	# vc128 TIGHT BODY CAPTURE: HEAD within 10deg, was 20deg. Sun/Mercury are always close
	# together in the sky, and Venus is nearby, so 20deg let a look at the Sun pick Mercury
	# or Venus instead. At 10deg a look between two bodies says Not sure instead of picking wrong.
	# vc122 required hand within 15deg too, but a pinch hand sits below eye level, so the
	# intended planet failed and Capella / a neighbour won instead - the vc124 wrong-planet bug.
	# Hand-only picks are still blocked: if head is not on a body within 20deg, nothing brings.
	for c: Dictionary in candidates:
		var gang: float = _angle_between(gaze, c["dir"])
		var pang: float = _angle_between(pinch_dir, c["dir"]) if pinch_dir != Vector3.ZERO else gang
		if gang < closest_angle:
			closest_angle = gang
			closest = c
		# vc180: AIM ray within 6 deg (sky planets are drawn ~1.7 deg wide,
		# Sun/Moon ~0.5 deg; 6 deg covers fingertip parallax, not neighbours).
		if c["kind"] == "body" and pang < 6.0 and pang < body_best_angle:
			body_best_angle = pang
			body_best = c
	if not body_best.is_empty() and body_best_angle < 6.0:
		best = body_best
		best_angle = body_best_angle
		second_angle = 999.0
	# vc67 STELLAR ANCHORS: Sirius + 9 new stars from user database 2026-10-29 21:42.
	# Any star with a USER_STAR_DESCRIPTIONS entry is clickable like planets, same
	# name / typing captions / voice-after-typing. Other stars stay NOT clickable.
	if best.is_empty() and _sky != null:
		for _item: Dictionary in _sky.named_star_directions():
			var _sname: String = str(_item.get("name", ""))
			if USER_STAR_DESCRIPTIONS.has(_sname):
				if _item["dir"].y < 0.0 and not (gaze.y < -0.087 or pinch_dir.y < -0.087):
					continue  # vc75 FULL SKY: below-horizon stars only when looking down
				var _sang: float = _angle_between(aim, _item["dir"])  # vc180 aim ray
				# vc129: stars are points - 10deg still captured Capella by accident.
				# Stars now need HEAD within 5deg. Planets stay 10deg (vc128), comet 20deg.
				if _sang < 4.0:
					select_object(_sname)
					_show_panel_for({"name": _sname, "kind": "star", "entry": _item})
					return true
	else:
		# vc125: second pass is gaze-only, same as first pass. Hand never steals a gaze pick.
		for c: Dictionary in candidates:
			var ang: float = _angle_between(aim, c["dir"])  # vc180 aim ray, was head gaze
			if ang < best_angle:
				second_angle = best_angle
				second = best
				best_angle = ang
				best = c
			elif ang < second_angle:
				second_angle = ang
				second = c
	if best.is_empty():
		# vc169 PINCH ACCURACY (user 2026-11-03): no more "Not sure" dead end.
		# A pinch at a planet must land on a planet, even if head aim is a
		# few degrees outside the old 10 deg capture. Pick the closest body
		# within 20 deg (vc170); farther than that, show nothing at all.
		# (planets/Moon/Sun only - stars are never candidates here), show its
		# panel and bring it to you, exactly like a clean pinch. Only when
		# there is no candidate at all (no bodies loaded) does it do nothing.
		if true:  # vc180: 20 deg "closest wins" fallback OFF - it made planets pop up on misses
			# vc170 (Claude prompt, user 2026-11-03): when nothing is under
			# the pinch, show NOTHING - no panel change, no "Not sure" text,
			# no voice. Closest within 20 deg still wins (wider than the old
			# 10 deg capture that kept missing real pinches).
			return false
		select_object(closest["name"])
		_show_panel_for(closest)
		if _teacher != null:
			_teacher.ask_about_selected(closest["name"])
		return true
	# vc38: old 1.0 deg star rule failed constantly in dense fields
	# (vc37 videos: repeated "Two objects" even after moving head).
	# New rule: fail only if second is within 0.5 deg AND the best
	# star is not clearly brighter (mag at least 1.0 lower).
	# A bright star you are aiming at wins a close tie; a 0.5-1.0
	# deg gap now picks the closest, it no longer fails.
	var _star_ambiguous: bool = false
	if second_angle - best_angle < 0.5:
		_star_ambiguous = true
		if best.get("kind", "") == "star" and second.get("kind", "") == "star":
			var _bm: float = float(best.get("entry", {}).get("mag", 99.0))
			var _sm: float = float(second.get("entry", {}).get("mag", 99.0))
			if _sm - _bm >= 1.0:
				_star_ambiguous = false
	# vc40: no more star dead end. Closest star wins, even if a
	# second star is within 0.5 deg. Panel shows its real name,
	# RA/Dec, Alt/Az, so a wrong pick is visible and a re-pinch
	# with the head moved a little picks the other one.
	select_object(best["name"])
	_show_panel_for(best)
	if _teacher != null:
		_teacher.ask_about_selected(best["name"])
	return true

func _on_teacher_answer(_object_name: String, answer: String, source_label: String) -> void:
	if _zodiac_wait_obj != "" and _object_name == _zodiac_wait_obj:
		var _sg: String = _zodiac_wait_obj.trim_prefix("Zodiac ")
		_zodiac_wait_obj = ""
		if source_label != "local" and _teacher_speech != null and _teacher_speech.has_method("enqueue"):
			_teacher_speech.enqueue("Here is today's horoscope for " + _sg + ", just for fun. " + answer)
		return
	# vc121: a voice-asked teacher answer DOES go on screen, pinch teacher
	# answers stay hidden under vc57 CLEAN. Flag clears on first answer.
	if _voice_teacher_pending and (_object_name == selected_object or _object_name == _voice_teacher_object) and _panel != null:
		_voice_teacher_pending = false
		_panel.show_teacher(answer, source_label)
		# vc142 SPOKEN TEACHER via audio stream: relay /speak MP3 chunks
		# played through AudioStreamMP3, like planet voices. No
		# DisplayServer TTS (vc139 crash). vc141 wired the node but
		# NEVER CALLED speak() - this call was missing, so no voice.
		if _teacher_speech != null and _teacher_speech.has_method("speak"):
			_teacher_speech.speak(answer)
		return
	# vc42 panel cleanup: a late answer for an OLD object must never
	# land on the NEW object's panel (vc41 video: Moon facts + 42 Per
	# answer stacked, 55 Ari + Lili Borea stacked). Drop it silently.
	if _object_name != selected_object:
		return
	# vc57 CLEAN: teacher answer does NOT go on screen for playtest — no long words in the way.
	pass

func _on_teacher_ask_started(_object_name: String) -> void:
	if _voice_teacher_pending and (_object_name == selected_object or _object_name == _voice_teacher_object) and _panel != null:
		_panel.show_teacher_asking()
	if _object_name != selected_object:
		return
	# v23 interim state only: while the teacher call (and any
	# retries) is in flight, the panel says it is asking — never
	# offline on the first failure. Lock/identify flow untouched.
	# vc57 CLEAN: no 'Teacher asking' words on screen.
	pass

# Million-dollar telescope feel: every body gets a real, short
# description, not just numbers. Facts are public NASA-level
# basics, kept to one line so the panel stays readable in 2 seconds.
const PLANET_FACTS: Dictionary = {
	"Sun": "The Sun, a ball of plasma holding 99.8% of our solar system's mass. Visible surface about 5,772 K, core about 15 million K, outer corona over 1 million K. About 109 Earths wide. The equator turns in about 25 days, the poles in about 35 — the surface you see here boils, drifts, and flares, all made in the app, no photo.",
	"Moon": "Earth's moon. 3,474 km wide, about 384,400 km away. One orbit: 27.3 days.",
	"Mercury": "Mercury is a scarred, airless world of extreme contrast, cooked by proximity to the sun and frozen by the vacuum of space. Visually, it presents a stark, heavily cratered slate-grey and ash landscape that closely resembles Earth's moon under a star-filled black sky. Because it lacks a heat-trapping atmosphere, temperatures swing violently from a blistering 800°F (430°C) during the day to a bone-chilling -290°F (-180°C) at night, with low gravity at 38% of Earth's baseline.",
	"Venus": "Venus is a runaway greenhouse nightmare, a toxic and suffocating pressure cooker hidden beneath an unbroken shroud of acid clouds. Visually, the planet's surface is a dim, orange-crushed wasteland of volcanic basalt and glowing lava flows, illuminated by sickly yellow light filtering through thick carbon dioxide mist. It is the hottest planet in the solar system, maintaining a uniform, lethal temperature of 867°F (464°C) alongside an atmospheric pressure 92 times greater than Earth's—enough to instantly crush a standard hull.",
	"Mars": "Mars is the top candidate for humanity's first off-world colony due to its solid surface, 24.6-hour day, and massive reserves of underground water ice. Visually, the planet is defined by its iconic butterscotch-and-rust landscape, painted by iron oxide dust under a pinkish-tan sky. It is a bitterly cold desert world, with a hostile average temperature of -80°F (-62°C), a toxic carbon dioxide atmosphere, and a light gravity pull just 38% of Earth's baseline.",
	"Jupiter": "Jupiter is a screaming planetary engine, a colossal gas giant that contains more than twice the mass of all other planets combined. Visually, it is a turbulent, swirling canvas of crimson, cream, and ochre storm bands, dominated by the Great Red Spot—a counter-clockwise hurricane twice the width of Earth. It features a freezing average temperature of -166°F (-110°C), lethal levels of localized radiation, and a crushing gravity well that exerts 2.4 times Earth's baseline force.",
	"Saturn": "Saturn is the jewel of the solar system, a colossal gas giant defined by its magnificent and expansive ring architecture. Visually, the planet displays a muted, banded palette of butterscotch, gold, and light amber hues, orbited by a sweeping, translucent disc of billions of shimmering water-ice tracks and cosmic dust. It is a frozen, lightweight giant with a hostile average temperature of -288°F (-178°C), devastating equatorial winds peaking at 1,100 mph (1,800 km/h), and a vast domain of over 140 moons.",
	"Uranus": "Uranus is a pale, eccentric ice giant that rolls through its orbit entirely on its side due to a prehistoric cosmic collision. Visually, the planet appears as a featureless, serene aquamarine and pale cyan sphere, surrounded by a subtle, vertical ring system and a dim entourage of icy moons. It is a deeply frozen world with an atmospheric temperature averaging -320°F (-195°C), choked by a dense haze of hydrogen, helium, and methane gases swirling over a vast mantle of slushy water and ammonia ice.",
	"Neptune": "Neptune is the solar system's ultimate frontier, a massive, hyper-velocity ice giant cloaked in perpetual shadow. Visually, the planet is a mesmerizing, deep cobalt-and-sapphire blue caused by methane gas absorption, featuring brilliant white high-altitude clouds and violent, dark storm systems. It reigns as the coldest and windiest world in the system, with a crushing average temperature of -353°F (-214°C) and supersonic atmospheric winds that rip through the methane-ammonia fog at speeds exceeding 1,200 miles per hour (2,000 km/h).",
}
const USER_STAR_DESCRIPTIONS: Dictionary = {
	"Sirius": "Sirius is a blinding binary star system that shines as the brightest star in Earth's night sky, located just 8.6 light-years away. Visually, it is famous for a chaotic rainbow-twinkling effect, rapidly shifting color from ice-blue and diamond-white to vivid flashes of red, yellow, and green due to atmospheric turbulence fracturing its immense brightness. It is a stellar powerhouse with a blistering surface temperature of 17,400°F (9,650°C), radiating over 25 times the luminosity of the Sun and emitting intense, high-energy ultraviolet radiation across its local stellar sector.",
	"Canopus": "Canopus reigns as the second-brightest star in the night sky, acting as a critical navigational beacon for spacecraft tracking through the southern hemisphere. Visually, it glows with a stark, steady yellowish-white radiance, cutting through space with immense power as a massive yellow-white supergiant. Its surface burns at 13,000°F (7,200°C), and it pumps out an astonishing 10,000 times the energy of the Sun, anchoring a vital cosmic crossroads 310 light-years away.",
	"Rigil Kentaurus": "Alpha Centauri is the closest star system to Earth, positioned a mere 4.37 light-years away and serving as humanity's primary target for future interstellar travel. Visually, it merges into a single warm golden-yellow point to the naked eye, though it is actually a tight trio of stars consisting of two sun-like stars and a dim red dwarf (Proxima Centauri). The primary star has a surface temperature of 10,000°F (5,500°C) and features a gravitational profile nearly identical to Earth's home sun.",
	"Arcturus": "Arcturus is a bloated, high-velocity orange giant star that is rapidly cutting through our galactic neighborhood just 37 light-years away. Visually, it pierces the night sky with a distinct, glowing burnt-orange and amber hue, marking its status as a dying star that has expanded to 25 times its original size. It operates at a cooler surface temperature of 7,300°F (4,000°C) but blazes with 170 times the Sun's brightness, signaling its entry into the final stages of its evolutionary life cycle.",
	"Vega": "Vega is a hyper-spinning, diamond-sharp star that serves as the baseline zero-point metric for calibrating astronomical brightness scales. Visually, it emits a piercing, icy electric-blue and sapphire flare, spinning so fast on its axis that its equator bulges outward into an oval shape. It maintains a scorching surface temperature of 17,000°F (9,400°C), burns 40 times brighter than the Sun, and is encircled by a massive, chaotic ring of dust and debris that may be forming a new planetary system 25 light-years away.",
	"Capella": "Capella is a high-mass quadruple star system functioning as the golden north-sky anchor, located 43 light-years from Earth. Visually, it merges into a singular, bright warm yellow and rich cream beacon, masking a violent dance between two giant yellow stars orbiting each other every 104 days. Its primary components burn at a surface temperature of 9,000°F (5,000°C), combining to blast out over 80 times the Sun's radiant energy.",
	"Rigel": "Rigel is a monstrous blue supergiant anchoring the foot of the Orion system, acting as a hyper-luminous lighthouse 860 light-years away. Visually, it pierces space with a violent, piercing electric-blue and hyper-white glare of unmatched intensity. It is an evolutionary ticking time bomb with a scorching surface temperature of 21,000°F (11,600°C), flooding its sector with 120,000 times the Sun's raw power.",
	"Procyon": "Procyon is a bloated, subgiant stellar neighbor sitting right on humanity's cosmic doorstep just 11.4 light-years out. Visually, it casts a pale, steady yellowish-white tint, slowly running out of core hydrogen fuel and beginning its expansion into a giant. It maintains a surface temperature of 11,200°F (6,200°C) and burns with a localized intensity 7 times brighter than the Sun.",
	"Betelgeuse": "Betelgeuse is a titanic red supergiant on the absolute brink of a spectacular, civilization-altering supernova explosion. Visually, it burns with an ominous, unsteady ruby-red and deep cinnamon pulse, wildly fluctuating in brightness as it rhythmically destabilizes 550 light-years away. It is so massive that if placed in our solar system, it would swallow everything up to Jupiter, though its surface is a relatively cool 6,000°F (3,300°C) despite pumping out 100,000 times the Sun's luminosity.",
	"Achernar": "Achernar is a cosmic anomaly, a hyper-velocity blue star that is the flattest, most distorted stellar object in the known sky. Visually, it flashes with a bright blue-white luminescence, though its rapid spin causes its equator to bulge out into a flattened, spinning top shape. Burning at a searing 26,500°F (14,700°C), this energetic powerhouse generates 3,000 times the Sun's energy output 140 light-years away.",
}

# vc77 SHORT DESCRIPTIONS (user 2026-10-30: descriptions shorter, voice shorter).
# Trimmed from the full user descriptions, facts/numbers kept, florid filler cut.
# Display and voice both use these short versions now; full versions stay in PLANET_FACTS / USER_STAR_DESCRIPTIONS for reference.
const SHORT_PLANET_FACTS: Dictionary = {
	"Sun": "The Sun, plasma holding 99.8% of our solar system's mass. Surface about 5,772 K, about 109 Earths wide, equator turns in 25 days, poles in 35.",
	"Moon": "Earth's moon. 3,474 km wide, about 384,400 km away. One orbit: 27.3 days.",
	"Mercury": "Mercury is a scarred, airless world, cratered and grey like our Moon. Days hit 800°F, nights drop to -290°F, with gravity just 38% of Earth's.",
	"Venus": "Venus is a toxic pressure cooker under acid clouds. It is the hottest planet, 867°F everywhere, with pressure 92 times Earth's.",
	"Mars": "Mars is the top candidate for humanity's first off-world colony, butterscotch-and-rust from iron oxide dust. It averages -80°F, with a thin carbon dioxide atmosphere and gravity 38% of Earth's.",
	"Jupiter": "Jupiter is a colossal gas giant, more than twice the mass of all other planets combined. Its Great Red Spot is a storm twice as wide as Earth, and it averages -166°F.",
	"Saturn": "Saturn is the ringed jewel, a frozen gas giant at -288°F, with winds up to 1,100 mph and over 140 moons.",
	"Uranus": "Uranus is a pale ice giant that rolls on its side. It averages -320°F, with a methane haze over slushy water and ammonia ice.",
	"Neptune": "Neptune is a deep cobalt ice giant, the coldest and windiest world. It averages -353°F, with supersonic winds over 1,200 mph.",
}
const SHORT_STAR_DESCRIPTIONS: Dictionary = {
	"Sirius": "Sirius is the brightest star in Earth's night sky, just 8.6 light-years away. It burns at 17,400°F, 25 times brighter than the Sun, with a rainbow twinkle.",
	"Canopus": "Canopus is the second-brightest star, a yellow-white supergiant 310 light-years away. It burns at 13,000°F, 10,000 times brighter than the Sun.",
	"Rigil Kentaurus": "Alpha Centauri is the closest star system, just 4.37 light-years away. It is a trio of stars, with the primary burning at 10,000°F.",
	"Arcturus": "Arcturus is an orange giant 37 light-years away, burnt-orange and 25 times the Sun's size. It burns at 7,300°F, 170 times brighter than the Sun.",
	"Vega": "Vega is an icy electric-blue star 25 light-years away, spinning so fast its equator bulges. It burns at 17,000°F, 40 times brighter than the Sun.",
	"Capella": "Capella is a golden quadruple star system 43 light-years away. Two giant stars orbit every 104 days, burning at 9,000°F, 80 times brighter than the Sun.",
	"Rigel": "Rigel is a blue supergiant in Orion, 860 light-years away. It burns at 21,000°F, 120,000 times brighter than the Sun.",
	"Procyon": "Procyon is a pale yellowish-white neighbour just 11.4 light-years away. It burns at 11,200°F, 7 times brighter than the Sun.",
	"Betelgeuse": "Betelgeuse is a ruby-red supergiant 550 light-years away, near supernova. It burns at 6,000°F, 100,000 times brighter than the Sun, and would swallow everything up to Jupiter.",
	"Achernar": "Achernar is the flattest star, a blue-white spinner 140 light-years away. It burns at 26,500°F, 3,000 times brighter than the Sun.",
}
const SPECTRAL_MEANING: Dictionary = {
	"O": "blue, hottest stars", "B": "blue-white, very hot", "A": "white, hot",
	"F": "yellow-white", "G": "yellow, like our Sun", "K": "orange, cooler", "M": "red, coolest stars",
}


func _on_typing_finished() -> void:
	# vc67: user 2026-10-29 21:45-21:46 EDT — finish typing FIRST, then AI reads.
	# Typing sound is now short (60cps), desc voice starts only after typing is done.
	if _pending_desc == "":
		return
	var _dname: String = _pending_desc
	_pending_desc = ""
	if _voice != null:
		_voice.play_voice("voice_%s_desc" % _dname.to_lower().replace(" ", "_"))
		_desc_playing = true

func _on_voice_finished() -> void:
	# vc78 FADE: desc voice just ended, so user has finished hearing the description. Give 2 sec to finish reading, then fade panel out.
	if not _desc_playing:
		return
	_desc_playing = false
	if _panel != null:
		_panel.fade_out_after_voice()

func _play_pinch_click() -> void:
	# vc64: user-supplied pinch success sound, plays once on a successful pinch.
	if _sfx == null:
		return
	var _stream: AudioStream = load("res://data/sounds/own/sound_pinch_click_own.wav")
	if _stream != null:
		_sfx.stop()
		_sfx.stream = _stream
		_sfx.play()

## vc116: solar-system view toggle for 3I/ATLAS. The view node is in the
## scene but hidden by default — there is no existing solar-system mode
## in the app to hook a VR button into yet, so this method is the toggle
## until a VR control is added. It does not hide the sky by itself.
func toggle_atlas_system_view() -> void:
	if _atlas_system == null:
		return
	_atlas_system.visible = not _atlas_system.visible
	if _atlas_system.visible and _atlas_system.has_method("set_scrub_unix"):
		_atlas_system.set_scrub_unix(Time.get_unix_time_from_system())

func _show_panel_for(obj: Dictionary) -> void:
	if _panel == null:
		return
	_desc_playing = false  # vc78: new planet, old desc voice (if any) is superseded
	# vc116 3I/ATLAS: panel text from AtlasInfo, live distances from ephemeris.
	# No voice name file exists for it, so no play_voice call here.
	if obj.get("kind", "") == "atlas":
		if _planets != null:
			_planets.clear_focus()
		selected_object = "3I/ATLAS"
		# vc167 REVERT: old description method, user 2026-11-03 — no InfoPanel.
		if _atlas != null:
			_panel.set_anchor(_atlas, 1.7)
			if _panel.has_method("set_panel_scale"):
				_panel.set_panel_scale(1.0)
			if _panel.has_method("set_face_panel_mode"):
				_panel.set_face_panel_mode(true)
			if _panel.has_method("set_desc_width"):
				_panel.set_desc_width(600)
			_panel.show_name_desc("3I/ATLAS", AtlasInfo.short_panel_text(Ephemeris.now_jd()))
		_play_pinch_click()
		return
	# vc131 ISS panel: bring to front like atlas, panel anchored to the station.
	if obj.get("kind", "") == "iss":
		if _planets != null:
			_planets.clear_focus()
		if _atlas != null and _atlas.brought:
			_atlas.send_back()
		selected_object = "ISS"
		if _iss != null and _camera != null:
			_iss.bring_to_front(_camera)
			# vc167 REVERT: old description method, user 2026-11-03 — no InfoPanel.
			_panel.set_anchor(_iss, 2.5)
			if _panel.has_method("set_panel_scale"):
				_panel.set_panel_scale(1.0)
			if _panel.has_method("set_face_panel_mode"):
				_panel.set_face_panel_mode(false)
			if _panel.has_method("set_desc_width"):
				_panel.set_desc_width(600)
			var _iss_detail: String = "ISS, International Space Station. 109 m wide, about 420 km up, 7.66 km/s, 93 minutes per orbit. Right now %.0f km from you%s.\nIn the sky it is a bright moving point, like a star. This model is shrunk about 30 times.\nTLE 2026-11-02, position approximate, not live tracking. Pinch again to put it back." % [float(_iss.get("range_km")), "" if bool(_iss.get("sunlit")) else ", in Earth's shadow"]
			if _voice_heard != "":
				_iss_detail = "I heard: " + _voice_heard + "\n" + _iss_detail
				_voice_heard = ""
			_panel.show_name_desc("ISS", _iss_detail)
	if obj.get("kind", "") == "earth":
		# vc158: Earth is NOT in the main sky anymore — you stand on Earth, so showing it overhead makes no sense. It only appears overhead when you travel to another planet.
		selected_object = "Earth"
		var _earth_detail: String = "Earth, our home. 12,742 km wide, 71% ocean, one Moon, one Sun at 1 AU.\nYou are standing on Earth, so it is under your feet, not in the sky. Travel to the Moon or another planet and look up — that is where Earth belongs, as a photo-real blue dot overhead."
		if _voice_heard != "":
			_earth_detail = "I heard: " + _voice_heard + "\n" + _earth_detail
		_panel.show_name_desc("Earth", _earth_detail)
		return
		_play_pinch_click()
		return
	# Any other object sends a brought comet back to the sky, like switching planets.
	if _atlas != null and _atlas.brought:
		_atlas.send_back()
	if _iss != null and bool(_iss.get("brought")):
		_iss.send_back()
	if _earth != null and bool(_earth.get("brought")):
		_earth.send_back()
	# vc67 STARS: name in cool font + typing captions, voice says name now,
	# desc voice AFTER typing finishes (typing_finished signal, vc67 user spec).
	# Star orb shows in room at eye level, 1.5m in front (was 3m at ground level).
	if obj.get("kind", "") in ["sirius", "star"]:
		var _sname2: String = str(obj.get("name", "Sirius"))
		if _planets != null:
			_planets.clear_focus()
		_show_star_orb(obj["entry"])
		# vc167 REVERT: old description method, user 2026-11-03 — no InfoPanel.
		if _panel != null and _star_orb != null:
			_panel.set_anchor(_star_orb, 0.9)
			if _panel.has_method("set_panel_scale"):
				_panel.set_panel_scale(1.0)
		selected_object = _sname2
		_panel.show_name_desc(_sname2, str(SHORT_STAR_DESCRIPTIONS.get(_sname2, USER_STAR_DESCRIPTIONS.get(_sname2, ""))))
		_play_pinch_click()
		_pending_desc = _sname2
		if _voice != null:
			_voice.play_voice("voice_%s_name" % _sname2.to_lower().replace(" ", "_"))
		return
	var name: String = obj["name"]
	var detail: String = ""
	if obj["kind"] == "body":
		_clear_star_orb()
		# vc83 REVERSE (sky path): re-pinching a brought planet sends it back, not a new panel.
		if _planets != null and _planets.is_brought(name):
			_planets.send_back(name)
			_planets.clear_focus()
			selected_object = ""
			_desc_playing = false
			_pending_desc = ""  # vc94: reverse stops the voice, not just the words
			if _voice != null and _voice.has_method("stop_all"):
				_voice.stop_all()
			elif _voice != null:
				_voice.stop()
			if _panel != null:
				_panel.stop_typing()
				_panel.fade_out_now()  # vc87: words fade away as the planet goes back
			return
		# vc55 USER SPEC 2026-10-29: pinch = highlight + name ONLY.
		# NO bring-to-you on pinch, NO telescope/auto zoom on pinch.
		# Planet stays where it is. Zoom ONLY manually via the dial.
		# Voice show-me is the ONLY path that brings a planet to you,
		# via _bring_to_you_next (set in show_body_by_name).
		if _planets != null:
			_planets.clear_travel()
			_planets.clear_telescope()
			# vc56 PLAYTEST: pinch BRINGS it to you, always. No manual dial zoom.
			_planets.bring_to_front(name)
			_planets.select_body(name)
			# vc167 REVERT: old description method, user 2026-11-03 — no InfoPanel.
			# Panel scale back to 1.0 (vc161 2.0x/3.33x was for the bigger planets, now reverted).
			if _panel != null:
				var _pn: Node = _planets.get_node_or_null(name)
				if _pn != null:
					if _panel.has_method("set_panel_scale"):
						_panel.set_panel_scale(1.0)
					_panel.set_anchor(_pn, _planets.target_brought_radius(name) + 0.5)
					if _panel.has_method("set_face_panel_mode"):
						_panel.set_face_panel_mode(false)
		_bring_to_you_next = false
		selected_object = name
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
		# vc56 PLAYTEST panel: name + one fact only, big and simple for first-time users.
		if name == "Moon":
			detail = "The Moon is humanity's primary stepping stone into deep space and the only other celestial body ever visited by humans. Visually, it features a stark, monochromatic charcoal-and-silver landscape peppered with bright white impact craters under a perpetually pitch-black sky. Lacking a protective atmosphere, it suffers from violent temperature swings ranging from a scorching 250°F (121°C) in direct sunlight to a freezing -208°F (-133°C) in the dark, with gravity that is just 16% (one-sixth) of Earth's baseline."
		else:
			var fact: String = str(SHORT_PLANET_FACTS.get(name, PLANET_FACTS.get(name, "")))
			if fact != "":
				detail = "%s" % fact  # vc77 SHORT
			else:
				detail = name
	else:
		# Step 1 (Muse Code, cherry-picked): a star pick must never
		# leave a planet glow on (wrong object). Planet focus off,
		# star orb owns the room.
		if _planets != null:
			_planets.clear_focus()
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
		var spect_mean: String = ""
		if spect != "" and SPECTRAL_MEANING.has(spect[0]):
			spect_mean = " — " + str(SPECTRAL_MEANING[spect[0]])
		if _star_orb_name == name and _star_orb != null:
			_clear_star_orb()
			detail = "%s\nStar orb back in the sky" % name
		else:
			_show_star_orb(entry)
			detail = "%s%s%s%s, mag %.1f\n%.0f light years away\nRA %.2fh Dec %.2f°\nAlt %.1f° Az %.1f°\nPinch again to put it back" % [name, con_str, spect_str, spect_mean, entry.get("mag", 0.0), dist_ly, entry.get("ra_h", 0.0), entry.get("dec_deg", 0.0), aa.get("alt", 0.0), aa.get("az", 0.0)]
	if obj["kind"] == "body":
		# vc75 FULL SKY: label below-horizon picks clearly, so a Sun under the ground is never mistaken for sky above.
		if _planets != null and _planets.body_directions().has(name) and _planets.body_directions()[name].y < 0.0:
			detail = "Below horizon right now — under the ground, not in the sky above you.\n" + detail
		if _panel.has_method("set_desc_width"):
			_panel.set_desc_width(300)
		# vc125 HEARD CONFIRMATION: show the exact transcribed words at the top of the
		# planet panel, so a show-me command is confirmed instead of being overwritten.
		if _voice_heard != "":
			detail = "I heard: " + _voice_heard + "\n" + detail
			_voice_heard = ""
		_panel.show_name_desc(name, detail)
		_play_pinch_click()
		_pending_desc = name
		if _voice != null:
			_voice.play_voice("voice_%s_name" % name.to_lower().replace(" ", "_"))
	else:
		_panel.show_object(name, detail)

func _travel_detail(name: String) -> String:
	# Honest travel labels — a wrong label fails the whole step.
	# Mars alone is REAL (Curiosity panorama). The rest are
	# SIMULATED: real colours and clouds from each globe's own
	# scan, no invented ground, gas giants floating (no floor).
	var back: String = "Pinch again to go back"
	if name == "Mars":
		return "Mars\nYOU ARE THERE — procedural 3D world\nBuilt in Godot, no photo, no panorama\nRed rocky plain, butterscotch sky\nNot live — " + back
	if name == "Moon":
		return "Moon\nYOU ARE THERE — procedural 3D world\nBuilt in Godot, no photo, no panorama\nGray regolith, black sky, Earth overhead\nNot live — " + back
	if name == "Mercury":
		return "Mercury\nYOU ARE THERE — simulated, orbiting above\nGray cratered world, colours from real scans\nNo real panorama exists — " + back
	if name == "Venus":
		return "Venus\nYOU ARE THERE — simulated, floating in the clouds\nCreamy cloud deck, circles in 4 Earth days\nNever the ground — no surface panorama exists\n" + back
	if name == "Jupiter":
		return "Jupiter\nYOU ARE THERE — simulated cloud deck\nCream and rust bands beneath your feet\nGreat Red Spot world, imagined from real scans\nNo solid ground exists here — " + back
	if name == "Saturn":
		return "Saturn\nYOU ARE THERE — floating inside the A ring\nIce chunks from pebbles to houses, Saturn 55 deg wide\nReal ring sizes, simulated chunk layout\n" + back
	if name == "Sun":
		return "The Sun\nYOU ARE THERE — on the photosphere, 5,500 C\nBoiling granules, a sunspot, jets and arches of plasma\nArtistic: the Sun has no solid surface\n" + back
	if name == "Uranus":
		return "Uranus\nYOU ARE THERE — simulated cloud deck\nPale cyan calm, tipped on its side\nSun a cold spark, 19 times farther than Earth\nImagined — no solid ground here — " + back
	if name == "Neptune":
		return "Neptune\nYOU ARE THERE — simulated cloud deck\nDeep blue, winds over 2,000 km/h\nSun a bright star, 30 times farther than Earth\nImagined — no solid ground here — " + back
	return name + "\nYOU ARE THERE — simulated\n" + back

func _show_star_orb(entry: Dictionary) -> void:
	_clear_star_orb()
	var orb: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	# Brighter = bigger orb. Mag -1.44 (Sirius) -> 0.30 m,
	# mag 6 -> 0.06 m. Same scale logic as sky points, larger
	# so it reads as an object in the room, not a dot.
	var r: float = clamp(0.30 - float(entry.get("mag", 3.0)) * 0.04, 0.06, 0.45)
	# vc182 (user 2026-11-04): a pinched star now looks like a real star,
	# made like the Sun: the same animated surface (boiling granulation,
	# limb darkening) and corona shaders as the Sun, recoloured to the
	# star's real colour (blue-white, yellow, orange, red). Stars are too
	# far for their surface to be seen; this is a simulated close-up.
	var col: Color = entry.get("color", Color(1.0, 1.0, 1.0))
	var white: Color = col.lerp(Color(1, 1, 1), 0.65)
	sphere.radius = r * 0.9
	sphere.height = r * 1.8
	sphere.radial_segments = 48
	sphere.rings = 24
	orb.mesh = sphere
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = load("res://sun_surface.gdshader")
	smat.set_shader_parameter("quality", 1)
	smat.set_shader_parameter("col_deep", Vector3(col.r * 0.35, col.g * 0.30, col.b * 0.30))
	smat.set_shader_parameter("col_mid", Vector3(col.r * 0.85, col.g * 0.80, col.b * 0.80))
	smat.set_shader_parameter("col_hot", Vector3(lerp(col.r, white.r, 0.4), lerp(col.g, white.g, 0.4), lerp(col.b, white.b, 0.4)))
	smat.set_shader_parameter("col_white", Vector3(white.r, white.g, white.b))
	smat.set_shader_parameter("whiteness", 0.45)
	orb.material_override = smat
	var corona: MeshInstance3D = MeshInstance3D.new()
	var cq: QuadMesh = QuadMesh.new()
	cq.size = Vector2.ONE * r * 0.9 * 2.0 * 4.0
	corona.mesh = cq
	var cmat: ShaderMaterial = ShaderMaterial.new()
	cmat.shader = load("res://sun_corona.gdshader")
	cmat.set_shader_parameter("quad_radius_in_suns", 4.0)
	cmat.set_shader_parameter("halo_color", Vector3(col.r, col.g, col.b))
	cmat.set_shader_parameter("streamer_color", Vector3(white.r, white.g, white.b))
	cmat.set_shader_parameter("prom_color", Vector3(col.r * 0.95, col.g * 0.6, col.b * 0.5))
	corona.material_override = cmat
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(corona)
	var _sptex: Texture2D = load("res://data/sky/star_spike.png")
	if _sptex != null:
		var _spsp: Sprite3D = Sprite3D.new()
		_spsp.texture = _sptex
		_spsp.modulate = col
		_spsp.pixel_size = 0.02
		_spsp.scale = Vector3(r * 8.0, r * 8.0, r * 8.0)
		orb.add_child(_spsp)
	var _comp: Dictionary = {"Sirius": Color(0.65, 0.75, 1.0), "Rigil Kentaurus": Color(1.0, 0.65, 0.35)}
	var _oname: String = str(entry.get("name", ""))
	if _comp.has(_oname):
		var _cmesh: SphereMesh = SphereMesh.new()
		_cmesh.radius = r * 0.25
		_cmesh.height = r * 0.5
		var _corb: MeshInstance3D = MeshInstance3D.new()
		_corb.mesh = _cmesh
		var _cmat: StandardMaterial3D = StandardMaterial3D.new()
		_cmat.albedo_color = _comp[_oname]
		_cmat.emission_enabled = true
		_cmat.emission = _comp[_oname]
		_cmat.emission_energy_multiplier = 2.0
		_cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_corb.material_override = _cmat
		_corb.position = Vector3(r * 1.2, r * 0.3, 0.0)
		orb.add_child(_corb)
	# vc67: orb at eye level, 1.5m in front of camera, world space — was (0,0,-3) at ground level.
	if _camera != null:
		orb.global_position = _camera.global_position + _camera.global_transform.basis * Vector3(0.0, 0.0, -1.5)
	else:
		orb.position = Vector3(0.0, 1.6, -1.5)
	add_child(orb)
	if _camera != null:
		orb.global_position = _camera.global_position + _camera.global_transform.basis * Vector3(0.0, 0.0, -1.5)
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

# Voice command, Phase 1 2026-10-29: "show me Mars" / "show me the Moon"
# does exactly what pinching that body does: show panel, bring it to you,
# say its name + description (voice files for planets, teacher text for stars).
# This is called once speech-to-text text arrives (Phase 2 engine, not yet built).
# Until then, do NOT pretend voice works - if this is called with a bad name, it says Not sure.
func show_body_by_name(body_name: String) -> bool:
	if body_name == "ISS":
		select_object("ISS")
		_show_panel_for({"name": "ISS", "kind": "iss"})
	if body_name == "Earth":
		select_object("Earth")
		_show_panel_for({"name": "Earth", "kind": "earth"})
		return true
		return true
	if body_name == "" or _planets == null:
		return false
	# Bodies only in Phase 1, stars later.
	var known: Array = ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]
	if body_name not in known:
		# vc169: "Not sure" panel removed (user 2026-11-03). Unknown voice
		# names just do nothing instead of showing that message.
		return false
	select_object(body_name)
	_bring_to_you_next = true
	_show_panel_for({"name": body_name, "kind": "body"})
	if _teacher != null:
		_teacher.ask_about_selected(body_name)
	return true


# vc180 SKY SYNC: "sync moon" / "sync sun" by voice skips the menu, shows the ring.
func _try_voice_sync(low: String) -> bool:
	if _sky_sync == null or not (low.contains("sync") or low.contains("sink")):
		return false
	if low.contains("moon"):
		_sky_sync.start_aim("Moon")
	elif low.contains("sun") or low.contains("son"):
		_sky_sync.start_aim("Sun")
	else:
		_sky_sync.open_menu()
	if _voice != null:
		_voice.play_sound("sound_click")
	return true

# vc180 SKY SYNC result: turn the whole sky so the virtual Moon/Sun sits
# exactly under the ring. Yaw only; height comes from time + location.
func _on_sky_synced(yaw_deg: float, body: String, alt_error_deg: float) -> void:
	yaw_offset_deg = yaw_deg
	alt_offset_deg = 0.0
	_apply_yaw()
	_debug_locked = true
	if _sky != null and _sky.has_method("_update_sky"):
		_sky.call("_update_sky", true)
	if _planets != null and _planets.has_method("_update_bodies"):
		_planets.call("_update_bodies", false)
	if _voice != null:
		_voice.play_sound("sound_click")
	if _panel != null:
		var _tdir: Vector3 = AstroMathScript.moon_world_dir(AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())["tt"], AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())["ut1"], _planets.lat_deg, _planets.lon_deg, 0.0, 0.0) if body == "Moon" else AstroMathScript.planet_world_dir("Sun", AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())["tt"], AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())["ut1"], _planets.lat_deg, _planets.lon_deg, 0.0, 0.0)
		var _up_deg: float = rad_to_deg(asin(clamp(_tdir.y, -1.0, 1.0)))
		_panel.show_object("Sky Sync", "%s synced to where you aimed.\nThe whole sky is turned to match. The %s is %.0f deg up right now, so look that high in that direction to see it." % [body, body, _up_deg])

func _on_sky_sync_message(text: String) -> void:
	if _panel != null:
		_panel.show_object("Sky Sync", text)


# vc181: is the LEFT palm turned toward your face? Palm normal from joint
# positions (wrist, index and little-finger knuckles), so it does not
# depend on any joint axis convention. Left hand: (index-wrist) x (little-wrist).
func _left_palm_facing_you() -> bool:
	if _camera == null:
		return false
	var t: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	if t == null:
		t = XRServer.get_tracker("/user/hand/left") as XRHandTracker  # vc195 fallback, same pattern as the hand-data check elsewhere
	if t == null or not t.has_tracking_data:
		return false
	var origin: Node3D = get_node_or_null("XROrigin") as Node3D
	var xf: Transform3D = origin.global_transform if origin != null else Transform3D.IDENTITY
	var w: Vector3 = xf * t.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
	var i: Vector3 = xf * t.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL).origin
	var l: Vector3 = xf * t.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL).origin
	var n: Vector3 = (i - w).cross(l - w)
	if n.length() < 0.00001:
		return false
	var palm: Vector3 = (i + l + w) / 3.0
	var to_eye: Vector3 = (_camera.global_position - palm).normalized()
	return n.normalized().dot(to_eye) > 0.55


# vc181 Talk to Teacher, started from the left-hand menu (AI TEACHER).
# Same steps the old floating Talk button ran; any pinch stops and sends.
func _start_talk() -> void:
	if _voice_listen == null or _voice_listen.is_listening():
		return
	if _teacher_speech != null and _teacher_speech.has_method("stop"):
		_teacher_speech.stop()
	var _started: bool = _voice_listen.start_listen()
	if _started:
		_listen_start_unix = Time.get_unix_time_from_system()
		_listen_panel_last = _listen_start_unix
	if _voice != null:
		_voice.play_sound("sound_click")

# vc181 Starship by voice only (no buttons). Needs "starship" / "star ship"
# in the sentence, so ordinary talk never triggers it.
#   "spawn starship"          -> appears, look at the ground, pinch to place
#   "launch starship"         -> launches (places it first if still aiming)
#   "reset / stop / remove starship" -> gone
#   "indoor / small starship" -> 1:10 model 8 m away
func _starship_voice(low: String) -> bool:
	if _starship == null or not (low.contains("starship") or low.contains("star ship")):
		return false
	var m: String = str(_starship.get("mode"))
	if low.contains("reset") or low.contains("stop") or low.contains("remove") or low.contains("cancel") or low.contains("clear"):
		_starship.reset_all()
	elif low.contains("indoor") or low.contains("small") or low.contains("mini"):
		if m == "off":
			_starship.set("indoor", true)
			_starship.start_placing()
		else:
			_starship.press_button("INDOOR")
	elif low.contains("launch") and (m == "placed" or m == "placing"):
		if m == "placing":
			_starship.place()
		_starship.start_launch()
	elif low.contains("spawn") or low.contains("launch"):
		if m == "off" or m == "launching":
			if m == "launching":
				_starship.reset_all()
			_starship.start_placing()
	else:
		return false
	if _voice != null:
		_voice.play_sound("sound_click")
	return true


# vc182 wake word. Speech-to-text writes "Star Bridge" many ways
# ("starbridge.", "Star bridge,", "star ridge", "start bridge", "stars bridge",
# "star fridge"), so match loosely on the letters. Returns what was said
# AFTER the wake word ("" if nothing), or "-" if there was no wake word.
var _wake_re: RegEx = null
func _wake_split(low: String) -> String:
	if _wake_re == null:
		_wake_re = RegEx.new()
		_wake_re.compile("(star|stars|start|starr|stab|stop)[\\s\\-,.]*(bridge|bridges|bridg|ridge|fridge|brich|britch|bridget)[\\s,.!?:;-]*")
	var m: RegExMatch = _wake_re.search(low)
	if m == null:
		var compact: String = ""
		for ch in low:
			if ch >= "a" and ch <= "z":
				compact += ch
		if compact.contains("starbridg") or compact.contains("starsbridg") or compact.contains("startbridg"):
			return ""
		return "-"
	return low.substr(m.get_end()).strip_edges()


# vc184 ZODIAC by voice: "show me Taurus", "show me Scorpio", "what is Leo",
# "hide the zodiac". Only a zodiac NAME triggers it, and only with show / see /
# zodiac / sign / constellation / horoscope / tell, or when the name is most of
# the sentence, so ordinary teacher questions are not taken over.
func _zodiac_voice(low: String) -> bool:
	if _zodiac == null:
		return false
	if (low.contains("hide") or low.contains("clear") or low.contains("remove")) and (low.contains("zodiac") or low.contains("constellation") or low.contains("sign")):
		_zodiac.hide_sign()
		return true
	var code: String = _zodiac.code_for(low)
	if code == "":
		return false
	var asked: bool = false
	for w in ["show", "see", "zodiac", "sign", "constellation", "horoscope", "tell", "what is", "where is", "display"]:
		if low.contains(w):
			asked = true
	if not asked and low.split(" ", false).size() > 3:
		return false
	if code == "Cnc" and not (low.contains("sign") or low.contains("zodiac") or low.contains("constellation") or low.contains("horoscope") or low.contains("show")):
		return false  # "cancer" alone is too often a health question
	if _planets != null and _planets.travel_body() != "":
		return false
	var speech: String = _zodiac.show_sign(code)
	if speech == "":
		return false
	if _voice != null:
		_voice.play_sound("sound_click")
	if _panel != null:
		_panel.fade_out_now()  # the sky is the display; the reading is spoken
	if _teacher_speech != null and _teacher_speech.has_method("speak"):
		_teacher_speech.speak(speech)
	# vc185: today's horoscope, written fresh by Muse Spark, plays right after
	# the reading (queued, so it never cuts the reading off).
	if code != "Oph" and _teacher != null:
		var sign: String = str(_zodiac.SIGNS[code]["sign"])
		_zodiac_wait_obj = "Zodiac " + sign
		_teacher.ask(_zodiac_wait_obj, "Horoscope: today's horoscope for " + sign + " for " + Time.get_date_string_from_system())
	return true
