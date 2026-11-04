# Solar-system view for 3I/ATLAS — added 2026-11-01, ephemeris by the user, math unchanged.
# Planets from Ephemeris.planet_helio(), comet from Ephemeris.atlas_helio(),
# both converted with Ephemeris.ecl_to_godot(). Directions are exact.
# If distances are compressed to fit, r_visual = k * r^0.6 is applied to
# EVERYTHING (planets and comet alike), and the view must be labelled
# "distances compressed". With k = 1.0, Neptune (30 AU) sits at 7.7 units
# and 3I/ATLAS at 12.9 AU sits at 4.6 units — no separate comet scale.
# This script is the view logic (positions, path, markers, scrubber date).
# vc116: wired into main.tscn as AtlasSystemView, hidden by default.
# toggle_atlas_system_view() in main.gd shows it; a VR scrubber control
# is still to come — scrub_jd defaults to today and set_scrub_unix() moves it.
extends Node3D
class_name AtlasSystemView

const COMPRESS_K: float = 1.0
const COMPRESS_LABEL: String = "distances compressed"
const PLANET_NAMES: Array = ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune"]

## Scrubber date, Julian Day. Default: today, set in _ready.
@export var scrub_jd: float = 0.0
var _path_start_jd: float = 0.0
var _path_end_jd: float = 0.0

func _ready() -> void:
	if scrub_jd == 0.0:
		scrub_jd = Ephemeris.now_jd()
	_path_start_jd = Ephemeris.jd_from_utc(2025, 7, 1)
	_path_end_jd = Ephemeris.jd_from_utc(2029, 1, 1)
	_build_view()

func _line_mesh(points: PackedVector3Array, dashed: bool) -> MeshInstance3D:
	var verts := PackedVector3Array()
	for i in range(points.size() - 1):
		if dashed and (i % 2 == 1):
			continue
		verts.append(points[i])
		verts.append(points[i + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.85, 1.0)
	inst.material_override = mat
	return inst

func _build_view() -> void:
	var split := atlas_path_split(scrub_jd)
	add_child(_line_mesh(split["past"], false))
	add_child(_line_mesh(split["future"], true))
	var cur := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	cur.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.emission_enabled = true
	cm.emission = Color(0.7, 0.9, 1.0)
	cm.emission_energy_multiplier = 3.0
	cur.material_override = cm
	cur.position = atlas_visual(scrub_jd)
	add_child(cur)
	for label in markers():
		var l := Label3D.new()
		l.text = label
		l.font_size = 24
		l.position = markers()[label] + Vector3(0, 0.25, 0)
		add_child(l)
	var title := Label3D.new()
	title.text = view_label()
	title.font_size = 32
	title.position = Vector3(0, 9.0, 0)
	add_child(title)

static func visual_pos(helio_au: Vector3) -> Vector3:
	var r := helio_au.length()
	if r <= 0.0:
		return Vector3.ZERO
	return Ephemeris.ecl_to_godot(helio_au) * (COMPRESS_K * pow(r, 0.6) / r)

static func planet_visual(name: String, jd: float) -> Vector3:
	return visual_pos(Ephemeris.planet_helio(name, jd))

static func atlas_visual(jd: float) -> Vector3:
	return visual_pos(Ephemeris.atlas_helio(jd))

## Path split at the scrubber date: solid for the past, dashed for the future.
static func atlas_path_split(scrub: float) -> Dictionary:
	var pts := Ephemeris.atlas_path(Ephemeris.jd_from_utc(2025, 7, 1), Ephemeris.jd_from_utc(2029, 1, 1), 10.0)
	var past := PackedVector3Array()
	var future := PackedVector3Array()
	var jd := Ephemeris.jd_from_utc(2025, 7, 1)
	for p in pts:
		if jd <= scrub:
			past.append(visual_pos(p))
		else:
			future.append(visual_pos(p))
		jd += 10.0
	return {"past": past, "future": future, "past_count": past.size(), "future_count": future.size()}

## Labeled markers, positions at their event dates (not at the scrubber date).
static func markers() -> Dictionary:
	var events := {
		"Mars flyby (2025-10-03)": Ephemeris.jd_from_utc(2025, 10, 3),
		"perihelion (2025-10-29)": Ephemeris.jd_from_utc(2025, 10, 29, 11, 45),
		"Earth closest (2025-12-19)": Ephemeris.jd_from_utc(2025, 12, 19, 6, 1),
		"Jupiter flyby (2026-03-16)": Ephemeris.jd_from_utc(2026, 3, 16, 12, 22),
	}
	var out := {}
	for label in events:
		out[label] = atlas_visual(events[label])
	return out

func set_scrub_unix(unix_seconds: float) -> void:
	scrub_jd = Ephemeris.jd_from_unix(unix_seconds)

func view_label() -> String:
	return "3I/ATLAS solar-system view — " + COMPRESS_LABEL
