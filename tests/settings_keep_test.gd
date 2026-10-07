extends Node
## What the player made survives a restart / a new version: the sticker designs (and the other
## settings created on first use) are read back from settings.json.
## Run: godot --headless --path . res://tests/settings_keep_test.tscn

const Livery = preload("res://scripts/car/livery.gd")


func _ready() -> void:
	var path: String = Game.SETTINGS_PATH
	var backup := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var layers: Array = [Livery.new_layer("star", Color(0.2, 0.6, 1.0))]
	Game.set_livery("r34", layers)
	Game.settings["recent_paints"] = ["#123456"]
	Game.settings["tutorial_done"] = true
	var before: Array = Game.get_livery("r34")
	Game.persist = true
	Game.save_settings()
	# a fresh start: the defaults, then the file
	Game.settings.erase("livery_designs")
	Game.settings.erase("recent_paints")
	Game.settings.erase("tutorial_done")
	Game.load_settings()
	var after: Array = Game.get_livery("r34")
	var ok: bool = after.size() == before.size() and not after.is_empty() \
		and str(after[0].get("shape")) == "star" \
		and Color.from_string(str(after[0].get("color")), Color.BLACK).is_equal_approx(Color.from_string(str(before[0].get("color")), Color.WHITE)) \
		and Game.settings.get("recent_paints") is Array and bool(Game.settings.get("tutorial_done", false))
	print("KEEP: designs before %d layer(s), after reload %d (%s), recent paints %s, tutorial done %s" % [before.size(), after.size(),
		after[0] if not after.is_empty() else "-", Game.settings.get("recent_paints"), Game.settings.get("tutorial_done")])
	# leave the user's file as it was
	Game.persist = false
	if backup != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SETTINGS KEEP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
