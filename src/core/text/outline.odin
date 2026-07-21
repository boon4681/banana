package text

import "core:c"
import "core:math"
import stbtt "vendor:stb/truetype"

Glyph :: struct {
	curve_base:  u32,
	curve_count: u32,
	contour_base:  u32,
	contour_count: u32,
	min, max:    [2]f32,
}

@(private = "file") _curves: [dynamic][2]f32
@(private = "file") _contour_ends: [dynamic]u32
@(private = "file") _version: u64

curve_data :: proc() -> ([][2]f32, u64) {
	return _curves[:], _version
}

glyph_contours :: proc(g: Glyph) -> []u32 {
	return _contour_ends[g.contour_base:][:g.contour_count]
}

glyph :: proc(f: ^Face, gid: u32) -> Glyph {
	if g, ok := f.glyphs[gid]; ok do return g

	verts: [^]stbtt.vertex
	nv := stbtt.GetGlyphShape(&f.info, c.int(gid), &verts)

	o := _Outline {
		min = {math.F32_MAX, math.F32_MAX},
		max = {-math.F32_MAX, -math.F32_MAX},
	}
	base := u32(len(_curves) / 3)
	contour_base := u32(len(_contour_ends))
	s := f.inv_upem
	for v in verts[:nv] {
		p := [2]f32{f32(v.x), f32(v.y)} * s
		switch stbtt.vmove(v.type) {
		case .vmove:
			_finish_contour(&o)
			o.cur = p
			o.start = p
			o.open = true
		case .vline:
			if p != o.cur do _emit(&o, o.cur, (o.cur + p) * 0.5, p)
		case .vcurve:
			q := [2]f32{f32(v.cx), f32(v.cy)} * s
			if p != o.cur || q != o.cur do _emit(&o, o.cur, q, p)
		case .vcubic:
			c1 := [2]f32{f32(v.cx), f32(v.cy)} * s
			c2 := [2]f32{f32(v.cx1), f32(v.cy1)} * s
			_cubic(&o, o.cur, c1, c2, p, 0)
		case .none:
		}
	}
	_finish_contour(&o)
	if verts != nil do stbtt.FreeShape(&f.info, verts)

	g := Glyph{
		curve_base = base,
		curve_count = o.count,
		contour_base = contour_base,
		contour_count = u32(len(_contour_ends)) - contour_base,
		min = o.min,
		max = o.max,
	}
	if o.count > 0 do _version += 1
	f.glyphs[gid] = g
	return g
}

@(private = "file")
_Outline :: struct {
	cur:      [2]f32,
	start:    [2]f32,
	open:     bool,
	min, max: [2]f32,
	count:    u32,
}

@(private = "file")
_emit :: proc(o: ^_Outline, p0, p1, p2: [2]f32) {
	append(&_curves, p0, p1, p2)
	o.count += 1
	for p in ([3][2]f32{p0, p1, p2}) {
		o.min.x = min(o.min.x, p.x); o.min.y = min(o.min.y, p.y)
		o.max.x = max(o.max.x, p.x); o.max.y = max(o.max.y, p.y)
	}
	o.cur = p2
}

@(private = "file")
_finish_contour :: proc(o: ^_Outline) {
	if !o.open do return
	if o.cur != o.start do _emit(o, o.cur, (o.cur + o.start) * 0.5, o.start)
	append(&_contour_ends, o.count)
	o.open = false
}

@(private = "file")
_cubic :: proc(o: ^_Outline, p0, c1, c2, p3: [2]f32, depth: int) {
	d := p3 - 3 * c2 + 3 * c1 - p0
	err := math.sqrt(d.x * d.x + d.y * d.y) * (math.SQRT_THREE / 36)
	if depth >= 4 || err <= 0.002 {
		q := (3 * (c1 + c2) - p0 - p3) * 0.25
		_emit(o, p0, q, p3)
		return
	}
	ab := (p0 + c1) * 0.5
	bc := (c1 + c2) * 0.5
	cd := (c2 + p3) * 0.5
	abc := (ab + bc) * 0.5
	bcd := (bc + cd) * 0.5
	m := (abc + bcd) * 0.5
	_cubic(o, p0, ab, abc, m, depth + 1)
	_cubic(o, m, bcd, cd, p3, depth + 1)
}
