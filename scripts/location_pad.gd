# ZIP number pad, written from scratch for Star App.
# A small in-front-of-you keypad (no typing, no menus): 1-9, 0,
# Clear, OK. Pinch a key to press it — Main routes the pinch here
# first while the pad is visible, so a keypress never calibrates
# or identifies. Passthrough-safe: tiny, upper-left, translucent.
extends Node3D

signal key_pressed(key: String)

const KEYS: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "clear", "0", "ok"]
const KEY_LABELS: Dictionary = {"clear": "C", "ok": "OK"}

var _buttons: Dictionary = {}
var _entry: Label3D = null
var _camera: XRCamera3D = null

func set_camera(camera: XRCamera3D) -> void:
	_camera = camera

func _ready() -> void:
	_entry = Label3D.new()
	_entry.font_size = 24
	_entry.pixel_size = 0.002
	_entry.width = 200
	_entry.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_entry.modulate = Color(1.0, 1.0, 1.0)
	_entry.outline_size = 2
	_entry.outline_modulate = Color(0.0, 0.0, 0.0)
	_entry.position = Vector3(0.0, 0.30, 0.0)
	add_child(_entry)
	set_entry("")
	var cols: int = 3
	for i: int in range(KEYS.size()):
		var key: String = KEYS[i]
		var btn: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.09, 0.09, 0.02)
		btn.mesh = box
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		if key == "ok":
			mat.albedo_color = Color(0.35, 0.75, 0.45, 0.85)
		elif key == "clear":
			mat.albedo_color = Color(0.75, 0.45, 0.40, 0.85)
		else:
			mat.albedo_color = Color(0.35, 0.50, 0.75, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		btn.material_override = mat
		var col: int = i % cols
		var row: int = i / cols
		btn.position = Vector3((float(col) - 1.0) * 0.11, 0.14 - float(row) * 0.11, 0.0)
		btn.name = "Key_" + key
		add_child(btn)
		_buttons[key] = btn
		var lab: Label3D = Label3D.new()
		lab.text = KEY_LABELS.get(key, key)
		lab.font_size = 24
		lab.pixel_size = 0.002
		lab.width = 60
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = Color(1.0, 1.0, 1.0)
		lab.outline_size = 2
		lab.outline_modulate = Color(0.0, 0.0, 0.0)
		lab.position = btn.position + Vector3(0.0, 0.0, 0.02)
		add_child(lab)

func _process(_delta: float) -> void:
	if _camera == null or not visible:
		return
	var basis: Basis = _camera.global_transform.basis
	global_position = _camera.global_position + basis * Vector3(-0.55, 0.02, -1.2)
	var look: Vector3 = _camera.global_position
	look.y = global_position.y
	if (look - global_position).length() > 0.01:
		look_at(look, Vector3.UP)

func set_entry(text: String) -> void:
	if _entry != null:
		_entry.text = "ZIP " + text if text != "" else "ZIP _____"

func press_at(point: Vector3) -> String:
	# Which key, if any, the pinched point hit. "" = missed pad.
	var best: String = ""
	var best_d: float = 0.07
	for key: Variant in _buttons.keys():
		var btn: MeshInstance3D = _buttons[key]
		var d: float = point.distance_to(btn.global_position)
		if d < best_d:
			best_d = d
			best = key
	return best
