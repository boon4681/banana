package platform

import "base:runtime"
import "core:c"
import "src:core/render"
import gif "src:patches/std/image"

// Number of decoded frames an Animation keeps resident.
GIF_ANIMATION_RING :: 4

// Bounded-memory animated image.
GIF_Data :: struct {
    encoded: []u8, // owned copy; the decoder reads from it for the stream's life
    delays:  []f32,
    ring:    [GIF_ANIMATION_RING]^render.Image,
    ring_at: [GIF_ANIMATION_RING]int, // frame index resident in each slot, -1 when empty
    stream:  ^gif.Stream,
    decoded: int, // frames pulled from the stream so far
    width:   int,
    height:  int,
    window:  ^Window,
}

// load all frames
load_image_frames :: proc(w: ^Window, encoded: []u8) -> (frames: []Image_Frame, err: Image_Error) {
    if w == nil do return nil, .Decode_Failed
    if len(encoded) == 0 do return nil, .Empty_Input
    if len(encoded) > int(max(c.int)) do return nil, .Input_Too_Large

    // stb only animates GIF; anything else decodes as a lone frame.
    if !_is_gif(encoded) {
        image := load_image_from_bytes(w, encoded) or_return
        single, alloc_err := make([]Image_Frame, 1, w.allocator)
        if alloc_err != nil {
            free_image(w, image)
            return nil, .Allocation_Failed
        }
        single[0] = {image = image, delay = 0}
        return single, .None
    }

    x, y: c.int
    stream := gif.open(raw_data(encoded), c.int(len(encoded)), &x, &y)
    if stream == nil do return nil, .Decode_Failed
    defer gif.close(stream)

    width, height := int(x), int(y)
    if width <= 0 || height <= 0 do return nil, .Invalid_Dimensions
    if width > max(int) / height / 4 do return nil, .Invalid_Dimensions
    frame_bytes := width * height * 4

    list := make([dynamic]Image_Frame, 0, 8, w.allocator)
    for {
        pixels, pix_err := make([]u8, frame_bytes, w.allocator)
        if pix_err != nil {
            _free_partial_frames(w, list[:])
            return nil, .Allocation_Failed
        }

        ms := c.int(0)
        status := gif.next(stream, raw_data(pixels), c.size_t(frame_bytes), &ms)
        if status != 1 {
            delete(pixels, w.allocator)
            if status < 0 {
                _free_partial_frames(w, list[:])
                return nil, .Decode_Failed
            }
            break
        }

        image := new(render.Image, w.allocator)
        image^ = render.Image {
            data   = pixels,
            w      = u32(width),
            h      = u32(height),
            format = .RGBA8,
        }
        append(&w.images, image)

        if ms <= 10 do ms = 100
        append(&list, Image_Frame{image = image, delay = f32(ms) / 1000})
    }

    if len(list) == 0 {
        delete(list)
        return nil, .Decode_Failed
    }
    return list[:], .None
}

@(private="file")
_free_partial_frames :: proc(w: ^Window, frames: []Image_Frame) {
    for f in frames do free_image(w, f.image)
    delete(frames, w.allocator)
}

free_animation :: proc(anim: ^GIF_Data) {
    if anim == nil do return
    w := anim.window
    if anim.stream != nil do gif.close(anim.stream)
    for img in anim.ring do if img != nil do free_image(w, img)
    delete(anim.encoded, w.allocator)
    delete(anim.delays, w.allocator)
    runtime.mem_free(anim, w.allocator)
}

// Releases frames returned by load_image_frames, including the slice itself.
free_image_frames :: proc(w: ^Window, frames: []Image_Frame) {
    if w == nil || frames == nil do return
    for f in frames do free_image(w, f.image)
    delete(frames, w.allocator)
}

// Opens an animated image without decoding its pixels.
load_gif_dynamic :: proc(w: ^Window, encoded: []u8) -> (anim: ^GIF_Data, err: Image_Error) {
    if w == nil do return nil, .Decode_Failed
    if len(encoded) == 0 do return nil, .Empty_Input
    if len(encoded) > int(max(c.int)) do return nil, .Input_Too_Large
    if !_is_gif(encoded) do return nil, .Decode_Failed

    count := int(gif.scan(raw_data(encoded), c.int(len(encoded)), nil, 0))
    if count <= 0 do return nil, .Decode_Failed

    raw_delays := make([]c.int, count, w.allocator)
    defer delete(raw_delays, w.allocator)
    gif.scan(raw_data(encoded), c.int(len(encoded)), raw_data(raw_delays), c.int(count))

    // The decoder reads from this buffer lazily, so it must outlive the caller's.
    owned := make([]u8, len(encoded), w.allocator)
    copy(owned, encoded)

    x, y: c.int
    stream := gif.open(raw_data(owned), c.int(len(owned)), &x, &y)
    if stream == nil {
        delete(owned, w.allocator)
        return nil, .Decode_Failed
    }

    width, height := int(x), int(y)
    if width <= 0 || height <= 0 || width > max(int) / height / 4 {
        gif.close(stream)
        delete(owned, w.allocator)
        return nil, .Invalid_Dimensions
    }

    anim = new(GIF_Data, w.allocator)
    anim.encoded = owned
    anim.stream = stream
    anim.width = width
    anim.height = height
    anim.window = w
    anim.delays = make([]f32, count, w.allocator)
    for d, i in raw_delays {
        ms := d
        if ms <= 10 do ms = 100
        anim.delays[i] = f32(ms) / 1000
    }
    for i in 0 ..< GIF_ANIMATION_RING do anim.ring_at[i] = -1
    return anim, .None
}

