class_name CampaignArt
extends RefCounted
## Campaign illustrations from assets/campaign_art.json (exported by
## tools/assets/pipeline.py): full-size chapter pictures found by campaign,
## chapter and usage ("briefing"). A chapter without a picture, or a picture
## missing on disk, gives null and the screens show text only.

const MANIFEST := "res://assets/campaign_art.json"
## The Long Watch follows Wren and Maelis; reuse their existing defence painting.
const REUSED_ILLUSTRATIONS := {
	"long_watch/watch_last/briefing": "last_light/ll_knight/briefing",
}

static var _paths: Dictionary = {}   # "campaign/chapter/usage" -> res:// path
static var _loaded := false


## The texture for a chapter's picture, or null.
static func texture(campaign_id: String, chapter_id: String, usage: String = "briefing") -> Texture2D:
	var path := path_of(campaign_id, chapter_id, usage)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The picture for a campaign as a whole, from its progress: the chapter to
## play next, or the last chapter once the campaign is won. A chapter without a
## picture shows the closest earlier chapter that has one (else the first
## later one), so a campaign with any art always has a cover. Null when the
## campaign has no pictures at all.
static func campaign_texture(data: GameData, progress: Campaign, usage: String = "briefing") -> Texture2D:
	var chapters: Array = progress.definition(data)["chapters"]
	if chapters.is_empty():
		return null
	var index := mini(progress.chapter, chapters.size() - 1)
	for i in range(index, -1, -1):
		var tex := texture(progress.campaign_id, String(chapters[i]["id"]), usage)
		if tex != null:
			return tex
	for i in range(index + 1, chapters.size()):
		var tex := texture(progress.campaign_id, String(chapters[i]["id"]), usage)
		if tex != null:
			return tex
	return null


## The res:// path the manifest gives a chapter's picture, or "".
static func path_of(campaign_id: String, chapter_id: String, usage: String = "briefing") -> String:
	if not _loaded:
		_read_manifest()
	var key := "%s/%s/%s" % [campaign_id, chapter_id, usage]
	return String(_paths.get(REUSED_ILLUSTRATIONS.get(key, key), ""))


static func _read_manifest() -> void:
	_loaded = true
	_paths = {}
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for entry in (parsed as Dictionary).get("illustrations", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var key := "%s/%s/%s" % [entry.get("campaign", ""), entry.get("chapter", ""), entry.get("usage", "")]
		_paths[key] = String(entry.get("path", ""))
