// Offline tool. Compile with meshoptimizer's simplifier.cpp and allocator.cpp.
#include "meshoptimizer.h"
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <vector>

template <typename T>
bool read(std::istream &stream, T *values, size_t count) {
    return static_cast<bool>(stream.read(reinterpret_cast<char *>(values), count * sizeof(T)));
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    std::ifstream input(argv[1], std::ios::binary);
    uint32_t counts[4];
    if (!read(input, counts, 4) || counts[0] == 0 || counts[0] > 65535 ||
            counts[1] == 0 || counts[1] % 3 != 0 || counts[2] < 5 || counts[2] > 20) return 3;
    const auto [vertex_count, index_count, attribute_count, preserve_uniform] = counts;
    std::vector<float> positions(vertex_count * 3), attributes(vertex_count * attribute_count);
    std::vector<unsigned int> indices(index_count), result(index_count);
    if (!read(input, positions.data(), positions.size()) || !read(input, attributes.data(), attributes.size()) ||
            !read(input, indices.data(), indices.size()) || *std::max_element(indices.begin(), indices.end()) >= vertex_count) return 4;
    std::vector<float> weights(attribute_count, 1.4f);
    weights[0] = weights[1] = 6.0f; // UV texture coordinates.
    weights[2] = weights[3] = weights[4] = .35f; // Normal orientation.
    std::vector<unsigned char> locked(vertex_count, 0);
    if (preserve_uniform) {
        float bottom = positions[1], top = bottom;
        for (size_t i = 0; i < vertex_count; ++i) {
            bottom = std::min(bottom, positions[i * 3 + 1]);
            top = std::max(top, positions[i * 3 + 1]);
        }
        for (size_t i = 0; i < vertex_count; ++i) {
            const float height = (positions[i * 3 + 1] - bottom) / (top - bottom);
            if (height < .51f || height > .79f) locked[i] = meshopt_SimplifyVertex_Lock;
        }
    }
    std::ofstream output(argv[2], std::ios::binary);
    for (size_t level = 0; level < 2; ++level) {
        const size_t target = (index_count / 3) * (level == 0 ? 72 : 41) / 100 * 3;
        const float max_error = level == 0 ? .025f : .050f;
        const uint32_t count = static_cast<uint32_t>(meshopt_simplifyWithAttributes(result.data(), indices.data(),
            index_count, positions.data(), vertex_count, 3 * sizeof(float), attributes.data(),
            attribute_count * sizeof(float), weights.data(), attribute_count, locked.data(), target, max_error,
            meshopt_SimplifyLockBorder | meshopt_SimplifyRegularize, nullptr));
        if (count < 3) return 5;
        output.write(reinterpret_cast<const char *>(&count), sizeof(count));
        output.write(reinterpret_cast<const char *>(result.data()), count * sizeof(result[0]));
    }
    return output ? 0 : 6;
}
