package painter

import "base:runtime"
import "src:core/common"
import "src:core/render"
import "core:math"
import "core:math/linalg"


@(private="file")
Clip_Entry :: struct {
	kind:         enum { Scissor, Stencil },
	prev_scissor: Maybe(common.Rect),
}

@(private="file")
Vector_State :: struct {
	verts:      [dynamic]render.Vertex,
	indices:    [dynamic]u32,
	texture:    render.Texture,
	scissor:    Maybe(common.Rect),
	clips:      [dynamic]Clip_Entry,
	transforms: [dynamic]common.Mat3x3,
	msdf_atlas: render.Texture,
	msdf_atlas_version: u64,
}

@(private="file")
_vs :: proc(p: Painter) -> ^Vector_State {
	return cast(^Vector_State)(p.state)
}

@(private="file")
_state_size :: proc() -> int { return size_of(Vector_State) }

@(private="file")
_init :: proc(p: Painter, allocator: runtime.Allocator) {
	v := _vs(p)
	v^ = {}
	v.verts = make([dynamic]render.Vertex, allocator)
	v.indices = make([dynamic]u32, allocator)
	v.clips = make([dynamic]Clip_Entry, allocator)
	v.transforms = make([dynamic]common.Mat3x3, allocator)
	append(&v.transforms, common.Mat3X3_IDENTITY)
}

@(private="file")
_shutdown :: proc(p: Painter) {
	v := _vs(p)
	if v == nil do return
	if v.msdf_atlas != render.INVALID_TEXTURE do render.RENDERER.destroy_texture(v.msdf_atlas)
	delete(v.verts)
	delete(v.indices)
	delete(v.clips)
	delete(v.transforms)
}

@(private="file")
_begin_frame :: proc(p: Painter, color: common.Color) {
	v := _vs(p)
	render.RENDERER.clear(render.INVALID_RENDER_TARGET, color)
	render.RENDERER.stencil_clear()
	clear(&v.verts)
	clear(&v.indices)
	clear(&v.clips)
	resize(&v.transforms, 1)
	v.transforms[0] = common.Mat3X3_IDENTITY
	v.texture = render.INVALID_TEXTURE
	v.scissor = nil
}

@(private="file")
_end_frame :: proc(p: Painter) {
	_flush(_vs(p))
	render.RENDERER.present()
}

@(private="file")
_rect :: proc(p: Painter, r: common.Rect, color: common.Color, radius: f32 = 0) {
	v := _vs(p)
	_set_texture(v, render.INVALID_TEXTURE)
	rad := min(radius, r.w * 0.5, r.h * 0.5)
	if rad <= 0 {
		_quad(v, {r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}, color)
		return
	}
	pts := _perimeter(r, rad, _segs(rad))
	base := u32(len(v.verts))
	_vert(v, {r.x + r.w * 0.5, r.y + r.h * 0.5}, {0, 0}, color)
	for pt in pts do _vert(v, pt, {0, 0}, color)
	n := u32(len(pts))
	for i in 0 ..< n {
		append(&v.indices, base, base + 1 + i, base + 1 + (i + 1) % n)
	}
}

@(private="file")
_border :: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: f32 = 0) {
	if width <= 0 do return
	v := _vs(p)
	_set_texture(v, render.INVALID_TEXTURE)
	w := min(width, r.w * 0.5, r.h * 0.5)
	rad := min(radius, r.w * 0.5, r.h * 0.5)
	segs := _segs(max(rad, 1))
	outer := _perimeter(r, rad, segs)
	inner := _perimeter({r.x + w, r.y + w, r.w - 2 * w, r.h - 2 * w}, max(rad - w, 0), segs)
	base := u32(len(v.verts))
	for pt, i in outer {
		_vert(v, pt, {0, 0}, color)
		_vert(v, inner[i], {0, 0}, color)
	}
	n := u32(len(outer))
	for i in 0 ..< n {
		j := (i + 1) % n
		o0 := base + 2 * i
		o1 := base + 2 * j
		append(&v.indices, o0, o0 + 1, o1, o0 + 1, o1 + 1, o1)
	}
}

