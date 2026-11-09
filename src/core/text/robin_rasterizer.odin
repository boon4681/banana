package text

// CPU preprocessing for Raster of Bezier Intersection
// Neighbourhoods (ROBIN), by James T. Griffin:
// https://github.com/jamesthomasgriffin/robin

import "base:runtime"
import "core:math"

Robin_Cell :: struct {
    partial_winding: i16,
    first:           u32,
    count:           u16,
}

Robin_Raster :: struct {
    cells:         []Robin_Cell,
    memberships:   []u32,
    min, max:      [2]f32,
    width, height: int,
    allocator:     runtime.Allocator,
}

@(private)
Robin_Curve :: struct {
    p1, p2, p3: [2]f32,
    a, b, c:    [2]f32,
    // x-root solve, specialised once per curve.
    linear:     bool, // |a.x| below the threshold: the x-equation degenerates
    inv_2ax:    f32,  // 1 / (2 * a.x), quadratic branch
    bx_sq:      f32,  // b.x * b.x, quadratic branch
    inv_bx:     f32,  // 1 / b.x, linear branch
    degenerate: bool, // linear branch with b.x ~ 0: no usable root
}

@(private="file")
Robin_Bounds :: struct {
    mn, mx: [2]f32,
}

@(private="file")
_robin_root_eligibility :: proc(y1, y2, y3, y: f32) -> u32 {
    shift := u32(0)
    if y > y1 do shift |= 1
    if y > y2 do shift |= 2
    if y > y3 do shift |= 4
    return (0x2E74 >> shift) & 0x0101
}

@(private="file")
_robin_eval :: proc(a, b, c: f32, t: f32) -> f32 {
    return (a * t + b) * t + c
}

@(private)
_robin_curve_prepare :: proc(p1, p2, p3: [2]f32) -> Robin_Curve {
    rc := Robin_Curve{
        p1 = p1,
        p2 = p2,
        p3 = p3,
        a  = p1 - 2 * p2 + p3,
        b  = 2 * (p2 - p1),
        c  = p1,
    }
    if abs(rc.a.x) < 1.0 / 65536.0 {
        rc.linear = true
        rc.degenerate = abs(rc.b.x) < 1e-12
        if !rc.degenerate do rc.inv_bx = 1 / rc.b.x
    } else {
        rc.inv_2ax = 1 / (2 * rc.a.x)
        rc.bx_sq = rc.b.x * rc.b.x
    }
    return rc
}

// L-shaped crossing count used by the ROBIN shader.
// Summed over a closed outline it is the ordinary non-zero winding number.
@(private)
_robin_curve_crossing_prepared :: proc(rc: Robin_Curve, line_y: f32, q: [2]f32) -> i32 {
    change: i32 = 0
    if rc.p1.x < q.x && rc.p1.y < line_y do change += 1
    if rc.p3.x < q.x && rc.p3.y < line_y do change -= 1

    v_code := _robin_root_eligibility(rc.p1.x, rc.p2.x, rc.p3.x, q.x)
    if v_code == 0 do return change

    roots: [2]f32
    if rc.linear {
        if rc.degenerate do return change
        t := -(rc.c.x - q.x) * rc.inv_bx
        roots = {t, t}
    } else {
        d := math.sqrt(max(rc.bx_sq - 4 * rc.a.x * (rc.c.x - q.x), 0))
        roots = {(-rc.b.x - d) * rc.inv_2ax, (-rc.b.x + d) * rc.inv_2ax}
    }

    if v_code & 1 != 0 {
        y := _robin_eval(rc.a.y, rc.b.y, rc.c.y, roots[0])
        if y < q.y do change += 1
    }
    if v_code > 1 {
        y := _robin_eval(rc.a.y, rc.b.y, rc.c.y, roots[1])
        if y < q.y do change -= 1
    }
    return change
}

@(private="file")
_robin_curve_bounds :: proc(points: [][2]f32, curve: int) -> Robin_Bounds {
    i := curve * 3
    b := Robin_Bounds{{math.F32_MAX, math.F32_MAX}, {-math.F32_MAX, -math.F32_MAX}}
    for p in points[i:][:3] {
        b.mn.x = min(b.mn.x, p.x); b.mn.y = min(b.mn.y, p.y)
        b.mx.x = max(b.mx.x, p.x); b.mx.y = max(b.mx.y, p.y)
    }
    return b
}

