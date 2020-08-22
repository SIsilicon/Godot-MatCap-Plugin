tool
extends SpatialMaterial

const DEFAULT_SPATIAL_CODE := """
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : hint_color;
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular;
uniform float metallic;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

void vertex() {
	UV=UV*uv1_scale.xy+uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = texture(texture_albedo,base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
"""

enum Blend {
	NONE,
	MIX,
	ADD,
	SUB,
	MUL
}

# Exported variables
var mat_cap: Texture setget set_mat_cap
var modulate := Color.white setget set_modulate
var energy := 1.0 setget set_energy
var blend: int = Blend.NONE setget set_blend
var mask: Texture setget set_mask

var prev_shader_code := ""
var original_shader: RID
var adjusted_shader := Shader.new()
var dirty_shader := true


func transform_material() -> String:
	var code := VisualServer.shader_get_code(
			VisualServer.material_get_shader(get_rid())
	)

	if prev_shader_code != code:
		dirty_shader = true
	if not dirty_shader:
		return ""
	prev_shader_code = code

	# When a material is first created, it does not immediately have shader code.
	# This makes sure that it will initially work.
	if code.empty():
		code = DEFAULT_SPATIAL_CODE

	var shader_type_line_end := code.find(";")
	if shader_type_line_end == -1:
		return ""

	# Insert uniforms right after shader_type.
	code = code.insert(shader_type_line_end + 1, """
		// MATCAP UNIFORMS
		uniform sampler2D texture_matcap: hint_albedo_white;
		uniform sampler2D mask_matcap: hint_albedo_white;
		uniform vec4 modulate_matcap = vec4(1.0);"""\
	.replace("\n\t\t", "\n"))

	var frag_code = """
		vec3 matcap_normal = vec3(NORMALMAP.xy * 2.0 - 1.0, 1.0) * NORMALMAP_DEPTH;
		matcap_normal.z = 1.0 - (pow(matcap_normal.x, 2.0) + pow(matcap_normal.y, 2.0));
		matcap_normal = matcap_normal.x * TANGENT + matcap_normal.y * BINORMAL + matcap_normal.z * NORMAL;
		vec2 uv = matcap_normal.xy * vec2(0.5, -0.5) + 0.5;
		vec4 matcap = texture(texture_matcap, uv);
		// GLES3 matcap.rgb = pow(matcap.rgb, vec3(2.2));
		matcap *= modulate_matcap;
		// MASK matcap.a *= texture(mask_matcap, base_uv).r;
		// MASK_TRIPLANAR matcap.a *= triplanar_texture(mask_matcap, uv1_power_normal, uv1_triplanar_pos).r;
		// VERT_COLORS matcap *= COLOR;

		// 'IF' statements that rely on shader constants will most likely get optimized away. ;)
		int matcap_blend = /*MATCAP_BLEND*/0;
		if(matcap_blend == 0) {
			ALBEDO = matcap.rgb;
			// ALPHA = matcap.a;
		} else if(matcap_blend == 1) {
			EMISSION = mix(EMISSION, matcap.rgb, matcap.a);
			AO = mix(AO, 0.0, matcap.a);
			SPECULAR = mix(SPECULAR, 0.0, matcap.a);
			ALBEDO *= 1.0 - matcap.a;
		} else if(matcap_blend == 2) {
			EMISSION += matcap.rgb * matcap.a;
		} else if(matcap_blend == 3) {
			EMISSION -= matcap.rgb * matcap.a;
		} else if(matcap_blend == 4) {
			EMISSION = mix(EMISSION, EMISSION * matcap.rgb, matcap.a);
			ALBEDO = mix(ALBEDO, ALBEDO * matcap.rgb, matcap.a);
		}"""\
	.replace("\n\t", "\n")

	var regex := RegEx.new()
	regex.compile("void\\s+fragment\\s*\\(\\s*\\)\\s*{")
	var has_fragment := regex.search(code)
	if has_fragment:
		var end := has_fragment.get_end() - 1
		var frag_end := find_closing_bracket(code, end)
		code = code.insert(frag_end, frag_code +"\n")
	else:
		code += "void fragment() {" + frag_code + "\n}"

	if not flags_unshaded and blend == Blend.NONE:
		code = code.insert(shader_type_line_end + 1, "\nrender_mode unshaded;")
	if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3:
		code = code.replace("// GLES3", "")
	if flags_transparent or params_blend_mode != BLEND_MODE_MIX:
		code = code.replace("// ALPHA", "ALPHA")
	if vertex_color_use_as_albedo:
		code = code.replace("// VERT_COLORS ", "")
	if blend != Blend.NONE:
		code = code.replace("// MASK_TRIPLANAR " if uv1_triplanar else "// MASK ", "")
	code = code.replace("/*MATCAP_BLEND*/0", str(blend))

	dirty_shader = false
	return code


