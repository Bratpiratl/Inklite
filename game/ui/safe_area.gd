class_name SafeArea
extends RefCounted
## Abstände für Notch, Statusleiste und Gestenleiste in Canvas-Einheiten (links, oben, rechts, unten).
## Im Browser über CSS env(safe-area-inset-*), sonst über DisplayServer.

const JS_INSETS := """(function() {
	var d = document.createElement('div');
	d.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
	document.body.appendChild(d);
	var s = getComputedStyle(d);
	var r = [s.paddingLeft, s.paddingTop, s.paddingRight, s.paddingBottom].map(parseFloat).join(',');
	d.remove();
	return r + ',' + window.devicePixelRatio;
})()"""


static func insets(viewport: Viewport) -> Vector4:
	var window_size := Vector2(DisplayServer.window_get_size())
	var canvas_size := viewport.get_visible_rect().size
	if window_size.x <= 0.0:
		return Vector4.ZERO
	var to_canvas := canvas_size.x / window_size.x
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval(JS_INSETS, true)
		if not (raw is String):
			return Vector4.ZERO
		var parts: PackedStringArray = raw.split(",")
		if parts.size() < 5:
			return Vector4.ZERO
		var scale := float(parts[4]) * to_canvas
		return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])) * scale
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or screen.x <= 0:
		return Vector4.ZERO
	return Vector4(safe.position.x, safe.position.y,
		screen.x - safe.end.x, screen.y - safe.end.y) * to_canvas