// Build ROBIN raster.
robin_build_raster :: proc(
    points: [][2]f32,
    bounds_min, bounds_max: [2]f32,
    width:  int = 16,
    height: int = 16,
    allocator := context.allocator,
    margin: [2]f32 = {},
) -> Robin_Raster {
    r := Robin_Raster{
        min       = bounds_min,
        max       = bounds_max,
        width     = width,
        height    = height,
        allocator = allocator,
    }
    if width <= 0 || height <= 0 || len(points) < 3 do return r

    r.cells = make([]Robin_Cell, width * height, allocator)
    span := bounds_max - bounds_min
    curve_count := len(points) / 3

    bounds := make([]Robin_Bounds, curve_count, context.temp_allocator)
    defer delete(bounds, context.temp_allocator)
    prepared := make([]Robin_Curve, curve_count, context.temp_allocator)
    defer delete(prepared, context.temp_allocator)
    for curve in 0 ..< curve_count {
        bounds[curve] = _robin_curve_bounds(points, curve)
        i := curve * 3
        prepared[curve] = _robin_curve_prepare(points[i], points[i + 1], points[i + 2])
    }

    // Sample centres, one per column.
    centres := make([]f32, width, context.temp_allocator)
    defer delete(centres, context.temp_allocator)
    for x in 0 ..< width {
        lo_x := bounds_min.x + span.x * f32(x) / f32(width)
        hi_x := bounds_min.x + span.x * f32(x + 1) / f32(width)
        centres[x] = (lo_x + hi_x) * 0.5
    }

    step_counts := make([]u32, width, context.temp_allocator)
    defer delete(step_counts, context.temp_allocator)
    step_range := make([][2]int, curve_count, context.temp_allocator)
    defer delete(step_range, context.temp_allocator)

    for curve in 0 ..< curve_count {
        b := bounds[curve]
        s0, s1 := width, -1
        for s in 0 ..< width {
            hit: bool
            if s == 0 {
                hit = b.mn.x < centres[0]
            } else {
                hit = b.mx.x >= centres[s - 1] && b.mn.x < centres[s]
            }
            if hit {
                if s < s0 do s0 = s
                s1 = s
            }
        }
        step_range[curve] = {s0, s1}
        for s in s0 ..= s1 do step_counts[s] += 1
    }

    step_offsets := make([]u32, width + 1, context.temp_allocator)
    defer delete(step_offsets, context.temp_allocator)
    step_total: u32
    for s in 0 ..< width {
        step_offsets[s] = step_total
        step_total += step_counts[s]
    }
    step_offsets[width] = step_total

    step_lists := make([]u32, step_total, context.temp_allocator)
    defer delete(step_lists, context.temp_allocator)
    step_cursor := make([]u32, width, context.temp_allocator)
    defer delete(step_cursor, context.temp_allocator)
    copy(step_cursor, step_offsets[:width])
    for curve in 0 ..< curve_count {
        r := step_range[curve]
        if r[1] < r[0] do continue
        for s in r[0] ..= r[1] {
            step_lists[step_cursor[s]] = u32(curve)
            step_cursor[s] += 1
        }
    }

    cell_count := width * height
    counts := make([]u32, cell_count + 1, context.temp_allocator)
    defer delete(counts, context.temp_allocator)

    inv_cell := [2]f32{f32(width) / span.x, f32(height) / span.y}
    curve_span := make([][4]int, curve_count, context.temp_allocator)
    defer delete(curve_span, context.temp_allocator)

    for curve in 0 ..< curve_count {
        b := bounds[curve]
        b.mn -= margin
        b.mx += margin
        x0 := clamp(int((b.mn.x - bounds_min.x) * inv_cell.x), 0, width - 1)
        x1 := clamp(int((b.mx.x - bounds_min.x) * inv_cell.x), 0, width - 1)
        y0 := clamp(int((b.mn.y - bounds_min.y) * inv_cell.y), 0, height - 1)
        y1 := clamp(int((b.mx.y - bounds_min.y) * inv_cell.y), 0, height - 1)
        curve_span[curve] = {x0, x1, y0, y1}
        for cy in y0 ..= y1 {
            for cx in x0 ..= x1 {
                counts[cy * width + cx] += 1
            }
        }
    }

    offsets := counts
    running: u32
    for i in 0 ..< cell_count + 1 {
        n := offsets[i]
        offsets[i] = running
        running += n
    }

    members := make([]u32, int(running), allocator)
    cursor := make([]u32, cell_count, context.temp_allocator)
    defer delete(cursor, context.temp_allocator)
    copy(cursor, offsets[:cell_count])
    for curve in 0 ..< curve_count {
        s := curve_span[curve]
        for cy in s[2] ..= s[3] {
            for cx in s[0] ..= s[1] {
                ci := cy * width + cx
                members[cursor[ci]] = u32(curve)
                cursor[ci] += 1
            }
        }
    }

    for y in 0 ..< height {
        cell_size := [2]f32{
            span.x / f32(width),
            span.y / f32(height),
        }
        lo_y := bounds_min.y + f32(y) * cell_size.y
        hi_y := lo_y + cell_size.y
        total: i32
        prev_qx: f32

        for x in 0 ..< width {
            lo := [2]f32{bounds_min.x + span.x * f32(x) / f32(width), lo_y}
            hi := [2]f32{bounds_min.x + span.x * f32(x + 1) / f32(width), hi_y}
            ci := y * width + x
            first := int(offsets[ci])
            cell_members := members[first:offsets[ci + 1]]

            q := (lo + hi) * 0.5
            step := step_lists[step_offsets[x]:step_offsets[x + 1]]
            if x == 0 {
                for curve in step {
                    total += _robin_curve_crossing_prepared(prepared[curve], lo.y, q)
                }
            } else {
                for curve in step {
                    total += _robin_curve_crossing_prepared(prepared[curve], lo.y, q)
                    total -= _robin_curve_crossing_prepared(prepared[curve], lo.y, {prev_qx, q.y})
                }
            }
            prev_qx = q.x
            local: i32
            for curve in cell_members {
                local += _robin_curve_crossing_prepared(prepared[curve], lo.y, q)
            }
            count := len(cell_members)
            r.cells[ci] = {
                partial_winding = i16(total - local),
                first           = u32(first),
                count           = u16(min(count, int(max(u16)))),
            }
        }
    }
    r.memberships = members[:]
    return r
}
