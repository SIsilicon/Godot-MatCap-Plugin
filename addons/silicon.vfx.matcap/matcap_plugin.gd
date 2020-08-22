tool
extends EditorPlugin

var button: MenuButton
var selected_material: Material

var icon: Texture


func handles(object: Object) -> bool:
	if object is SpatialMaterial:
		button.show()
		return true
	button.hide()
	return false


func edit(object: Object) -> void:
	selected_material = object

	if selected_material.get_script() == preload("matcap_material.gd"):
		button.get_popup().set_item_id(0, 1)
		button.get_popup().set_item_text(0, "Remove MatCap")
	else:
		button.get_popup().set_item_id(0, 0)
		button.get_popup().set_item_text(0, "Add MatCap")
	button.get_popup().set_item_icon(0, icon)


func enable_plugin() -> void:
	print("""
MatCap Plugin enabled! To learn how to use the plugin, please go to:
https://github.com/SIsilicon/Godot-MatCap-Plugin
If there's an issue, please go to:
https://github.com/SIsilicon/Godot-MatCap-Plugin/issues
""")


func _enter_tree() -> void:
	while not icon:
		icon = load("res://addons/silicon.vfx.matcap/matcap_material.png")
		yield(get_tree(), "idle_frame")
	add_custom_type("MatCapMaterial", "SpatialMaterial", preload("matcap_material.gd"), icon)

	button = MenuButton.new()
	button.flat = true
	button.icon = get_editor_interface().get_base_control().get_icon("SpatialMaterial", "EditorIcons")
	button.text = "SpatialMaterial"
	button.visible = false
	button.get_popup().add_item("Add MatCap", 0)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, button)

	if not button.get_popup().is_connected("index_pressed", self, "_on_button_pressed"):
		button.get_popup().connect("index_pressed", self, "_on_button_pressed")


func _on_button_pressed(index: int) -> void:
	match button.get_popup().get_item_id(0):
		0: # Add Tile Breaker
			selected_material.set_script(preload("matcap_material.gd"))
		1: # Remove Tile Breaker
			selected_material.set_script(null)
	edit(selected_material)


func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, button)
	remove_custom_type("MatCapMaterial")
