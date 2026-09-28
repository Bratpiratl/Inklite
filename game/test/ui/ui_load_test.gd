extends GdUnitTestSuite
## Lädt alle Skripte und Szenen der Oberfläche. Parse-Fehler fallen so schon beim Testlauf auf
## und nicht erst im Browser. Die Szenen werden nur erzeugt, nicht in den Baum gehängt.

const DIRS := ["res://ui", "res://telemetry"]


func test_all_ui_scripts_and_scenes_load() -> void:
	var count := 0
	for dir in DIRS:
		for file in DirAccess.get_files_at(dir):
			var path: String = dir.path_join(file)
			if file.ends_with(".gd"):
				var script: GDScript = load(path)
				assert_bool(script != null and script.can_instantiate()).override_failure_message("Skript lädt nicht: " + path).is_true()
				count += 1
			elif file.ends_with(".tscn"):
				var scene: PackedScene = load(path)
				assert_object(scene).override_failure_message("Szene lädt nicht: " + path).is_not_null()
				var node := scene.instantiate()
				assert_object(node).is_not_null()
				node.free()
				count += 1
	assert_int(count).is_greater(10)
