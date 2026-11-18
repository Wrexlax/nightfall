shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_premul_alpha, depth_draw_never;

// Steam Frame ambient glow, drawn in the 3D scene just behind the screen
// (SteamVR cannot show the cylinder layer used elsewhere). The halo viewport
// is rendered over a transparent background, so its colour is premultiplied.
uniform sampler2D halo : source_color, filter_linear, repeat_disable;

void fragment() {
	vec4 c = texture(halo, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
