#include <stdlib.h>
#include <string.h>

#include "webp/decode.h"
#include "webp/demux.h"

typedef struct banana_webp_stream {
    WebPAnimDecoder *dec;
    int width;
    int height;
    int last_timestamp;
} banana_webp_stream;

int banana_webp_is_webp(const unsigned char *data, int len) {
    if (!data || len < 12) return 0;
    return memcmp(data, "RIFF", 4) == 0 && memcmp(data + 8, "WEBP", 4) == 0;
}

// Returns the frame count, or -1 if the data is not a well-formed WebP.
int banana_webp_scan(const unsigned char *data, int len, int *delays_ms, int max_delays) {
    if (!banana_webp_is_webp(data, len)) return -1;
    WebPData blob = {data, (size_t)len};
    WebPDemuxer *demux = WebPDemux(&blob);
    if (!demux) return -1;

    int count = (int)WebPDemuxGetI(demux, WEBP_FF_FRAME_COUNT);
    if (delays_ms && max_delays > 0) {
        WebPIterator it;
        if (WebPDemuxGetFrame(demux, 1, &it)) {
            int i = 0;
            do {
                if (i >= max_delays) break;
                delays_ms[i++] = it.duration;
            } while (WebPDemuxNextFrame(&it));
            WebPDemuxReleaseIterator(&it);
        }
    }
    WebPDemuxDelete(demux);
    return count;
}

// Decodes a still image (or the first frame of an animation) as straight RGBA8.
// Returns 1 on success, -1 on error or short buffer.
int banana_webp_decode(const unsigned char *data, int len, unsigned char *dst, size_t dst_bytes, int *w, int *h) {
    int iw = 0, ih = 0;
    if (!WebPGetInfo(data, (size_t)len, &iw, &ih)) return -1;
    if (w) *w = iw;
    if (h) *h = ih;
    if (!dst) return 1;
    size_t stride = (size_t)iw * 4;
    if (dst_bytes < stride * (size_t)ih) return -1;
    if (!WebPDecodeRGBAInto(data, (size_t)len, dst, dst_bytes, (int)stride)) return -1;
    return 1;
}

// Returns NULL if the data is not a WebP or allocation fails. `data` must stay
// alive and unmodified until banana_webp_close.
banana_webp_stream *banana_webp_open(const unsigned char *data, int len, int *w, int *h) {
    if (!banana_webp_is_webp(data, len)) return 0;

    WebPAnimDecoderOptions opts;
    if (!WebPAnimDecoderOptionsInit(&opts)) return 0;
    // Straight alpha to match stb's output for every other format.
    opts.color_mode = MODE_RGBA;
    opts.use_threads = 0;

    WebPData blob = {data, (size_t)len};
    WebPAnimDecoder *dec = WebPAnimDecoderNew(&blob, &opts);
    if (!dec) return 0;

    WebPAnimInfo info;
    if (!WebPAnimDecoderGetInfo(dec, &info)) {
        WebPAnimDecoderDelete(dec);
        return 0;
    }

    banana_webp_stream *st = (banana_webp_stream *)calloc(1, sizeof(banana_webp_stream));
    if (!st) {
        WebPAnimDecoderDelete(dec);
        return 0;
    }
    st->dec = dec;
    st->width = (int)info.canvas_width;
    st->height = (int)info.canvas_height;
    if (w) *w = st->width;
    if (h) *h = st->height;
    return st;
}

// Composites the next frame onto the canvas and copies it as RGBA8 into `dst`.
// Returns 1 on a decoded frame, 0 at end of animation, -1 on error or short buffer.
int banana_webp_next(banana_webp_stream *st, unsigned char *dst, size_t dst_bytes, int *delay_ms) {
    if (!st || !dst) return 0;
    if (!WebPAnimDecoderHasMoreFrames(st->dec)) return 0;

    size_t frame_bytes = (size_t)st->width * (size_t)st->height * 4;
    if (dst_bytes < frame_bytes) return -1;

    uint8_t *buf = 0;
    int timestamp = 0;
    if (!WebPAnimDecoderGetNext(st->dec, &buf, &timestamp)) return -1;
    memcpy(dst, buf, frame_bytes);

    // libwebp reports end timestamps, so the hold time is the gap to the previous one.
    if (delay_ms) *delay_ms = timestamp - st->last_timestamp;
    st->last_timestamp = timestamp;
    return 1;
}

void banana_webp_rewind(banana_webp_stream *st) {
    if (!st) return;
    WebPAnimDecoderReset(st->dec);
    st->last_timestamp = 0;
}

void banana_webp_close(banana_webp_stream *st) {
    if (!st) return;
    WebPAnimDecoderDelete(st->dec);
    free(st);
}