func set_mat_cap(value: Texture) -> void:
	mat_cap = value
	VisualServer.material_set_param(get_rid(), "texture_matcap", mat_cap)


func set_modulate(value: Color) -> void:
	modulate = value
	VisualServer.material_set_param(get_rid(), "modulate_matcap", modulate * Color(energy, energy, energy, 1.0))


func set_energy(value: float) -> void:
	energy = value
	VisualServer.material_set_param(get_rid(), "modulate_matcap", modulate * Color(energy, energy, energy, 1.0))


func set_blend(value: int) -> void:
	blend = value
	dirty_shader = true
	property_list_changed_notify()


func set_mask(value: Texture) -> void:
	mask = value
	VisualServer.material_set_param(get_rid(), "mask_matcap", mask)


func _get_property_list() -> Array:
	var properties := [
		{name="MatCapMaterial", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="mat_cap", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture"},
		{name="modulate", type=TYPE_COLOR},
		{name="energy", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,16,0.01"},
		{name="blend", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="None,Mix,Add,Subtract,Multiply"},
	]

	if blend != Blend.NONE:
		properties += [
			{name="mask", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture"}
		]

	return properties


func _init() -> void:
	if not VisualServer.is_connected("frame_pre_draw", self, "_update"):
		VisualServer.connect("frame_pre_draw", self, "_update")
	if not VisualServer.is_connected("frame_post_draw", self, "_post_draw"):
		VisualServer.connect("frame_post_draw", self, "_post_draw")

	yield(VisualServer, "frame_post_draw")
	set_mat_cap(mat_cap)
	set_modulate(modulate)
	set_energy(energy)
	set_blend(blend)
	set_mask(mask)
	preload("matcap_cleanup.gd").new().setup(self)

func _update() -> void:
	if adjusted_shader:
		var code := transform_material()
		if not code.empty():
			adjusted_shader.code = code
		original_shader = VisualServer.material_get_shader(get_rid())
		VisualServer.material_set_shader(get_rid(), adjusted_shader.get_rid())


func _post_draw() -> void:
	VisualServer.material_set_shader(get_rid(), original_shader)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		VisualServer.disconnect("frame_pre_draw", self, "_update")
		VisualServer.disconnect("frame_post_draw", self, "_post_draw")


static func find_closing_bracket(string : String, open_bracket_idx : int) -> int:
	var bracket_count := 1
	var open_bracket := string.substr(open_bracket_idx, 1)
	var close_bracket := "}" if open_bracket == "{" else ")" if open_bracket == "(" else "]"
	var index := open_bracket_idx
	
	while index < string.length():
		var open_index = string.find(open_bracket, index+1)
		var close_index = string.find(close_bracket, index+1)
		
		if close_index != -1 and (open_index == -1 or close_index < open_index):
			index = close_index
			bracket_count -= 1
		elif open_index != -1 and (close_index == -1 or open_index < close_index):
			index = open_index
			bracket_count += 1
		else:
			return -1
		
		if bracket_count <= 0:
			return index
	
	return -1
