class_name LegacyUserData
extends RefCounted
## Copies saves, campaign progress and settings from previous project names.
## Newer Crowns of Cinder data takes priority over Reignem. Existing destination
## files are never overwritten, and source files are never moved or deleted.
## Headless: only FileAccess/DirAccess.

const LEGACY_NAME := "Reignem"
const MARKER := "migrated_from_reignem.txt"
## Engine-generated folders that should not be carried over.
const SKIP := ["logs", "shader_cache", "vulkan"]


## The old folder next to the current user data folder.
static func legacy_dir() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join(LEGACY_NAME)


## Copies the old folder into the new one once. Returns how many files were
## copied (0 when there is nothing to do).
static func migrate(from_dir: String = "", to_dir: String = "user://", marker_name: String = MARKER) -> int:
	if from_dir == "":
		return migrate_previous(OS.get_user_data_dir().get_base_dir(), to_dir)
	var src := from_dir
	var dst := ProjectSettings.globalize_path(to_dir)
	if src.simplify_path() == dst.simplify_path() or not DirAccess.dir_exists_absolute(src):
		return 0
	var marker := dst.path_join(marker_name)
	if FileAccess.file_exists(marker):
		return 0
	var copied := _copy_tree(src, dst)
	var f := FileAccess.open(marker, FileAccess.WRITE)
	if f != null:
		f.store_string("Copied %d file(s) from %s\n" % [copied, src])
	return copied


## Visit the most recent title first so older saves cannot replace newer ones.
static func migrate_previous(base_dir: String, to_dir: String = "user://") -> int:
	var copied := migrate(base_dir.path_join("Crowns of Cinder"), to_dir, "migrated_from_cinder.txt")
	copied += migrate(base_dir.path_join(LEGACY_NAME), to_dir)
	return copied


static func _copy_tree(src: String, dst: String) -> int:
	if DirAccess.make_dir_recursive_absolute(dst) not in [OK, ERR_ALREADY_EXISTS]:
		return 0
	var copied := 0
	var files := Array(DirAccess.get_files_at(src))
	files.sort()
	for name in files:
		var target := dst.path_join(name)
		if FileAccess.file_exists(target):
			continue
		if DirAccess.copy_absolute(src.path_join(name), target) == OK:
			copied += 1
	var dirs := Array(DirAccess.get_directories_at(src))
	dirs.sort()
	for name in dirs:
		if name in SKIP:
			continue
		copied += _copy_tree(src.path_join(name), dst.path_join(name))
	return copied
