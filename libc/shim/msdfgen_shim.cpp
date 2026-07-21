#include "msdfgen.h"
#include "core/edge-coloring.h"
#include <algorithm>
#include <cmath>
#include <cstdint>

extern "C" bool banana_msdf_generate(const float *curve_points, int curve_count,
    const uint32_t *contour_ends, int contour_count, int width, int height,
    double scale, double translate_x, double translate_y, double pixel_range, uint8_t *rgba) {
    if (!curve_points || !contour_ends || !rgba || curve_count <= 0 || contour_count <= 0 || width <= 0 || height <= 0 || scale <= 0)
        return false;
    msdfgen::Shape shape;
    int first = 0;
    for (int ci = 0; ci < contour_count; ++ci) {
        int end = int(contour_ends[ci]);
        if (end <= first || end > curve_count) return false;
        msdfgen::Contour &contour = shape.addContour();
        for (int i = first; i < end; ++i) {
            const float *p = curve_points+6*i;
            contour.addEdge(msdfgen::EdgeHolder(new msdfgen::QuadraticSegment(
                msdfgen::Point2(p[0], p[1]), msdfgen::Point2(p[2], p[3]), msdfgen::Point2(p[4], p[5]))));
        }
        first = end;
    }
    if (first != curve_count || !shape.validate()) return false;
    shape.normalize();
    msdfgen::edgeColoringInkTrap(shape, 3.0, 0);
    msdfgen::Bitmap<float, 3> bitmap(width, height);
    msdfgen::SDFTransformation transform(
        msdfgen::Projection(msdfgen::Vector2(scale), msdfgen::Vector2(translate_x, translate_y)),
        msdfgen::Range(pixel_range/scale));
    msdfgen::generateMSDF(bitmap, shape, transform);
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
        const float *src = bitmap(x, y);
        uint8_t *dst = rgba+4*(y*width+x);
        for (int c = 0; c < 3; ++c) dst[c] = uint8_t(std::lround(255.0*std::clamp(double(src[c]), 0.0, 1.0)));
        dst[3] = 255;
    }
    return true;
}
