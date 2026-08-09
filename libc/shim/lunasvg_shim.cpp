#include "lunasvg.h"
#include <cstdint>
#include <cstddef>
#include <string>

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

// Resolves currentColor for the whole document.
void banana_svg_set_current_color(void *handle, uint8_t r, uint8_t g, uint8_t b) {
    auto *doc = static_cast<lunasvg::Document *>(handle);
    if (!doc) return;

    static const char digits[] = "0123456789abcdef";
    char css[] = "svg{color:#000000}";
    char *hex = css + 11;
    const uint8_t rgb[3] = {r, g, b};
    for (int i = 0; i < 3; ++i) {
        hex[i * 2 + 0] = digits[rgb[i] >> 4];
        hex[i * 2 + 1] = digits[rgb[i] & 0xf];
    }

    doc->applyStyleSheet(std::string(css, sizeof(css) - 1));
    doc->forceLayout();
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