gif_get_frame_count :: proc(anim: ^GIF_Data) -> int {
    return anim == nil ? 0 : len(anim.delays)
}

gif_get_delay :: proc(anim: ^GIF_Data, frame: int) -> f32 {
    if anim == nil || len(anim.delays) == 0 do return 0
    return anim.delays[frame %% len(anim.delays)]
}

// Returns the image for frame.
gif_get_image :: proc(anim: ^GIF_Data, frame: int) -> ^render.Image {
    if anim == nil || len(anim.delays) == 0 do return nil
    want := frame %% len(anim.delays)

    if slot := _ring_find(anim, want); slot >= 0 do return anim.ring[slot]
    if want < anim.decoded - GIF_ANIMATION_RING || want < anim.decoded - 1 {
        if !_gif_rewind(anim) do return nil
    }
    for anim.decoded <= want {
        if !_gif_decode_next(anim) do return nil
    }
    if slot := _ring_find(anim, want); slot >= 0 do return anim.ring[slot]
    return nil
}

// Decodes at most budget frames ahead of frame.
// Call once per tick to keep the lookahead warm without decoding a whole animation in one paint.
gif_prefetch :: proc(anim: ^GIF_Data, frame: int, budget := 1) {
    if anim == nil || len(anim.delays) == 0 do return
    if len(anim.delays) <= 1 do return
    want := frame %% len(anim.delays)

    for i in 0 ..< budget {
        next := want + 1 + i
        if next >= len(anim.delays) do return // wrapping would rewind; not worth a stall
        if _ring_find(anim, next) >= 0 do continue
        if next < anim.decoded do return
        for anim.decoded <= next {
            if !_gif_decode_next(anim) do return
        }
    }
}

@(private="file")
_ring_find :: proc(anim: ^GIF_Data, frame: int) -> int {
    for at, i in anim.ring_at {
        if at == frame && anim.ring[i] != nil do return i
    }
    return -1
}

@(private="file")
_gif_rewind :: proc(anim: ^GIF_Data) -> bool {
    gif.close(anim.stream)
    x, y: c.int
    anim.stream = gif.open(raw_data(anim.encoded), c.int(len(anim.encoded)), &x, &y)
    anim.decoded = 0
    for i in 0 ..< GIF_ANIMATION_RING do anim.ring_at[i] = -1
    return anim.stream != nil
}

// Pulls one frame from the stream into the oldest ring slot.
@(private="file")
_gif_decode_next :: proc(anim: ^GIF_Data) -> bool {
    if anim.stream == nil do return false
    index := anim.decoded
    if index >= len(anim.delays) do return false

    slot := index %% GIF_ANIMATION_RING
    frame_bytes := anim.width * anim.height * 4

    if anim.ring[slot] == nil {
        pixels, pix_err := make([]u8, frame_bytes, anim.window.allocator)
        if pix_err != nil do return false
        image := new(render.Image, anim.window.allocator)
        image^ = render.Image {
            data   = pixels,
            w      = u32(anim.width),
            h      = u32(anim.height),
            format = .RGBA8,
        }
        append(&anim.window.images, image)
        anim.ring[slot] = image
    }

    image := anim.ring[slot]
    // Overwriting the pixels invalidates the uploaded texture
    if image.texture != render.INVALID_TEXTURE {
        free_image_texture(anim.window, image)
    }

    ms := c.int(0)
    if gif.next(anim.stream, raw_data(image.data), c.size_t(frame_bytes), &ms) != 1 {
        anim.ring_at[slot] = -1
        return false
    }
    anim.ring_at[slot] = index
    anim.decoded = index + 1
    return true
}

@(private="package")
_is_gif :: proc(encoded: []u8) -> bool {
    return len(encoded) >= 6 &&
        encoded[0] == 'G' && encoded[1] == 'I' && encoded[2] == 'F' &&
        encoded[3] == '8' && (encoded[4] == '7' || encoded[4] == '9') && encoded[5] == 'a'
}
