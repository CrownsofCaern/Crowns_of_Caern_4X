class_name SaveLoadDialog
extends ModalPanel
## Save or load menu: the autosave slot and the numbered slots, each with the
## map, date and whose turn it is.

signal slot_chosen(mode: String, slot: String)
signal closed

var mode := "load"


func open(game_data: GameData, open_mode: String, can_save: bool = true, directory: String = SaveSlots.DEFAULT_DIR, temporary: bool = false) -> void:
	set_menu_background("archive")
	mode = open_mode
	_clear()
	_body.add_child(UiStyle.label(("Playtest · " if temporary else "") + ("Save Game" if mode == "save" else "Load Game"), 22, UiStyle.BRASS))
	if temporary:
		_body.add_child(_wrapped("These slots are temporary and are removed when you return to the editor.", 14, UiStyle.WARN))
	for row in SaveSlots.list(game_data, directory):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var lbl := UiStyle.label(row["label"], 15, UiStyle.BRASS if row["valid"] else UiStyle.TEXT)
		lbl.custom_minimum_size.x = 90
		line.add_child(lbl)
		var info := UiStyle.label(SaveSlots.summary(row), 13, UiStyle.TEXT if row["valid"] else UiStyle.TEXT_DIM)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		line.add_child(info)
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 32)
		var slot: String = row["slot"]
		if mode == "save":
			b.text = "Overwrite" if row["exists"] else "Save"
			# The autosave and online slots are written by the game itself.
			b.disabled = slot == SaveSlots.AUTOSAVE or SaveSlots.is_online_slot(slot) or not can_save
		else:
			b.text = "Load"
			b.disabled = not row["valid"]
		b.pressed.connect(func(): slot_chosen.emit(mode, slot))
		line.add_child(b)
		_body.add_child(line)
	_buttons([["Close", func():
		hide()
		closed.emit()]])
	show()
