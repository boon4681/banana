package style_native

import "core:math"
import style ".."
import "src:core/node"
import YG "src:yoga"

@(private)
Grid_Item :: struct {
    n: ^node.BaseNode,
    column, row, column_span, row_span: int,
    auto_width, auto_height, measured: bool,
    align: style.Keyword,
    outer_height: f32,
    justify:      style.Keyword,
    outer_width:  f32,
}

@(private)
grid_line :: proc(v: style.Value, explicit: int) -> int {
    n := int(v.number)
    return n - 1 if n > 0 else explicit + 1 + n
}
@(private)
grid_span :: proc(start, end: style.Value, explicit: int) -> (index, span: int) {
    index, span = -1, 1
    if start.kind == .Keyword && start.keyword == .Span { span = int(start.number) }
    if end.kind == .Keyword && end.keyword == .Span { span = int(end.number) }
    if start.kind == .Number && end.kind == .Number {
        a, b := grid_line(start, explicit), grid_line(end, explicit)
        if b < a { a, b = b, a }
        index, span = a, max(1, b - a)
    } else if start.kind == .Number {
        index = grid_line(start, explicit)
    } else if end.kind == .Number {
        index = grid_line(end, explicit) - span
    } else { return }
    index = max(0, index)
    return
}

@(private)
grid_area :: proc(areas: []style.Area, line: style.Value) -> (style.Area, bool) {
    if line.kind != .Keyword || line.keyword != .Area { return {}, false }
    for area in areas { if f32(area.name) == line.number { return area, true } }
    return {}, false
}

@(private)
expand_tracks :: proc(list: []style.Track, available, gap: f32) -> [dynamic]style.Track {
    out := make([dynamic]style.Track, context.temp_allocator)
    fixed: f32
    for track in list { if track.repeat == .Once && track.kind == .Px { fixed += track.value + gap } }
    for track in list {
        count := 1
        if track.repeat != .Once {
            smallest := track.min if track.min > 0 else track.value if track.kind == .Px else 0
            if smallest > 0 { count = max(1, int(math.floor((available - fixed + gap) / (smallest + gap)))) }
        }
        for _ in 0..<count { append(&out, track) }
    }
    return out
}

@(private)
size_tracks :: proc(tracks: []style.Track, content: []f32, available, gap: f32, definite: bool) -> []f32 {
    out := make([]f32, len(tracks), context.temp_allocator)
    used := gap * f32(max(0, len(tracks) - 1))
    fractions: f32
    stretchable := 0
    for track, i in tracks {
        switch track.kind {
        case .Px: out[i] = track.value
        case .Percent: out[i] = track.value / 100 * available if definite else content[i]
        case .Fr:
            if definite { fractions += track.value } else { out[i] = content[i] }
        case .Auto: out[i] = content[i]; stretchable += 1
        case .Min_Content, .Max_Content: out[i] = content[i]
        }
        out[i] = max(out[i], track.min)
        used += out[i]
    }
    if !definite { return out }
    free := available - used
    if fractions > 0 {
        for track in tracks { if track.kind == .Fr { free += track.min } }
        unit := max(0, free) / max(fractions, 1)
        for track, i in tracks { if track.kind == .Fr { out[i] = max(track.min, track.value * unit) } }
    } else if free > 0 && stretchable > 0 {
        for track, i in tracks { if track.kind == .Auto { out[i] += free / f32(stretchable) } }
    }
    return out
}

@(private)
grid_measure :: proc(item: ^Grid_Item, width: f32) -> (outer_width, outer_height: f32) {
    raw := item.n.raw
    if item.auto_width { YG.NodeStyleSetWidthAuto(raw) }
    if item.auto_height { YG.NodeStyleSetHeightAuto(raw) }
    YG.NodeCalculateLayout(raw, width, YG.UNDEFINED, .LTR)
    item.measured = true
    outer_width = YG.NodeLayoutGetWidth(raw) + YG.NodeLayoutGetMargin(raw, .Left) + YG.NodeLayoutGetMargin(raw, .Right)
    outer_height = YG.NodeLayoutGetHeight(raw) + YG.NodeLayoutGetMargin(raw, .Top) + YG.NodeLayoutGetMargin(raw, .Bottom)
    return
}

