extends Node3D

const FLOOR_MARKING_NAMES := [
    "Bay separator",
    "Bay back line",
    "Lane arrow shaft",
    "Directional arrow",
    "Aisle dashed line",
    "Ramp centre dash",
    "Entry lane edge",
    "EV bay patch",
    "Label EV",
    "Label 徐行",
    "Label 止まれ"
]

func _ready() -> void:
    _apply_to(self)

func _apply_to(node: Node) -> void:
    if node is GeometryInstance3D:
        var imported_flag: Variant = node.get_meta("casts_shadow", null)
        if imported_flag == false or _is_floor_marking(node.name):
            node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for child: Node in node.get_children():
        _apply_to(child)

func _is_floor_marking(node_name: String) -> bool:
    if node_name.begins_with("Label "):
        var label := node_name.trim_prefix("Label ").trim_suffix(" mesh")
        if label.is_valid_int() and label.length() == 3:
            return true
    for prefix: String in FLOOR_MARKING_NAMES:
        if node_name.begins_with(prefix):
            return true
    return false
