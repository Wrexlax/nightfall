shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Steam Frame curved screen. SteamVR has no cylinder composition layers, so a
// curved screen is drawn in the 3D scene (like Moonlight XR) using the same
// already-composed screen viewport(s) the flat quad layer shows. Stereo modes
// show the left-eye viewport to the left eye and the right-eye one to the right.
uniform sampler2D tex_mono : source_color, filter_linear, repeat_disable;
uniform sampler2D tex_left : source_color, filter_linear, repeat_disable;
uniform sampler2D tex_right : source_color, filter_linear, repeat_disable;
uniform bool stereo = false;
// Fraction of the viewport taken by the fixed bezel padding on each side.
uniform vec2 inset = vec2(0.0);

// The screen viewport has no mipmaps and is usually sharper than the headset's
// eye image, so a single lookup shimmers on fine text. Average four lookups
// spread over the pixel's footprint (rotated grid) - a cheap stand-in for the
// mip chain Moonlight XR builds for its curved picture.
vec3 supersample(sampler2D t, vec2 uv, vec2 dx, vec2 dy) {
	vec3 c = texture(t, uv + dx * -0.125 + dy * -0.375).rgb;
	c += texture(t, uv + dx * 0.375 + dy * -0.125).rgb;
	c += texture(t, uv + dx * 0.125 + dy * 0.375).rgb;
	c += texture(t, uv + dx * -0.375 + dy * 0.125).rgb;
	return c * 0.25;
}

void fragment() {
	vec2 uv = mix(inset, vec2(1.0) - inset, UV);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	if (stereo) {
		ALBEDO = (VIEW_INDEX == 1) ? supersample(tex_right, uv, dx, dy) : supersample(tex_left, uv, dx, dy);
	} else {
		ALBEDO = supersample(tex_mono, uv, dx, dy);
	}
}