@(private)
track_at :: proc(explicit: []style.Track, implicit: style.Value, e: ^style.Engine, i: int) -> style.Track {
    if i < len(explicit) { return explicit[i] }
    if list := style.tracks(e, implicit); len(list) > 0 { return list[(i - len(explicit)) % len(list)] }
    return {}
}

@(private)
span_size :: proc(sizes: []f32, start, span: int, gap: f32) -> (offset, size: f32) {
    for i in 0..<start { offset += sizes[i] + gap }
    for i in start..<start+span { size += sizes[i] }
    size += gap * f32(span - 1)
    return
}

@(private)
layout_grid :: proc(h: ^Host, b: ^Binding, c: style.Computed_Style) -> (expected_height: f32, relayout: bool) {
    raw := b.node.raw
    width, height := content_size(raw)
    definite_height := c[.Height].kind != .Keyword
    column_gap := style.resolve_percent(c[.Column_Gap], width)
    row_gap := style.resolve_percent(c[.Row_Gap], height)

    columns := expand_tracks(style.tracks(h.engine, c[.Grid_Template_Columns]), width, column_gap)
    rows := expand_tracks(style.tracks(h.engine, c[.Grid_Template_Rows]), height, row_gap)
    areas := style.areas(h.engine, c[.Grid_Template_Areas])
    template_columns, template_rows := len(columns), len(rows)
    for area in areas {
        for len(columns) < int(area.column + area.column_span) { append(&columns, track_at(columns[:template_columns], c[.Grid_Auto_Columns], h.engine, len(columns))) }
        for len(rows) < int(area.row + area.row_span) { append(&rows, track_at(rows[:template_rows], c[.Grid_Auto_Rows], h.engine, len(rows))) }
    }
    explicit_columns, explicit_rows := len(columns), len(rows)
    if len(columns) == 0 { append(&columns, style.Track{}) }

    items := make([dynamic]Grid_Item, context.temp_allocator)
    fits := false
    for track in style.tracks(h.engine, c[.Grid_Template_Columns]) { if track.repeat == .Auto_Fit { fits = true } }
    for child in b.node.children {
        if child.freed || child.raw == nil { continue }
        item := Grid_Item{n = child, column = -1, row = -1, column_span = 1, row_span = 1, auto_width = true, auto_height = true, align = c[.Align_Items].keyword, justify = c[.Justify_Items].keyword}
        if id, bound := h.handles[child]; bound {
            cc, _ := style.presented_style(h.engine, id)
            if cc[.Display].keyword == .None || out_of_flow(cc) { continue }
            item.column, item.column_span = grid_span(cc[.Grid_Column_Start], cc[.Grid_Column_End], explicit_columns)
            item.row, item.row_span = grid_span(cc[.Grid_Row_Start], cc[.Grid_Row_End], explicit_rows)
            if area, named := grid_area(areas, cc[.Grid_Column_Start]); named { item.column, item.column_span = int(area.column), int(area.column_span) }
            if area, named := grid_area(areas, cc[.Grid_Row_Start]); named { item.row, item.row_span = int(area.row), int(area.row_span) }
            item.auto_width = cc[.Width].kind == .Keyword
            item.auto_height = cc[.Height].kind == .Keyword
            if cc[.Justify_Self].keyword != .Auto do item.justify = cc[.Justify_Self].keyword
            if cc[.Align_Self].keyword != .Auto { item.align = cc[.Align_Self].keyword }
        } else if YG.NodeStyleGetDisplay(child.raw) == .None { continue }
        append(&items, item)
    }
    if fits && len(items) < len(columns) { resize(&columns, max(1, len(items))) }
    for item in items {
        for len(columns) < max(item.column, 0) + item.column_span { append(&columns, track_at(columns[:explicit_columns], c[.Grid_Auto_Columns], h.engine, len(columns))) }
    }

    column_count := len(columns)
    taken := make([dynamic]bool, context.temp_allocator)
    free_at :: proc(taken: ^[dynamic]bool, columns, row, column, row_span, column_span: int) -> bool {
        if column + column_span > columns { return false }
        for r in row..<row+row_span {
            for k in column..<column+column_span {
                if i := r * columns + k; i < len(taken) && taken[i] { return false }
            }
        }
        return true
    }
    take :: proc(taken: ^[dynamic]bool, columns: int, item: Grid_Item) {
        if need := (item.row + item.row_span) * columns; len(taken) < need { resize(taken, need) }
        for r in item.row..<item.row+item.row_span {
            for k in item.column..<item.column+item.column_span { taken[r * columns + k] = true }
        }
    }
    for &item in items { if item.row >= 0 && item.column >= 0 { take(&taken, column_count, item) } }
    for &item in items {
        if item.row < 0 || item.column >= 0 { continue }
        for k in 0..<column_count {
            if free_at(&taken, column_count, item.row, k, item.row_span, item.column_span) { item.column = k; break }
        }
        if item.column < 0 { item.column = 0 }
        take(&taken, column_count, item)
    }
    cursor_row, cursor_column := 0, 0
    for &item in items {
        if item.row >= 0 { continue }
        if item.column >= 0 {
            row := cursor_row
            for !free_at(&taken, column_count, row, item.column, item.row_span, item.column_span) { row += 1 }
            item.row = row
        } else {
            search: for row := cursor_row; ; row += 1 {
                for k in (cursor_column if row == cursor_row else 0)..<column_count {
                    if free_at(&taken, column_count, row, k, item.row_span, item.column_span) {
                        item.row, item.column = row, k
                        break search
                    }
                }
            }
            cursor_row, cursor_column = item.row, item.column + item.column_span
        }
        take(&taken, column_count, item)
    }
    for item in items {
        for len(rows) < item.row + item.row_span { append(&rows, track_at(rows[:explicit_rows], c[.Grid_Auto_Rows], h.engine, len(rows))) }
    }

    column_content := make([]f32, len(columns), context.temp_allocator)
    for track, i in columns {
        if track.kind == .Px || track.kind == .Fr || track.kind == .Percent { continue }
        for &item in items {
            if item.column != i || item.column_span != 1 { continue }
            outer_width, _ := grid_measure(&item, YG.UNDEFINED)
            column_content[i] = max(column_content[i], outer_width)
        }
    }
    column_sizes := size_tracks(columns[:], column_content, width, column_gap, true)

    row_content := make([]f32, len(rows), context.temp_allocator)
    for &item in items {
        needs_height := item.align != .Stretch || !item.auto_height
        for i in item.row..<item.row+item.row_span {
            if kind := rows[i].kind; kind != .Px && !(definite_height && (kind == .Fr || kind == .Percent)) { needs_height = true }
        }
        if !needs_height { continue }
        _, area_width := span_size(column_sizes, item.column, item.column_span, column_gap)
        if item.justify != .Stretch && item.auto_width {
            item.outer_width, _ = grid_measure(&item, YG.UNDEFINED)
            area_width = min(area_width, item.outer_width)
            item.outer_width = area_width
        }
        _, item.outer_height = grid_measure(&item, area_width)
        if item.row_span == 1 { row_content[item.row] = max(row_content[item.row], item.outer_height) }
    }
    row_sizes := size_tracks(rows[:], row_content, height, row_gap, definite_height)
    for item in items {
        if item.row_span == 1 || !item.measured { continue }
        _, have := span_size(row_sizes, item.row, item.row_span, row_gap)
        if item.outer_height > have { row_sizes[item.row + item.row_span - 1] += item.outer_height - have }
    }

    origin_x, origin_y := YG.NodeLayoutGetPadding(raw, .Left), YG.NodeLayoutGetPadding(raw, .Top)
    for &item in items {
        x, area_width := span_size(column_sizes, item.column, item.column_span, column_gap)
        y, area_height := span_size(row_sizes, item.row, item.row_span, row_gap)
        child := item.n.raw
        // space the item's size dont include, its margins plus padding and border when content-box
        margin_x := YG.NodeLayoutGetMargin(child, .Left) + YG.NodeLayoutGetMargin(child, .Right)
        margin_y := YG.NodeLayoutGetMargin(child, .Top) + YG.NodeLayoutGetMargin(child, .Bottom)
        if YG.NodeStyleGetBoxSizing(child) == .ContentBox {
            margin_x += YG.NodeLayoutGetPadding(child, .Left) + YG.NodeLayoutGetPadding(child, .Right) + YG.NodeLayoutGetBorder(child, .Left) + YG.NodeLayoutGetBorder(child, .Right)
            margin_y += YG.NodeLayoutGetPadding(child, .Top) + YG.NodeLayoutGetPadding(child, .Bottom) + YG.NodeLayoutGetBorder(child, .Top) + YG.NodeLayoutGetBorder(child, .Bottom)
        }
        #partial switch item.align {
        case .Center: y += max(0, area_height - item.outer_height) / 2
        case .Flex_End: y += max(0, area_height - item.outer_height)
        }
        if item.outer_width > 0 {
            #partial switch item.justify {
            case .Center: x += max(0, area_width - item.outer_width) / 2
            case .Flex_End: x += max(0, area_width - item.outer_width)
            }
            area_width = item.outer_width
        }
        YG.NodeStyleSetPositionType(child, .Absolute)
        if item.measured { YG.NodeStyleSetPosition(child, .Left, YG.UNDEFINED) }
        YG.NodeStyleSetPosition(child, .Left, origin_x + x)
        YG.NodeStyleSetPosition(child, .Top, origin_y + y)
        if item.auto_width { YG.NodeStyleSetWidth(child, max(0, area_width - margin_x)) }
        if item.auto_height {
            if item.align == .Stretch { YG.NodeStyleSetHeight(child, max(0, area_height - margin_y)) } else { YG.NodeStyleSetHeightAuto(child) }
        }
    }

    _, content_height := span_size(row_sizes, 0, len(row_sizes), row_gap)
    _, content_width := span_size(column_sizes, 0, len(column_sizes), column_gap)
    frame_x := YG.NodeLayoutGetPadding(raw, .Left) + YG.NodeLayoutGetPadding(raw, .Right) + YG.NodeLayoutGetBorder(raw, .Left) + YG.NodeLayoutGetBorder(raw, .Right)
    frame_y := YG.NodeLayoutGetPadding(raw, .Top) + YG.NodeLayoutGetPadding(raw, .Bottom) + YG.NodeLayoutGetBorder(raw, .Top) + YG.NodeLayoutGetBorder(raw, .Bottom)
    border_box := c[.Box_Sizing].keyword == .Border_Box
    expected_height = height
    if !definite_height {
        // yoga cant size a box from absolute children, so content height go in as min-height
        floor := style.resolve_percent(c[.Min_Height], 0) if c[.Min_Height].kind == .Length && c[.Min_Height].unit == .Px else 0
        YG.NodeStyleSetMinHeight(raw, max(floor, content_height + (frame_y if border_box else 0)))
        expected_height = max(content_height, floor - (frame_y if border_box else 0))
    }
    if c[.Display].keyword == .Inline_Grid && c[.Width].kind == .Keyword {
        YG.NodeStyleSetMinWidth(raw, content_width + (frame_x if border_box else 0))
    }
    return expected_height, YG.NodeIsDirty(raw)
}

// undo grid placement on children when the node stop being a grid
@(private)
release_grid :: proc(h: ^Host, b: ^Binding) {
    for child in b.node.children {
        if child.freed || child.raw == nil { continue }
        // bound children reset on their own restyle, only unbound ones would keep the placement
        if _, bound := h.handles[child]; bound { continue }
        YG.NodeStyleSetPositionType(child.raw, .Relative)
        YG.NodeStyleSetPosition(child.raw, .Left, YG.UNDEFINED)
        YG.NodeStyleSetPosition(child.raw, .Top, YG.UNDEFINED)
        YG.NodeStyleSetWidthAuto(child.raw)
        YG.NodeStyleSetHeightAuto(child.raw)
    }
}
