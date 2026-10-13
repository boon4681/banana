package painter

import "src:core/common"
import "src:core/redraw"

// Field by field where a struct has padding, whose bytes are not defined.

@(private)
_hash_shadow :: proc(s: common.EffectShadow) {
    when redraw.CHECK {
        redraw.hash([4]f32{s.x, s.y, s.blur, s.spread})
        redraw.hash(s.color)
        redraw.hash(u8(s.inset))
    }
}

@(private)
_hash_gradient :: proc(g: common.Gradient) {
    when redraw.CHECK {
        redraw.hash(u8(g.kind))
        redraw.hash(g.angle)
        redraw.hash_slice(g.stops)
    }
}

@(private)
_hash_transform :: proc(t: common.Transform) {
    when redraw.CHECK {
        redraw.hash(t.translate)
        redraw.hash(t.rotate)
        redraw.hash(t.scale)
        redraw.hash(t.origin)
        redraw.hash(t.linear)
        redraw.hash(u8(t.has_linear))
    }
}

@(private)
_hash_filter :: proc(f: common.EffectFilter) {
    when redraw.CHECK {
        redraw.hash(f.blur)
        redraw.hash(f.color)
        redraw.hash(f.offset)
        for s in f.shadows do _hash_shadow(s)
    }
}

@(private)
_hash_msdf :: proc(quads: []MSDF_Quad) {
    when redraw.CHECK {
        for q in quads {
            redraw.hash(q.rect)
            redraw.hash(q.atlas)
            redraw.hash(q.tint)
            redraw.hash(u8(q.has_tint))
        }
    }
}
