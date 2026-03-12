// Copyright © 2025 Cory Petkovsek, Roope Palmroos, and Contributors.
//
// Grass shader for a cross-quad mesh (two perpendicular quads per particle).
// Designed for use with QuadMesh (draw_pass_1) + PlaneMesh FACE_X (draw_pass_2).
//
// Wind and color logic mirrors the original grass.gdshader, with two changes:
//   1. Height factor is derived from UV.y instead of VERTEX.y, which works
//      correctly for both QuadMesh and PlaneMesh FACE_X (both map UV.y to world Y,
//      with UV.y = 0 at the tip and UV.y = 1 at the base).
//   2. Ribbon tip-pinching is removed; alpha cutout via discard replaces it.
//      Using discard (rather than ALPHA_SCISSOR_THRESHOLD) keeps the shader in
//      the opaque render queue, which is important for large particle counts.

shader_type spatial;

render_mode skip_vertex_transform, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform sampler2D grass_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

varying vec4 data;

void vertex() {
	// Height factor: 1.0 at the tip (UV.y = 0), 0.0 at the base (UV.y = 1).
	// UV.y maps to world Y on both QuadMesh and PlaneMesh FACE_X.
	data[2] = 1.0 - UV.y;
	data[2] *= data[2]; // make non-linear

	// Brighten tips
	COLOR = mix(COLOR, vec4(1.0), smoothstep(0.9, 1.0, data[2]));
	// Darken base, skip if scale is less than threshold, as this means "grow in" is occurring.
	COLOR *= INSTANCE_CUSTOM[3] < 0.35 ? 1. : mix(1.0, 0.75, smoothstep(0.35, 0.0, data[2]));
	// Save red/green shift for fragment
	data.rg = INSTANCE_CUSTOM.rg;

	// World space vertex
	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Get wind force and scale from process()
	float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	float force = INSTANCE_CUSTOM[2] * data[2] * scale;
	// Add some cheap jitter at high wind values
	force -= fract(force * 256.0) * force * 0.05;
	// Curve the result
	force = pow(force, 0.707);

	// These 2 combined result in a decent bend without resorting to matrices or pivot data.
	// Lateral move and wobble
	float lateral_wobble = sin(TIME * 2.0 * (1.0 + data.r + data.g)) * 0.25 * (1.0 - INSTANCE_CUSTOM[2]);
	vec2 direction = normalize(wind_direction);
	w_vertex.xz -= (vec2(-direction.y, direction.x) * lateral_wobble + direction) * force;
	// Flatten
	w_vertex.y -= INSTANCE_CUSTOM[2] * force * data[2];

	// Save final wind force value for fragment.
	data[3] = force;

	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}

void fragment() {
	vec4 tex = texture(grass_texture, UV);
	// Discard transparent pixels (keeps shader in opaque render queue).
	if (tex.a < alpha_scissor_threshold) discard;

	// Base color modulated by texture RGB.
	ALBEDO = vec3(0.20, 0.22, 0.05) * (data[2] * 0.5 + 0.5);
	ALBEDO.rg *= (data.rg * 0.3 + 0.9);
	ALBEDO *= pow(COLOR.rgb, vec3(2.2));
	ALBEDO *= tex.rgb;
	// Modify roughness / specular based on wind force for added detail
	float spec_rough = clamp(max(data[2], data[3]), 0., 1.);
	ROUGHNESS = 1. - spec_rough;
	SPECULAR = clamp(spec_rough * 0.25, 0., .15);

	BACKLIGHT = vec3(0.33);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = pow(ALBEDO, vec3(0.4));
	#endif
}
