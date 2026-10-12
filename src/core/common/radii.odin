package common

// Radii for css styling 
Radii :: [4][2]f32

radii_fit :: proc(r: Radii, w, h: f32) -> Radii {
    out: Radii
    for corner, i in r {
        if corner.x > 0 && corner.y > 0 do out[i] = corner
    }
    scale: f32 = 1
    sides := [4][2]f32{
        {out[0].x + out[1].x, w}, {out[1].y + out[2].y, h},
        {out[2].x + out[3].x, w}, {out[3].y + out[0].y, h},
    }
    for side in sides {
        if side[0] > side[1] && side[0] > 0 do scale = min(scale, max(side[1], 0) / side[0])
    }
    return out * scale
}

radii_resolve :: proc(r, percent: Radii, w, h: f32) -> Radii {
    out := r
    for &corner, i in out do corner += percent[i] * [2]f32{w, h} / 100
    return out
}

radii_circular :: proc(r: Radii) -> bool {
    for corner in r {
        if corner.x != corner.y do return false
    }
    return true
}

radii_max :: proc(r: Radii) -> (largest: f32) {
    for corner in r do largest = max(largest, corner.x, corner.y)
    return
}

radii_min :: proc(r: Radii) -> f32 {
    smallest := min(r[0].x, r[0].y)
    for corner in r do smallest = min(smallest, corner.x, corner.y)
    return smallest
}

rounded_rect_contains :: proc(r: Rect, radii: Radii, x, y: f32) -> bool {
    if x < r.x || y < r.y || x >= r.x + r.w || y >= r.y + r.h do return false
    if radii == 0 do return true
    left, top := x < r.x + r.w * 0.5, y < r.y + r.h * 0.5
    radius := radii[0] if left && top else radii[1] if top else radii[3] if left else radii[2]
    if radius.x <= 0 || radius.y <= 0 do return true
    cx := r.x + radius.x if left else r.x + r.w - radius.x
    cy := r.y + radius.y if top else r.y + r.h - radius.y
    dx := (cx - x if left else x - cx) / radius.x
    dy := (cy - y if top else y - cy) / radius.y
    return dx <= 0 || dy <= 0 || dx * dx + dy * dy <= 1
}

radii_inset :: proc(r: Radii, d: f32) -> Radii {
    out: Radii
    for corner, i in r {
        if corner.x > d && corner.y > d do out[i] = corner - d
    }
    return out
}

// top, right, bottom, left.
radii_inset_sides :: proc(r: Radii, d: [4]f32) -> Radii {
    by := Radii{{d[3], d[0]}, {d[1], d[0]}, {d[1], d[2]}, {d[3], d[2]}}
    out: Radii
    for corner, i in r {
        if corner.x > by[i].x && corner.y > by[i].y do out[i] = corner - by[i]
    }
    return out
}

radii_grow :: proc(r: Radii, d: f32) -> Radii {
    out: Radii
    for corner, i in r {
        if corner.x > 0 && corner.y > 0 do out[i] = {max(corner.x + d, 0), max(corner.y + d, 0)}
    }
    return out
}
