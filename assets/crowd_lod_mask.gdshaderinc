// Ordered coverage keeps the two silhouettes opaque, with no double exposure.
float lod_threshold(vec2 pixel) {
	ivec2 p = ivec2(pixel) & ivec2(3);
	int x = p.x ^ p.y;
	int rank = ((x & 1) << 3) | ((p.y & 1) << 2) | ((x & 2) >> 0) | ((p.y & 2) >> 1);
	return (float(rank) + 0.5) / 16.0;
}
