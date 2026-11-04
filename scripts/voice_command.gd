# Voice command, started 2026-10-29, user request: say "show me Mars", "show me the Moon", etc., app shows that body + name + description.
# Phase 1 (this file): command PARSING + show logic, pinch-identical, no new build yet.
# - parse_command(text): "show me mars", "show me the moon", "show me saturn" -> body name, or "" if not a known body/star.
# - Known bodies first: Sun, Moon, Mercury, Venus, Mars, Jupiter, Saturn, Uranus, Neptune.
# - Stars later: same parser, fed from stars.csv, after planets work in-headset.
# Phase 2 (next, needs a speech engine): microphone capture + speech-to-text.
# Godot 4.3 core has NO built-in speech-to-text, and Quest has no app-level
# "show me" listener out of the box. Options, in order, to be chosen with user:
#  A) Android speech-recognition plugin (Java, mic permission, on-device or cloud STT) - most accurate, most build work, risk to Quest export.
#  B) Mic capture (AudioEffectCapture) -> send clip to a cloud STT API on pinch-and-hold / voice button - works, needs internet + API key, latency 1-3 s.
#  C) Push-to-talk in app: hold a hand button / say a wake word - still needs A or B for the actual words.
# Until Phase 2 is chosen and built, this parser is testable by typing / by a debug pinch? No - do NOT fake voice: if no mic engine is present, voice command must say "voice not ready yet", never pretend it heard you.
# This file does NOT claim voice works yet. It only makes "show me X" do the same thing as pinching X, once text arrives.
extends Node

const BODIES: Array = ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]

func parse_command(text: String) -> String:
	# vc57 fix: ASR returns "show me Mars. show me Mars." with period + repeat,
	# old code compared the whole tail and never matched. Clean it first.
	var t: String = text.to_lower().strip_edges()
	t = t.replace(".", " ").replace(",", " ").replace("the ", "")
	# Take the FIRST "show me X" segment only, ignore repeats after it.
	if not t.contains("show me "):
		return ""
	var rest: String = t.substr(t.find("show me ") + "show me ".length()).strip_edges()
	var name: String = rest.split(" ")[0].strip_edges()
	# vc131 ISS: "show me iss" and "show me the space station" both mean ISS.
	if name in ["iss", "space", "station"]:
		return "ISS"
	if name == "earth":
		return "Earth"
	for body: String in BODIES:
		if name == body.to_lower():
			return body
	return ""
