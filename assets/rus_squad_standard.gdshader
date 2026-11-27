shader_type canvas_item;
render_mode unshaded;

void fragment() {
	// Shift the madder-dyed cloth while keeping wood, brass and embroidery warm.
	vec3 fabric = COLOR.rgb;
	float red_dye = smoothstep(0.10, 0.30, fabric.r - fabric.g)
		* (1.0 - smoothstep(0.25, 0.48, fabric.g / max(fabric.r, 0.001)));
	vec3 blue_dye = vec3(fabric.b * 1.35, fabric.g * 1.5, fabric.r * 0.87);
	COLOR.rgb = mix(fabric, blue_dye, red_dye);
}
