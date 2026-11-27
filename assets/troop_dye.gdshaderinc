float troop_dye_strength(float view_depth) {
	return mix(.38, 1.0, smoothstep(14.0, 72.0, view_depth));
}

vec3 troop_dye(vec3 base, vec3 dye, float mask, float view_depth) {
	float luminance = dot(base, vec3(.30, .59, .11));
	float grain = mix(.42, 1.12, smoothstep(.012, .20, luminance));
	return mix(base, dye * grain, mask * troop_dye_strength(view_depth));
}

float warrior_fabric(vec3 base) {
	float red = max(base.r, .001);
	return smoothstep(.12, .38, (base.r - base.g) / red)
		* smoothstep(.78, .95, base.b / max(base.g, .001))
		* smoothstep(.016, .045, red);
}

float warm_wood(vec3 base) {
	float peak = max(base.r, max(base.g, base.b));
	return smoothstep(.08, .27, (peak - base.b) / max(peak, .001))
		* smoothstep(.018, .065, peak);
}