@(private="file")
_image :: proc(p: Painter, image: ^render.Image, r: common.Rect, tint := common.COLOR_WHITE) {
	if image == nil do return
	texture := render.RENDERER.upload_image(image)
	if texture == render.INVALID_TEXTURE do return
	v := _vs(p)
	_set_texture(v, texture)
	base := u32(len(v.verts))
	_vert(v, {r.x, r.y}, {0, 0}, tint)
	_vert(v, {r.x + r.w, r.y}, {1, 0}, tint)
	_vert(v, {r.x + r.w, r.y + r.h}, {1, 1}, tint)
	_vert(v, {r.x, r.y + r.h}, {0, 1}, tint)
	append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

@(private="file")
_line :: proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32) {
	d := b - a
	length := linalg.length(d)
	if length == 0 || width <= 0 do return
	v := _vs(p)
	_set_texture(v, render.INVALID_TEXTURE)
	n := swizzle(d, 1, 0) * [2]f32{-1, 1} / length * (width * 0.5)
	_quad(v, a + n, b + n, b - n, a - n, color)
}

@(private="file")
_triangles :: proc(p: Painter, points: [][2]f32, indices: []u32, color: common.Color) {
	if len(points) == 0 || len(indices) < 3 do return
	v := _vs(p)
	_set_texture(v, render.INVALID_TEXTURE)
	base := u32(len(v.verts))
	for point in points do _vert(v, point, {0, 0}, color)
	for index in indices {
		if int(index) < len(points) do append(&v.indices, base + index)
	}
}

@(private="file")
_mesh_cached :: proc(p:Painter,cache:^Mesh_Cache,source_version:u64,vertices:[]render.Vertex,indices:[]u32) {
	if cache==nil do return
	v:=_vs(p);_flush(v)
	m:=_top(v);rebuild:=!cache.valid||cache.source_version!=source_version
	geometry_version:=cache.mesh.version
	if rebuild {
		if len(vertices)==0||len(indices)==0 do return
		cache.source_version=source_version;cache.valid=true;geometry_version+=1
	}
	render.RENDERER.draw_mesh(render.INVALID_RENDER_TARGET,&cache.mesh,vertices,indices,geometry_version,m,render.INVALID_TEXTURE,v.scissor,.Alpha)
}

@(private="file")
_glyphs :: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
	if len(quads) == 0 do return
	v := _vs(p)
	// Different pipeline: emit pending geometry first so paint order holds.
	_flush(v)
	verts, indices := _glyph_geometry(quads, color)
	render.RENDERER.draw_glyphs(render.INVALID_RENDER_TARGET, verts, indices, curves, version, _top(v), v.scissor)
}

@(private="file")
_glyph_geometry :: proc(quads: []Glyph_Quad, color: common.Color) -> ([]render.Glyph_Vertex, []u32) {
	verts := make([dynamic]render.Glyph_Vertex, 0, len(quads) * 4, context.temp_allocator)
	indices := make([dynamic]u32, 0, len(quads) * 6, context.temp_allocator)
	for q in quads {
		base := u32(len(verts))
		corners := [4]struct {
			pos: [2]f32,
			uv:  [2]f32,
		} {
			{{q.rect.x, q.rect.y}, q.uv0},
			{{q.rect.x + q.rect.w, q.rect.y}, {q.uv1.x, q.uv0.y}},
			{{q.rect.x + q.rect.w, q.rect.y + q.rect.h}, q.uv1},
			{{q.rect.x, q.rect.y + q.rect.h}, {q.uv0.x, q.uv1.y}},
		}
		for c in corners {
			append(&verts, render.Glyph_Vertex{
				pos         = c.pos,
				uv          = c.uv,
				color       = color,
				curve_base  = q.curve_base,
				curve_count = q.curve_count,
			})
		}
		append(&indices, base, base + 1, base + 2, base, base + 2, base + 3)
	}
	return verts[:], indices[:]
}

@(private="file")
_glyphs_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
	if cache == nil || len(quads) == 0 do return
	v := _vs(p)
	_flush(v)

	m := _top(v)
	rebuild := !cache.valid || cache.source_version != source_version || cache.color != color
	vertices: []render.Glyph_Vertex
	indices: []u32
	geometry_version := cache.mesh.version
	if rebuild {
		vertices, indices = _glyph_geometry(quads, color)
		cache.source_version = source_version
		cache.color = color
		cache.valid = true
		geometry_version += 1
	}
	render.RENDERER.draw_glyph_mesh(render.INVALID_RENDER_TARGET, &cache.mesh, vertices, indices, geometry_version, m, curves, version, v.scissor)
}

