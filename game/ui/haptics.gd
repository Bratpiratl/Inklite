class_name Haptics
extends RefCounted
## Kurze Vibration als Rückmeldung (Android im Browser; iPhones unterstützen das im Browser nicht).
## Abschaltbar in den Einstellungen.

const TAP := 15
const MERGE := 45
const WIN := 90


static func pulse(duration_ms: int) -> void:
	if Prefs.vibration:
		Input.vibrate_handheld(duration_ms)
