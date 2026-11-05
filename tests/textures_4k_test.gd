# Texture check, headless (v23 JOB 3 ultra realism).
# Run: godot --headless --path project -s tests/textures_4k_test.gd
# Contract: every planet/Moon body must have a loadable 2k fallback
# (equirectangular 2:1 JPEG). Any 4k file present in
# data/textures/ must be EXACTLY 4096x2048 JPEG — a 2k file renamed
# to 4k fails here instead of silently shipping. Celestia 4k files
# must also match their upstream byte sizes exactly (raw download
# bytes are deterministic); the Moon file is exempt from the byte
# check because it is user-converted from the SVS 16-bit TIF.
# Missing 4k files are reported, not failed: 2k fallback is the
# supported pre-download state (see docs/texture_upgrade_4k.md).
# Venus must stay the atmosphere texture, never a radar surface.
extends SceneTree

const TEX_DIR: String = "res://data/textures/"
const FALLBACKS: Array = [
	"2k_sun.jpg", "2k_moon.jpg", "2k_mercury.jpg",
	"2k_venus_atmosphere.jpg", "2k_mars.jpg", "2k_jupiter.jpg",
	"2k_saturn.jpg", "2k_uranus.jpg", "2k_neptune.jpg",
]
# Upstream byte sizes verified via the GitHub API 2026-10-28.
const EXPECTED_BYTES: Dictionary = {
	"4k_mars.jpg": 1135541,
	"4k_jupiter.jpg": 5152546,
	"4k_saturn.jpg": 687644,
}
const UPGRADEABLE: Array = ["Moon", "Mars", "Jupiter", "Saturn"]

var _fail: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("Textures: ", label, " PASS")
	else:
		_fail += 1
		print("Textures: ", label, " FAIL")

func _is_jpeg(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var b0: int = f.get_8()
	var b1: int = f.get_8()
	f.close()
	return b0 == 0xFF and b1 == 0xD8

func _file_bytes(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = int(f.get_length())
	f.close()
	return n

func _dims(path: String) -> Vector2i:
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return Vector2i(-1, -1)
	return Vector2i(img.get_width(), img.get_height())

func _initialize() -> void:
	# 2k fallbacks: always present, valid JPEG, equirect 2:1.
	for name: String in FALLBACKS:
		var p: String = TEX_DIR + name
		_check(_is_jpeg(p), name + " is JPEG")
		var d: Vector2i = _dims(p)
		_check(d.x >= 1024 and d.y * 2 == d.x, name + " loads equirectangular 2:1 (" + str(d.x) + "x" + str(d.y) + ")")
	# Venus rule: the atmosphere file exists; no radar surface file
	# may ever take its place (nothing here may reference one).
	_check(FileAccess.file_exists(TEX_DIR + "2k_venus_atmosphere.jpg"), "venus stays atmosphere texture")
	# 4k upgrades: verify strictly when present, report when absent.
	for body: String in UPGRADEABLE:
		var fname: String = "4k_" + body.to_lower() + ".jpg"
		var p: String = TEX_DIR + fname
		if not FileAccess.file_exists(p):
			print("Textures: ", fname, " not in repo yet — 2k fallback active (see docs/texture_upgrade_4k.md)")
			continue
		_check(_is_jpeg(p), fname + " is JPEG")
		var d: Vector2i = _dims(p)
		_check(d == Vector2i(4096, 2048), fname + " is 4096x2048 (got " + str(d.x) + "x" + str(d.y) + ")")
		if EXPECTED_BYTES.has(fname):
			_check(_file_bytes(p) == int(EXPECTED_BYTES[fname]), fname + " matches upstream bytes (" + str(_file_bytes(p)) + ")")
		else:
			print("Textures: ", fname, " present at " + str(_file_bytes(p)) + " bytes (user-converted Moon, dims verified above)")
	print("Textures: ", "ALL PASS" if _fail == 0 else "SOME FAILED")
	quit(_fail)
