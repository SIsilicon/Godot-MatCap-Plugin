tool
extends Reference

var material: Material

func setup(material: Material) -> void:
	self.material = material
	if material.has_meta("_matcap_cleanup"):
		material.remove_meta("_matcap_cleanup")
	material.set_meta("_matcap_cleanup", self)
	material.connect("script_changed", self, "_on_script_changed")


func _on_script_changed() -> void:
	VisualServer.disconnect("frame_pre_draw", material, "_update")
	VisualServer.disconnect("frame_post_draw", material, "_post_draw")
	material.remove_meta("_matcap_cleanup")
