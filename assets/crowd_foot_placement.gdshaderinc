global uniform sampler2D crowd_foot_ground : filter_nearest, repeat_disable;
global uniform vec4 crowd_foot_grid;
uniform ivec3 foot_left = ivec3(-1);
uniform ivec3 foot_right = ivec3(-1);
uniform vec2 foot_contact_height;

float foot_ground_height(vec2 world_xz) {
	vec2 last = vec2(textureSize(crowd_foot_ground, 0) - ivec2(1));
	vec2 cell_position = clamp((world_xz + crowd_foot_grid.xy) * crowd_foot_grid.zw,
		vec2(0.0), last - vec2(0.001));
	ivec2 cell = ivec2(floor(cell_position));
	vec2 weight = fract(cell_position);
	float a = texelFetch(crowd_foot_ground, cell, 0).r;
	float b = texelFetch(crowd_foot_ground, cell + ivec2(1, 0), 0).r;
	float c = texelFetch(crowd_foot_ground, cell + ivec2(0, 1), 0).r;
	if (weight.x + weight.y <= 1.0) {
		return a + (b - a) * weight.x + (c - a) * weight.y;
	}
	float d = texelFetch(crowd_foot_ground, cell + ivec2(1, 1), 0).r;
	return d + (c - d) * (1.0 - weight.x) + (b - d) * (1.0 - weight.y);
}

vec3 foot_joint(int bone, ivec2 frames, float phase, ivec2 old_frames, float old_phase, float blend) {
	int column = bone * 4 + 3;
	vec3 current = mix(texelFetch(pose_bones, ivec2(column, frames.x), 0).xyz,
		texelFetch(pose_bones, ivec2(column, frames.y), 0).xyz, phase);
	if (blend < 1.0) {
		vec3 previous = mix(texelFetch(pose_bones, ivec2(column, old_frames.x), 0).xyz,
			texelFetch(pose_bones, ivec2(column, old_frames.y), 0).xyz, old_phase);
		current = mix(previous, current, blend);
	}
	return current;
}

float foot_shin_distance(vec3 vertex, vec3 knee, vec3 ankle) {
	vec3 shin = knee - ankle;
	float along = clamp(dot(vertex - ankle, shin) / max(dot(shin, shin), 0.001), 0.0, 1.0);
	vec3 separation = vertex - mix(ankle, knee, along);
	return dot(separation, separation);
}

float foot_leg_offset(float height, mat4 model, vec3 knee, vec3 ankle, int toe_bone,
		ivec2 frames, float phase, ivec2 old_frames, float old_phase, float blend) {
	// The baked skin follows the ankle fully and tapers into the knee.
	float weight = 1.0 - smoothstep(ankle.y + 0.075, max(ankle.y + 0.15, knee.y + 0.12), height);
	if (weight <= 0.0) {
		return 0.0;
	}
	vec3 toe = foot_joint(toe_bone, frames, phase, old_frames, old_phase, blend);
	float clearance = min(ankle.y - foot_contact_height.x, toe.y - foot_contact_height.y);
	float contact = 1.0 - smoothstep(0.025, 0.095, clearance);
	if (contact <= 0.0) {
		return 0.0;
	}
	vec2 point = (model * vec4(mix(ankle, toe, 0.55), 1.0)).xz;
	float rise = foot_ground_height(point) - foot_ground_height(model[3].xz);
	return clamp(rise, -0.18, 0.22) * contact * weight;
}

float foot_placement(vec3 vertex, mat4 model, ivec2 frames, float phase,
		ivec2 old_frames, float old_phase, float blend) {
	if (vertex.y < -0.10 || vertex.y >= 0.72 || foot_left.x < 0 || foot_right.x < 0 || crowd_foot_grid.z <= 0.0) {
		return 0.0;
	}
	vec3 left_knee = foot_joint(foot_left.x, frames, phase, old_frames, old_phase, blend);
	vec3 left_ankle = foot_joint(foot_left.y, frames, phase, old_frames, old_phase, blend);
	vec3 right_knee = foot_joint(foot_right.x, frames, phase, old_frames, old_phase, blend);
	vec3 right_ankle = foot_joint(foot_right.y, frames, phase, old_frames, old_phase, blend);
	float difference = foot_shin_distance(vertex, right_knee, right_ankle) -
		foot_shin_distance(vertex, left_knee, left_ankle);
	float left_weight = smoothstep(-0.003, 0.003, difference);
	float offset = 0.0;
	if (left_weight > 0.0) {
		offset += left_weight * foot_leg_offset(vertex.y, model, left_knee, left_ankle, foot_left.z,
			frames, phase, old_frames, old_phase, blend);
	}
	if (left_weight < 1.0) {
		offset += (1.0 - left_weight) * foot_leg_offset(vertex.y, model, right_knee, right_ankle, foot_right.z,
			frames, phase, old_frames, old_phase, blend);
	}
	return offset * (1.0 - smoothstep(0.62, 0.72, vertex.y));
}