@(private="file")
_msdf_geometry :: proc(quads: []MSDF_Quad, color: common.Color) -> ([]render.Glyph_Vertex, []u32) {
	verts := make([dynamic]render.Glyph_Vertex, 0, len(quads) * 4, context.temp_allocator)
	indices := make([dynamic]u32, 0, len(quads) * 6, context.temp_allocator)
	for q in quads {
		base := u32(len(verts))
		corners := [4]struct { pos, uv: [2]f32 } {
			{{q.rect.x, q.rect.y}, {q.uv[0], q.uv[3]}},
			{{q.rect.x + q.rect.w, q.rect.y}, {q.uv[2], q.uv[3]}},
			{{q.rect.x + q.rect.w, q.rect.y + q.rect.h}, {q.uv[2], q.uv[1]}},
			{{q.rect.x, q.rect.y + q.rect.h}, {q.uv[0], q.uv[1]}},
		}
		for c in corners {
			append(&verts, render.Glyph_Vertex{pos = c.pos, uv = c.uv, color = color})
		}
		append(&indices, base, base + 1, base + 2, base, base + 2, base + 3)
	}
	return verts[:], indices[:]
}

@(private="file")
_msdf_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, atlas_pixels: []u8, atlas_w, atlas_h: int, atlas_version: u64, pixel_range: f32, quads: []MSDF_Quad, color: common.Color) {
	if cache == nil || len(quads) == 0 || len(atlas_pixels) == 0 do return
	v := _vs(p)
	_flush(v)
	if v.msdf_atlas == render.INVALID_TEXTURE {
		v.msdf_atlas = render.RENDERER.create_texture(atlas_pixels, atlas_w, atlas_h, .RGBA8)
		render.RENDERER.set_texture_filter(v.msdf_atlas, .Linear, .Linear, .Linear)
		v.msdf_atlas_version = atlas_version
	} else if v.msdf_atlas_version != atlas_version {
		if render.RENDERER.update_texture(v.msdf_atlas, atlas_pixels, {0, 0, f32(atlas_w), f32(atlas_h)}) {
			v.msdf_atlas_version = atlas_version
		}
	}

	m := _top(v)
	rebuild := !cache.valid || cache.source_version != source_version || cache.color != color
	vertices: []render.Glyph_Vertex
	indices: []u32
	geometry_version := cache.mesh.version
	if rebuild {
		vertices, indices = _msdf_geometry(quads, color)
		cache.source_version = source_version
		cache.color = color
		cache.valid = true
		geometry_version += 1
	}
	render.RENDERER.draw_msdf_mesh(render.INVALID_RENDER_TARGET, &cache.mesh, vertices, indices, geometry_version, m, v.msdf_atlas, pixel_range, v.scissor)
}

@(private="file")
_push_clip :: proc(p: Painter, r: common.Rect, mode: ClipMode) {
	v := _vs(p)
	_flush(v)
	m := _top(v)
	// Scissor is axis-aligned only; rotated/skewed transforms fall back to stencil.
	if mode == .Scissor && m[1, 0] == 0 && m[0, 1] == 0 {
		sr := _xform_rect(v, r)
		if cur, ok := v.scissor.?; ok do sr = _intersect(cur, sr)
		append(&v.clips, Clip_Entry{kind = .Scissor, prev_scissor = v.scissor})
		v.scissor = sr
	} else {
		render.RENDERER.stencil_push_clip()
		verts := [4]render.Vertex{
			{pos = _pt(v, {r.x, r.y})},
			{pos = _pt(v, {r.x + r.w, r.y})},
			{pos = _pt(v, {r.x + r.w, r.y + r.h})},
			{pos = _pt(v, {r.x, r.y + r.h})},
		}
		indices := [6]u32{0, 1, 2, 0, 2, 3}
		render.RENDERER.draw(render.INVALID_RENDER_TARGET, verts[:], indices[:], render.INVALID_TEXTURE, nil, .Opaque)
		render.RENDERER.stencil_use_clip()
		append(&v.clips, Clip_Entry{kind = .Stencil, prev_scissor = v.scissor})
	}
}

@(private="file")
_pop_clip :: proc(p: Painter) {
	v := _vs(p)
	if len(v.clips) == 0 do return
	_flush(v)
	e := pop(&v.clips)
	switch e.kind {
	case .Scissor: v.scissor = e.prev_scissor
	case .Stencil: render.RENDERER.stencil_pop_clip()
	}
}

@(private="file")
_pixel_scale :: proc(p: Painter) -> [2]f32 {
	m := _top(_vs(p))
	return {
		linalg.length([2]f32{m[0, 0], m[1, 0]}),
		linalg.length([2]f32{m[0, 1], m[1, 1]}),
	}
}

