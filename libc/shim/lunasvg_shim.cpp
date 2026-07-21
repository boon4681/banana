#include "lunasvg.h"
#include <cstdint>
#include <cstddef>

extern "C" {

void *banana_svg_parse(const char *data, size_t length) {
    if (!data || length == 0) return nullptr;
    return lunasvg::Document::loadFromData(data, length).release();
}

void banana_svg_destroy(void *handle) {
    delete static_cast<lunasvg::Document *>(handle);
}

// Intrinsic size in user units; the viewBox extent when one is present.
bool banana_svg_size(void *handle, float *width, float *height) {
    auto *doc = static_cast<lunasvg::Document *>(handle);
    if (!doc || !width || !height) return false;
    *width = doc->width();
    *height = doc->height();
    return *width > 0 && *height > 0;
}

bool banana_svg_render(void *handle, uint8_t *pixels, int width, int height,
    int stride, float scale_x, float scale_y) {
    auto *doc = static_cast<lunasvg::Document *>(handle);
    if (!doc || !pixels || width <= 0 || height <= 0 || stride < width*4) return false;
    lunasvg::Bitmap bitmap(pixels, width, height, stride);
    bitmap.clear(0x00000000);
    doc->render(bitmap, lunasvg::Matrix(scale_x, 0, 0, scale_y, 0, 0));
    bitmap.convertToRGBA();
    return true;
}

}
