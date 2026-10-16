shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Текстура SubViewport передаётся из PortalController.
// По вертикали изображение переворачивается, чтобы оно совпадало с ориентацией проёма.
uniform sampler2D portal_texture : source_color, filter_linear;

void fragment() {
	vec2 portal_uv = vec2(UV.x, 1.0 - UV.y);
	ALBEDO = texture(portal_texture, portal_uv).rgb;
	ALPHA = 1.0;
}
