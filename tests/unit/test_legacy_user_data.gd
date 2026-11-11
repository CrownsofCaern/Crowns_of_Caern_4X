extends "res://tests/test_case.gd"

const ROOT := "user://test_legacy_user_data"


func _wipe(path: String) -> void:
	var full := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(full):
		return
	for d in DirAccess.get_directories_at(full):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(full):
		DirAccess.remove_absolute(full.path_join(f))
	DirAccess.remove_absolute(full)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func before_each() -> void:
	_wipe(ROOT)


func after_each() -> void:
	_wipe(ROOT)


func test_project_uses_final_title() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/config/name")), "Crowns of Caern")


func test_legacy_dir_is_sibling_named_reignem() -> void:
	var dir := LegacyUserData.legacy_dir()
	assert_eq(dir.get_file(), "Reignem")
	assert_eq(dir.get_base_dir(), OS.get_user_data_dir().get_base_dir())


func test_copies_saves_and_settings_once_without_overwriting() -> void:
	var old := ProjectSettings.globalize_path(ROOT.path_join("old"))
	var new := ROOT.path_join("new")
	_write(ROOT.path_join("old/settings.cfg"), "old settings")
	_write(ROOT.path_join("old/saves/slot_1.json"), "slot one")
	_write(ROOT.path_join("old/saves/slot_auto.json"), "old auto")
	_write(ROOT.path_join("old/logs/godot.log"), "log")
	_write(new.path_join("saves/slot_auto.json"), "new auto")
	var copied := LegacyUserData.migrate(old, new)
	assert_eq(copied, 2)
	assert_eq(_read(new.path_join("settings.cfg")), "old settings")
	assert_eq(_read(new.path_join("saves/slot_1.json")), "slot one")
	assert_eq(_read(new.path_join("saves/slot_auto.json")), "new auto", "existing file kept")
	assert_false(FileAccess.file_exists(new.path_join("logs/godot.log")), "engine logs skipped")
	assert_true(FileAccess.file_exists(ROOT.path_join("old/saves/slot_1.json")), "source left in place")
	# Second run is a no-op even if the old folder gains files.
	_write(ROOT.path_join("old/saves/slot_2.json"), "later")
	assert_eq(LegacyUserData.migrate(old, new), 0)
	assert_false(FileAccess.file_exists(new.path_join("saves/slot_2.json")))


func test_missing_legacy_dir_does_nothing() -> void:
	var new := ROOT.path_join("new")
	assert_eq(LegacyUserData.migrate(ProjectSettings.globalize_path(ROOT.path_join("absent")), new), 0)
	assert_false(FileAccess.file_exists(new.path_join(LegacyUserData.MARKER)))


func test_recent_title_takes_priority_and_migration_runs_once() -> void:
	var base := ProjectSettings.globalize_path(ROOT.path_join("previous"))
	var target := ROOT.path_join("destination")
	_write(base.path_join("Crowns of Cinder/saves/slot_1.json"), "recent")
	_write(base.path_join("Reignem/saves/slot_1.json"), "older")
	_write(base.path_join("Reignem/saves/slot_2.json"), "legacy only")
	assert_eq(LegacyUserData.migrate_previous(base, target), 2)
	assert_eq(_read(target.path_join("saves/slot_1.json")), "recent")
	assert_eq(_read(target.path_join("saves/slot_2.json")), "legacy only")
	assert_true(FileAccess.file_exists(base.path_join("Crowns of Cinder/saves/slot_1.json")))
	_write(base.path_join("Crowns of Cinder/saves/slot_3.json"), "later")
	assert_eq(LegacyUserData.migrate_previous(base, target), 0)
	assert_false(FileAccess.file_exists(target.path_join("saves/slot_3.json")))
