#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "budoux.h"
#include "linebreakdef.h"

void banana_complex_context_utf32(const uint32_t *text, size_t length, const char *lang, uint8_t *out) {
    struct LineBreakContext ctx;
    if (!text || length == 0) return;
    lb_init_break_context(&ctx, text[0], lang);
    for (size_t i = 0; i < length; i++) out[i] = lb_get_char_class(&ctx, text[i]) == LBP_SA;
}

enum {
    BANANA_BUDOUX_NONE,
    BANANA_BUDOUX_JA,
    BANANA_BUDOUX_ZH_HANS,
    BANANA_BUDOUX_ZH_HANT,
    BANANA_BUDOUX_TH,
};

void banana_budoux_breaks_utf32(const uint32_t *text, size_t length, int model, uint8_t *breaks) {
    boundary_iterator_t iterator;
    int32_t start;
    int32_t end;

    memset(breaks, 0, length + 1);
    if (!text || length == 0 || length > INT32_MAX) return;

    switch (model) {
    case BANANA_BUDOUX_JA:
        iterator = boundary_iterator_init_ja_utf32(text, (int32_t)length);
        break;
    case BANANA_BUDOUX_ZH_HANS:
        iterator = boundary_iterator_init_zh_hans_utf32(text, (int32_t)length);
        break;
    case BANANA_BUDOUX_ZH_HANT:
        iterator = boundary_iterator_init_zh_hant_utf32(text, (int32_t)length);
        break;
    case BANANA_BUDOUX_TH:
        iterator = boundary_iterator_init_th_utf32(text, (int32_t)length);
        break;
    default:
        return;
    }

    while (boundary_iterator_next(&iterator, &start, &end)) {
        if (end > 0 && (size_t)end <= length) breaks[end] = 1;
    }
}
