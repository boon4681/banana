package svg

import "base:runtime"
import "core:c"
import "src:core/common"
import "src:core/painter"
import "src:core/render"
import "src:lunasvg"

// Upper bound on either raster dimension, well inside the GL_MAX_TEXTURE_SIZE of any target hardware.
MAX_RASTER_EDGE :: 4096

RASTER_SHRINK_RATIO :: 0.5
RASTER_GROW_RATIO :: 1.5

// New rasters snap to a multiple of this so a slow drag re-rasters at repeatable sizes instead of at wherever the band happened to break.
RASTER_STEP :: 64

// Below this the step would dominate the actual size.
RASTER_STEP_MIN :: 96

// Retains one rasterized image per SVG document.
// The raster is regenerated only when its pixel dimensions change.
Cache :: struct {
	image:     render.Image,
	px_w:      int,
	px_h:      int,
	valid:     bool,
	allocator: runtime.Allocator,
}

invalidate :: proc(cache: ^Cache) {
	if cache == nil do return
	cache.valid = false
}

cache_destroy :: proc(cache: ^Cache) {
	if cache == nil do return
	_release(cache)
	delete(cache.image.data, cache.allocator)
	cache^ = {}
}

draw_cached :: proc(
	doc: ^Document,
	p: painter.Painter,
	cache: ^Cache,
	dst: common.Rect,
	preserve_aspect := true,
	tint := common.COLOR_WHITE,
) {
	if doc == nil || doc.raw == nil || cache == nil do return
	if doc.view_box.w <= 0 || doc.view_box.h <= 0 || dst.w <= 0 || dst.h <= 0 do return

	fit := dst
	if preserve_aspect {
		s := min(dst.w / doc.view_box.w, dst.h / doc.view_box.h)
		fit.w = doc.view_box.w * s
		fit.h = doc.view_box.h * s
		fit.x += (dst.w - fit.w) * 0.5
		fit.y += (dst.h - fit.h) * 0.5
	}

	scale := painter.pixel_scale(p)
	want_w := max(fit.w * scale.x, 1)
	want_h := max(fit.h * scale.y, 1)

	if px_w, px_h, need := _plan_raster(cache, want_w, want_h); need {
		if !_rasterize(doc, cache, px_w, px_h) do return
	}

	painter.image(p, &cache.image, fit, tint)
}

@(private)
_plan_raster :: proc(cache: ^Cache, want_w, want_h: f32) -> (px_w, px_h: int, need: bool) {
	want_major := max(want_w, want_h)
	have_major := f32(max(cache.px_w, cache.px_h))

	if cache.valid &&
	   have_major > 0 &&
	   want_major >= have_major * RASTER_SHRINK_RATIO &&
	   want_major <= have_major * RASTER_GROW_RATIO {
		return cache.px_w, cache.px_h, false
	}

	if want_w >= want_h {
		px_w = _quantize(int(want_w + 0.5))
		px_h = max(int(want_h * f32(px_w) / want_w + 0.5), 1)
	} else {
		px_h = _quantize(int(want_h + 0.5))
		px_w = max(int(want_w * f32(px_h) / want_h + 0.5), 1)
	}

	if px_w > MAX_RASTER_EDGE || px_h > MAX_RASTER_EDGE {
		if px_w >= px_h {
			px_h = max(px_h * MAX_RASTER_EDGE / px_w, 1)
			px_w = MAX_RASTER_EDGE
		} else {
			px_w = max(px_w * MAX_RASTER_EDGE / px_h, 1)
			px_h = MAX_RASTER_EDGE
		}
	}

	if cache.valid && cache.px_w == px_w && cache.px_h == px_h {
		return px_w, px_h, false
	}
	return px_w, px_h, true
}

@(private = "file")
_quantize :: proc(px: int) -> int {
	if px <= RASTER_STEP_MIN do return px
	return ((px + RASTER_STEP - 1) / RASTER_STEP) * RASTER_STEP
}

@(private = "file")
_rasterize :: proc(doc: ^Document, cache: ^Cache, px_w, px_h: int) -> bool {
	if cache.allocator.procedure == nil do cache.allocator = context.allocator
	required := px_w * px_h * 4
	if len(cache.image.data) < required {
		delete(cache.image.data, cache.allocator)
		data, err := make([]u8, required, cache.allocator)
		if err != nil {
			cache.image.data = nil
			cache.valid = false
			return false
		}
		cache.image.data = data
	}

	_release(cache)

	ok := lunasvg.render(
		doc.raw,
		raw_data(cache.image.data),
		c.int(px_w),
		c.int(px_h),
		c.int(px_w * 4),
		f32(px_w) / doc.view_box.w,
		f32(px_h) / doc.view_box.h,
	)
	if !ok {
		cache.valid = false
		return false
	}

	cache.image.w = u32(px_w)
	cache.image.h = u32(px_h)
	cache.image.format = .RGBA8
	cache.px_w = px_w
	cache.px_h = px_h
	cache.valid = true
	return true
}

@(private = "file")
_release :: proc(cache: ^Cache) {
	if cache.image.texture == render.INVALID_TEXTURE do return
	render.RENDERER.unload_image(&cache.image)
}
