package node

import "src:core/common"
import "src:core/redraw"

@(private="file")
Box :: redraw.Box

@(private="file")
FAR :: f32(1 << 20)

@(private="file")
NOTHING :: Box{FAR, FAR, -FAR, -FAR}

@(private="file")
EVERYWHERE :: Box{-FAR, -FAR, FAR, FAR}

// Antialiasing and glyph overhang reach a little past a rect.
@(private="file")
PAD :: f32(2)

@(private="file")
_join :: proc(a, b: Box) -> Box {
    if b[2] <= b[0] || b[3] <= b[1] do return a
    return {min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])}
}

@(private="file")
_meet :: proc(a, b: Box) -> Box {
    return {max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])}
}

@(private="file")
_grow :: proc(b: Box, by: f32) -> Box {
    if by <= 0 || b[2] <= b[0] || b[3] <= b[1] do return b
    return {b[0] - by, b[1] - by, b[2] + by, b[3] + by}
}

// The box around a rect once `m` has moved it.
@(private="file")
_placed :: proc(m: common.Mat3x3, r: common.Rect) -> Box {
    if r.w <= 0 || r.h <= 0 do return NOTHING
    out := NOTHING
    for corner in ([4][2]f32{{r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}}) {
        p := m * [3]f32{clamp(corner.x, -FAR, FAR), clamp(corner.y, -FAR, FAR), 1}
        out = {min(out[0], p.x), min(out[1], p.y), max(out[2], p.x), max(out[3], p.y)}
    }
    return out
}

// How far `m` stretches a length, for reaches given in the node own units.
@(private="file")
_stretch :: proc(m: common.Mat3x3) -> f32 {
    return max(abs(m[0, 0]) + abs(m[0, 1]), abs(m[1, 0]) + abs(m[1, 1]))
}

@(private="file")
_local :: proc(n: ^BaseNode, at: common.Rect) -> common.Mat3x3 {
    transform := Resolve_Transform(n)
    if transform == common.IDENTITY_TRANSFORM do return common.Mat3X3_IDENTITY
    return common.transform_at_matrix(transform, {at.x, at.y})
}

@(private="file")
_filter_reach :: proc(n: ^BaseNode) -> (reach: f32) {
    filter, on := Resolve_Filter(n)
    if !on do return 0
    reach = filter.blur * 3
    for shadow in filter.shadows do reach = max(reach, max(abs(shadow.x), abs(shadow.y)) + shadow.blur * 3)
    return
}

Clip_Rect :: proc(n: ^BaseNode) -> common.Rect {
    if cr, ok := n.clip_rect.?; ok do return {n.rect.x + cr.x, n.rect.y + cr.y, cr.w, cr.h}
    border := n->get_rect(.Border)
    pad := n->get_rect(.Padding)
    r := common.Rect{n.rect.x + (pad.x - border.x), n.rect.y + (pad.y - border.y), pad.w, pad.h}
    if !n.clip_x {
        r.x = -FAR
        r.w = 2 * FAR
    }
    if !n.clip_y {
        r.y = -FAR
        r.h = 2 * FAR
    }
    return r
}

@(private)
_node_paint_box :: proc(self: ^BaseNode) -> common.Rect {
    r := self.rect
    if self.structural || (r.w <= 0 && r.h <= 0) do return {}
    reach := PAD
    if self._internal_style != nil {
        d := (cast(^Style)self._internal_style).decoration
        for s in d.shadows {
            if !s.inset do reach = max(reach, PAD + max(abs(s.x), abs(s.y)) + max(s.spread, 0) + s.blur * 3)
        }
        if d.outline_width > 0 do reach = max(reach, PAD + max(d.outline_offset, 0) + d.outline_width)
    }
    return {r.x - reach, r.y - reach, r.w + 2 * reach, r.h + 2 * reach}
}

@(private="file")
_cover :: proc(n: ^BaseNode, above: common.Mat3x3, clip: Box, out: ^Box) {
    // A fragment has no box of its own and is laid out as hidden; its members are not.
    if n.freed || (!n.structural && is_hidden(n)) do return
    m := above * _local(n, n.rect)
    drawn := _placed(m, n->paint_box())
    within := EVERYWHERE
    if n.clip_mode != .None do within = _placed(m, Clip_Rect(n))
    for c in n.children {
        // A fixed node is placed from the window: the boxes around it do not cut it off.
        if Resolve_Fixed(c) {
            _cover(c, m, EVERYWHERE, out)
        } else {
            _cover(c, m, within, &drawn)
        }
    }
    drawn = _grow(drawn, _filter_reach(n) * _stretch(m))
    out^ = _join(out^, _meet(drawn, clip))
}

@(private="file")
_surroundings :: proc(n: ^BaseNode) -> (above: common.Mat3x3, clip: Box, bleed: f32) {
    path := make([dynamic]^BaseNode, context.temp_allocator)
    for a := n.parent; a != nil; a = a.parent do append(&path, a)
    above = common.Mat3X3_IDENTITY
    clip = EVERYWHERE
    #reverse for a in path {
        above = above * _local(a, a.rect)
        if Resolve_Fixed(a) do clip = EVERYWHERE
        if a.clip_mode != .None do clip = _meet(clip, _placed(above, Clip_Rect(a)))
        bleed += _filter_reach(a) * _stretch(above)
    }
    if Resolve_Fixed(n) do clip = EVERYWHERE
    return
}

@(private)
_node_damage :: proc(self: ^BaseNode, loc := #caller_location) {
    if redraw.painting() do return
    if redraw.whole() {
        redraw.mark(loc)
        return
    }
    epoch := redraw.epoch()
    for a := self; a != nil; a = a.parent {
        if a.damage_epoch == epoch do return
        for o := a.owner; o != nil; o = o.owner {
            if o.damage_epoch == epoch do return
        }
    }
    self.damage_epoch = epoch
    above, clip, bleed := _surroundings(self)
    drawn := NOTHING
    _cover(self, above, clip, &drawn)
    redraw.damage(_grow(drawn, bleed), loc)
    redraw.wait_for_layout()
}

@(private)
_node_settle_damage :: proc(self: ^BaseNode) {
    _settle(self, common.Mat3X3_IDENTITY, EVERYWHERE, 0, false, false, redraw.whole(), redraw.epoch())
}

@(private="file")
_settle :: proc(n: ^BaseNode, above: common.Mat3x3, clip: Box, bleed: f32, recorded, covered, whole: bool, epoch: u64) {
    if n.freed do return
    moved := n.rect != n.shown
    damaged := n.damage_epoch == epoch
    covered := covered
    m := above * _local(n, n.rect)
    if !whole && (n.structural || !is_hidden(n)) {
        if moved && !recorded && !damaged {
            now := n.rect
            n.rect = n.shown
            before := _placed(above * _local(n, n.rect), n->paint_box())
            n.rect = now
            redraw.damage(_grow(_meet(before, clip), bleed))
        }
        if (moved || damaged) && !covered {
            drawn := NOTHING
            _cover(n, above, clip, &drawn)
            redraw.damage(_grow(drawn, bleed))
            covered = true
        }
    }
    n.shown = n.rect
    if n.structural do return
    within := clip
    if n.clip_mode != .None do within = _meet(clip, _placed(m, Clip_Rect(n)))
    under := bleed + _filter_reach(n) * _stretch(m)
    for c in n._internal_children {
        _settle(c, m, EVERYWHERE if Resolve_Fixed(c) else within, under, recorded || damaged, covered, whole, epoch)
    }
}
