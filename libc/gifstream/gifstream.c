// Streaming GIF decoder built on a stb_image.h
// stb_image.h in this directory is an unmodified copy of the vendored source.

#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include "stb_image.h"

typedef struct banana_gif_stream {
    stbi__context s;
    stbi__gif g;
    // Rolling copies of the two most recent frames.
    unsigned char *prev[2];
    size_t prev_bytes;
    int index;
    int done;
} banana_gif_stream;

// Counts frames and collects delays by walking the GIF block structure without
// decoding any pixels, so callers can size playback state up front while
// keeping only a bounded number of decoded frames resident.
//
// Writes up to `max_delays` delays (in milliseconds) into `delays_ms` and
// returns the total frame count, or -1 if the data is not a well-formed GIF.
int banana_gif_scan(const unsigned char *data, int len, int *delays_ms, int max_delays) {
    if (!data || len < 13) return -1;
    if (data[0] != 'G' || data[1] != 'I' || data[2] != 'F') return -1;

    int p = 6;
    int flags = data[10];
    p = 13;
    if (flags & 0x80) p += 3 * (2 << (flags & 7)); // global color table
    if (p > len) return -1;

    int count = 0;
    int pending_delay = 0;
    while (p < len) {
        unsigned char block = data[p++];
        if (block == 0x3B) break; // trailer
        if (block == 0x21) {      // extension
            if (p >= len) return -1;
            unsigned char label = data[p++];
            if (label == 0xF9 && p + 5 <= len) {
                // Graphic control: delay is little-endian centiseconds.
                pending_delay = (data[p + 2] | (data[p + 3] << 8)) * 10;
            }
            while (p < len) { // skip sub-blocks
                unsigned char sz = data[p++];
                if (sz == 0) break;
                p += sz;
            }
            continue;
        }
        if (block != 0x2C) return -1; // not an image descriptor
        if (p + 9 > len) return -1;
        int lflags = data[p + 8];
        p += 9;
        if (lflags & 0x80) p += 3 * (2 << (lflags & 7)); // local color table
        if (p >= len) return -1;
        ++p; // LZW minimum code size
        while (p < len) { // skip image data sub-blocks
            unsigned char sz = data[p++];
            if (sz == 0) break;
            p += sz;
        }
        if (delays_ms && count < max_delays) delays_ms[count] = pending_delay;
        ++count;
        pending_delay = 0;
    }
    return count;
}

// Returns NULL if the data is not a GIF or allocation fails. `data` must stay
// alive and unmodified until banana_gif_close.
banana_gif_stream *banana_gif_open(const unsigned char *data, int len, int *w, int *h) {
    if (!data || len <= 0) return 0;

    // Canvas size is only set on the stream's own struct after the first
    // decode, so probe a throwaway header parse to report it up front.
    stbi__context probe;
    stbi__gif hdr;
    int comp = 0;
    memset(&hdr, 0, sizeof(hdr));
    stbi__start_mem(&probe, data, len);
    if (!stbi__gif_header(&probe, &hdr, &comp, 1)) {
        STBI_FREE(hdr.out);
        STBI_FREE(hdr.history);
        STBI_FREE(hdr.background);
        return 0;
    }
    if (w) *w = hdr.w;
    if (h) *h = hdr.h;
    STBI_FREE(hdr.out);
    STBI_FREE(hdr.history);
    STBI_FREE(hdr.background);

    banana_gif_stream *st = (banana_gif_stream *)calloc(1, sizeof(banana_gif_stream));
    if (!st) return 0;
    stbi__start_mem(&st->s, data, len);
    return st;
}

// Decodes the next frame as RGBA8 into `dst`. Returns 1 on a decoded frame,
// 0 at end of animation, -1 on error or short buffer.
int banana_gif_next(banana_gif_stream *st, unsigned char *dst, size_t dst_bytes, int *delay_ms) {
    if (!st || st->done || !dst) return 0;

    unsigned char *two_back = st->index >= 2 ? st->prev[st->index % 2] : 0;

    int comp = 0;
    stbi_uc *u = stbi__gif_load_next(&st->s, &st->g, &comp, 4, two_back);
    if (u == (stbi_uc *)&st->s) u = 0; // end-of-animation marker
    if (!u) {
        st->done = 1;
        return 0;
    }

    size_t frame_bytes = (size_t)st->g.w * (size_t)st->g.h * 4;
    if (dst_bytes < frame_bytes) {
        st->done = 1;
        return -1;
    }
    memcpy(dst, u, frame_bytes);

    if (st->prev_bytes != frame_bytes) {
        free(st->prev[0]);
        free(st->prev[1]);
        st->prev[0] = (unsigned char *)malloc(frame_bytes);
        st->prev[1] = (unsigned char *)malloc(frame_bytes);
        st->prev_bytes = frame_bytes;
        if (!st->prev[0] || !st->prev[1]) {
            st->done = 1;
            return -1;
        }
    }
    memcpy(st->prev[st->index % 2], u, frame_bytes);

    if (delay_ms) *delay_ms = st->g.delay;
    ++st->index;
    return 1;
}

void banana_gif_close(banana_gif_stream *st) {
    if (!st) return;
    STBI_FREE(st->g.out);
    STBI_FREE(st->g.history);
    STBI_FREE(st->g.background);
    free(st->prev[0]);
    free(st->prev[1]);
    free(st);
}
