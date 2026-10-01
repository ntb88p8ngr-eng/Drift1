extends Node
## Switches the tabs of its parent TabContainer with the shift buttons: RB / E = next category,
## LB / Q = previous (like the paddles in the car). Works in the pause menu too.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	var tc := get_parent() as TabContainer
	if tc == null or not tc.is_visible_in_tree() or event.is_echo():
		return
	# a text field being typed into keeps its Q / E
	var foc := get_viewport().gui_get_focus_owner()
	if foc is LineEdit or foc is TextEdit:
		return
	var step := 0
	if event.is_action_pressed("shift_up"):
		step = 1
	elif event.is_action_pressed("shift_down"):
		step = -1
	if step == 0:
		return
	var n := tc.get_tab_count()
	tc.current_tab = posmod(tc.current_tab + step, n)
	get_viewport().set_input_as_handled()
	# the focus moves to the new page (or the tab row when the page has nothing focusable)
	var page := tc.get_current_tab_control()
	if page == null or not UiKitRef.focus_first(page):
		tc.get_tab_bar().grab_focus()


const UiKitRef = preload("res://scripts/ui/ui_kit.gd")
