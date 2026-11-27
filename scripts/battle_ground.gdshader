shader_type spatial;

uniform sampler2D grass_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D silt_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float snow = 0.0;
uniform vec4 road_curve = vec4(100.0, 12.0, .018, 0.0);
uniform vec4 tracks[7];
uniform int track_count = 0;

varying vec3 world;
varying vec4 cover;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cover = COLOR;
}

void fragment() {
	vec2 point = world.xz;
	vec2 grass_uv = point * .24;
	vec3 grass = texture(grass_color, grass_uv).rgb;
	float noise = dot(texture(grass_color, point * .009 + vec2(.31, .67)).rgb, vec3(.25, .58, .17));
	float macro = smoothstep(.04, .26, noise);
	float variation = clamp(.2 + noise * 2.0, 0.0, 1.0);
	vec3 turf = grass * mix(vec3(.41, .47, .28), vec3(.72, .74, .48), mix(variation, macro, .56));
	float fine_detail = 1.0 - smoothstep(28.0, 120.0, distance(CAMERA_POSITION_WORLD, world));
	vec3 dirt = texture(dirt_color, point * .35, mix(.90, 0.0, fine_detail)).rgb;
	dirt = mix(dirt, vec3(dot(dirt, vec3(.2126, .7152, .0722))), .20);
	vec3 leaves = texture(litter_color, point * .46 + vec2(.4, .3), mix(1.15, 0.0, fine_detail)).rgb;
	vec2 rock_uv = point * .19;
	vec3 rock = texture(rock_color, rock_uv).rgb;

	float road_x = road_curve.x + road_curve.y * sin(world.z * road_curve.z + road_curve.w);
	float road_distance = abs(world.x - road_x);
	float road = 1.0 - smoothstep(1.8, 3.8, road_distance + (grass.r - .4) * .7);
	for (int i = 0; i < track_count; i++) {
		vec4 track = tracks[i];
		vec2 minimum = min(track.xy, track.zw) - 2.0;
		vec2 maximum = max(track.xy, track.zw) + 2.0;
		if (all(greaterThanEqual(point, minimum)) && all(lessThanEqual(point, maximum))) {
			vec2 edge = track.zw - track.xy;
			float along = clamp(dot(point - track.xy, edge) / max(dot(edge, edge), .001), 0.0, 1.0);
			float distance_to_track = length(point - track.xy - edge * along);
			road = max(road, .85 * (1.0 - smoothstep(.72, 1.72, distance_to_track)));
		}
	}

	float dry = smoothstep(.12, .70, cover.r + (grass.r - .14) * .30);
	float litter = smoothstep(.07, .91, cover.g);
	float exposed = smoothstep(.06, .82, cover.b);
	float bank = smoothstep(.05, .86, cover.a);
	float damp = 1.0 - smoothstep(-.3, 3.2, world.y);
	vec3 silt_sample = texture(silt_color, point * .36 + vec2(.2, .7)).rgb;
	vec3 silt = silt_sample * mix(vec3(.91, .95, .92), vec3(.38, .47, .52), damp);
	vec3 ground = mix(turf, dirt * vec3(.73, .75, .69), dry);
	ground = mix(ground, leaves * vec3(.91, .91, .77), litter * .86);
	ground = mix(ground, rock * mix(.60, .78, variation), exposed);
	ground = mix(ground, mix(silt, rock * .57, .07), bank);
	ground = mix(ground, dirt * vec3(.92, .88, .78), road * .94);

	float snow_mask = (.62 + .38 * smoothstep(.04, .24, noise + grass.r * .08)) * snow;
	snow_mask *= 1.0 - max(road * .55, exposed * .28);
	snow_mask *= 1.0 - bank * damp * .50;
	ALBEDO = mix(ground, vec3(.48, .58, .68) * (.79 + grass.r * .21), snow_mask);

	vec3 grass_detail = texture(grass_normal, grass_uv).rgb;
	float soil_coverage = max(max(dry, litter), max(road, bank));
	float soft_ground = soil_coverage * mix(.91, .66, fine_detail);
	vec3 packed_normal = mix(grass_detail, vec3(.5, .5, 1.0), soft_ground);
	NORMAL_MAP = mix(packed_normal, texture(rock_normal, rock_uv).rgb, exposed * (1.0 - max(road, bank)));
	NORMAL_MAP_DEPTH = mix(.60, .18, snow_mask);
	ROUGHNESS = mix(mix(.96, .84, exposed), .66, bank * damp * (1.0 - road));
	SPECULAR = mix(.15, .33, bank * damp);
}
