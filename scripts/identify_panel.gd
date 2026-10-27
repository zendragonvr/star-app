# Fresh identify panel, written 2026-10-26.
# Small, upper-right, readable in 2 seconds, no scrolling, no menus.
# The panel follows the camera: it sits in front of the user in
# passthrough, never as a world menu the user has to walk to.
# It shows the object name plus the scientific numbers an
# astronomer can check (RA, Dec, alt, az, magnitude when known).
# If the pinch was not sure, it says so plainly instead of
# guessing a wrong name — a wrong name is worse than no name.
extends Node3D

var _label: Label3D
var _camera: XRCamera3D = null
var _hide_after_unix: float = -1.0

func _ready() -> void:
	_label = Label3D.new()
	# v4 panel size fix — v3 verdict, 2026-10-26 video: the panel
	# filled the whole view and text was cut off. Root cause:
	# Label3D default font_size is 64, times pixel_size 0.012
	# = 0.77 m tall PER LINE at 1.2 m distance. That is a
	# billboard, not a panel. v4: 32 * 0.0025 = 0.08 m per line,
	# readable in 2 seconds, upper-right, fits in view.
	# Width + word wrap so long teacher answers wrap instead
	# of running off the right edge.
	# v19 panel size fix — v18 video: text ran off the right
	# edge, and lines looked 2-3× too large in recording.
	# Smaller + more centred: font 24 × 0.002 = 0.048 m/line,
	# width 260 px × 0.002 = 0.52 m wide, centred at x=0.15
	# instead of 0.45, so the right edge stays in view.
	_label.font_size = 24
	_label.pixel_size = 0.002
	_label.width = 260
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 1.0, 1.0)
	_label.outline_size = 2
	_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_label.text = ""
	add_child(_label)

func set_camera(camera: XRCamera3D) -> void:
	_camera = camera

func _process(_delta: float) -> void:
	if _camera != null:
		var cam_basis: Basis = _camera.global_transform.basis
		global_position = _camera.global_position + cam_basis * Vector3(0.15, 0.28, -1.2)
	if _hide_after_unix > 0.0 and Time.get_unix_time_from_system() > _hide_after_unix:
		_label.text = ""
		_hide_after_unix = -1.0

func show_object(name: String, detail: String) -> void:
	_label.text = name + "\n" + detail
	_hide_after_unix = -1.0

func show_not_sure() -> void:
	# v15: persistent, not 3 s. The old 3 s hide cleared the panel
	# to "", then the diagnostic overwrote it with "Star App",
	# so the user could never tell if a pinch had worked at all.
	# Now the last result stays until the next pinch replaces it.
	_label.text = "Not sure — try a brighter object"
	_hide_after_unix = -1.0

func show_calibrated() -> void:
	_label.text = "Sky locked — saved, one time only"
	_hide_after_unix = -1.0

func show_calibrated_from(name: String) -> void:
	# v15: persistent lock confirmation. This is the confirmation
	# the user asked for 2026-10-27 — "need a way to confirm
	# moon locked". It stays on screen until the next identify,
	# and the diagnostic never overwrites it (diagnostic only
	# overwrites panels starting with "Star App" or empty).
	_label.text = "Sky locked from " + name + " — saved"
	_hide_after_unix = -1.0

func show_teacher(answer: String, source_label: String) -> void:
	# Panel says "live" (= API call just used a fraction of a
	# cent) or "saved" (= cached answer, no credits). Never hide
	# which one it was.
	var clean: String = answer.strip_edges()
	if clean.length() > 300:
		clean = clean.substr(0, 300) + "…"
	if _label.text != "":
		_label.text += "\n\nTeacher (" + source_label + "): " + clean
	else:
		_label.text = "Teacher (" + source_label + "): " + clean
	_hide_after_unix = -1.0

func hide_panel() -> void:
	_label.text = ""
	_hide_after_unix = -1.0

func current_text() -> String:
	return _label.text