@(private="file")
_push_transform :: proc(p: Painter, t: common.Transform, at: [2]f32) {
	v := _vs(p)
	origin := at + t.origin
	cosr := math.cos(t.rotate)
	sinr := math.sin(t.rotate)
	lin := matrix[2, 2]f32{
		cosr * t.scale.x, -sinr * t.scale.y,
		sinr * t.scale.x, cosr * t.scale.y,
	}
	tr := origin + t.translate - lin * origin
	m := common.Mat3x3{
		lin[0, 0], lin[0, 1], tr.x,
		lin[1, 0], lin[1, 1], tr.y,
		0, 0, 1,
	}
	append(&v.transforms, _top(v) * m)
}

@(private="file")
_pop_transform :: proc(p: Painter) {
	v := _vs(p)
	if len(v.transforms) > 1 do pop(&v.transforms)
}

@(private="file")
_flush :: proc(v: ^Vector_State) {
	if len(v.indices) > 0 {
		render.RENDERER.draw(render.INVALID_RENDER_TARGET, v.verts[:], v.indices[:], v.texture, v.scissor, .Alpha)
	}
	clear(&v.verts)
	clear(&v.indices)
}

@(private="file")
_set_texture :: proc(v: ^Vector_State, t: render.Texture) {
	if v.texture != t {
		_flush(v)
		v.texture = t
	}
}

@(private="file")
_top :: proc(v: ^Vector_State) -> common.Mat3x3 {
	return v.transforms[len(v.transforms) - 1]
}

@(private="file")
_pt :: proc(v: ^Vector_State, p: [2]f32) -> [2]f32 {
	return swizzle(_top(v) * [3]f32{p.x, p.y, 1}, 0, 1)
}

@(private="file")
_vert :: proc(v: ^Vector_State, p: [2]f32, uv: [2]f32, color: common.Color) {
	append(&v.verts, render.Vertex{pos = _pt(v, p), uv = uv, color = color})
}

@(private="file")
_quad :: proc(v: ^Vector_State, p0, p1, p2, p3: [2]f32, color: common.Color) {
	base := u32(len(v.verts))
	_vert(v, p0, {0, 0}, color)
	_vert(v, p1, {0, 0}, color)
	_vert(v, p2, {0, 0}, color)
	_vert(v, p3, {0, 0}, color)
	append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

@(private="file")
_segs :: proc(radius: f32) -> int {
	return clamp(int(radius * 0.5), 3, 24)
}

@(private="file")
_perimeter :: proc(r: common.Rect, radius: f32, segs: int) -> [][2]f32 {
	pts := make([dynamic][2]f32, 0, (segs + 1) * 4, context.temp_allocator)
	corners := [4]struct {
		center: [2]f32,
		start:  f32,
	} {
		{{r.x + radius, r.y + radius}, math.PI},
		{{r.x + r.w - radius, r.y + radius}, math.PI * 1.5},
		{{r.x + r.w - radius, r.y + r.h - radius}, 0},
		{{r.x + radius, r.y + r.h - radius}, math.PI * 0.5},
	}
	for corner in corners {
		for i in 0 ..= segs {
			ang := corner.start + (f32(i) / f32(segs)) * math.PI * 0.5
			append(&pts, corner.center + [2]f32{math.cos(ang), math.sin(ang)} * radius)
		}
	}
	return pts[:]
}

@(private="file")
_xform_rect :: proc(v: ^Vector_State, r: common.Rect) -> common.Rect {
	p0 := _pt(v, {r.x, r.y})
	p1 := _pt(v, {r.x + r.w, r.y + r.h})
	lo := linalg.min(p0, p1)
	hi := linalg.max(p0, p1)
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}

@(private="file")
_intersect :: proc(a, b: common.Rect) -> common.Rect {
	lo := linalg.max([2]f32{a.x, a.y}, [2]f32{b.x, b.y})
	hi := linalg.min([2]f32{a.x + a.w, a.y + a.h}, [2]f32{b.x + b.w, b.y + b.h})
	size := linalg.max(hi - lo, [2]f32{0, 0})
	return {lo.x, lo.y, size.x, size.y}
}

PAINTER_VECTOR :: Painter_Interface {
	state_size     = _state_size,
	init           = _init,
	shutdown       = _shutdown,
	begin_frame    = _begin_frame,
	end_frame      = _end_frame,
	rect           = _rect,
	border         = _border,
	image          = _image,
	line           = _line,
	triangles      = _triangles,
	mesh_cached    = _mesh_cached,
	glyphs         = _glyphs,
	glyphs_cached  = _glyphs_cached,
	msdf_cached    = _msdf_cached,
	pixel_scale    = _pixel_scale,
	push_clip      = _push_clip,
	pop_clip       = _pop_clip,
	push_transform = _push_transform,
	pop_transform  = _pop_transform,
}
