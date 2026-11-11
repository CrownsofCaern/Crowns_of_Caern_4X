extends Node
## First autoload: runs one-time housekeeping before anything reads user://
## (AudioManager loads settings in its own _ready, after this _init).


func _init() -> void:
	var copied := LegacyUserData.migrate()
	if copied > 0:
		print("Copied %d file(s) from previous game user folders." % copied)
