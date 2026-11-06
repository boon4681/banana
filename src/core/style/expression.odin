package style

import "core:strings"

// what a value get resolved against, node and parent for units and scope for var() lookups
@(private)
Context :: struct { e: ^Engine, node, parent, scope: ^Record, presentation: bool }
@(private)
Custom_Ref :: struct { declaration: ^Declaration, scope: i32 }

@(private)
custom_index :: proc(e: ^Engine, name: string) -> int {
    if i, ok := e.custom_names[name]; ok { return i }
    i := len(e.custom_names)
    e.custom_names[strings.clone(name)] = i
    return i
}
@(private)
custom_lookup :: proc(c: Context, name: string) -> (ref: Custom_Ref, ok: bool) {
    i, known := c.e.custom_names[name]
    if !known || c.scope == nil || i >= len(c.scope.custom) { return }
    ref = c.scope.custom[i]
    return ref, ref.declaration != nil
}

@(private)
valid_vars :: proc(vars: []Calc_Var) -> bool {
    for v in vars { if v.name == "" || !finite(v.factor) || int(v.unit) >= int(Unit.Calc) { return false } }
    return true
}
@(private)
valid_terms :: proc(p: Property, terms: [Unit]f32) -> bool {
    for coefficient in terms { if !finite(coefficient) { return false } }
    return !(p >= .Border_Top_Width && p <= .Border_Left_Width) || terms[.Percent] == 0
}
@(private)
valid_math :: proc(p: Property, ops: []Math_Op) -> bool {
    if len(ops) == 0 || len(ops) > 64 { return false }
    depth := 0
    for op in ops {
        switch op.kind {
        case .Term:
            if !valid_terms(p, op.calc) || !valid_vars(op.vars) { return false }
            depth += 1
        case .Min, .Max:
            if op.count < 1 || depth < int(op.count) { return false }
            depth -= int(op.count)-1
        case .Clamp:
            if depth < 3 { return false }
            depth -= 2
        case .Add, .Sub:
            if depth < 2 { return false }
            depth -= 1
        case .Scale:
            if depth < 1 || !finite(op.factor) { return false }
        case: return false
        }
    }
    return depth == 1
}
@(private)
valid_transform :: proc(ops: []Transform_Op) -> bool {
    if len(ops) == 0 || len(ops) > 64 { return false }
    for op in ops {
        if int(op.kind) >= len(Transform_Kind) { return false }
        for n in op.numbers { if !finite(n) { return false } }
        if op.kind != .Translate { continue }
        if !valid_value(.Translate_X, op.x) || !valid_value(.Translate_Y, op.y) || !valid_terms(.Translate_X, op.x_calc) || !valid_terms(.Translate_Y, op.y_calc) { return false }
        if op.x.unit == .Math || op.y.unit == .Math { return false }
    }
    return true
}
@(private)
valid_declaration :: proc(d: Declaration, defaults := false, custom := false) -> bool {
    if defaults && d.important { return false }
    if d.variable != "" && !d.has_fallback { return true }
    v := d.value
    if custom {
        if int(v.kind) >= len(Value_Kind) || int(v.unit) >= len(Unit) || int(v.keyword) >= len(Keyword) || !finite(v.number) || !finite(v.percent) { return false }
        for c in v.color { if !finite(c) { return false } }
    } else if !valid_value(d.property, v) { return false }
    p := d.property if !custom else Property.Translate_X
    if v.kind == .Length && v.unit == .Calc && (!valid_terms(p, d.calc) || !valid_vars(d.vars)) { return false }
    if v.kind == .Length && v.unit == .Math && !valid_math(p, d.math) { return false }
    if v.kind == .Transform && !valid_transform(d.transform) { return false }
    return true
}
@(private)
valid_declarations :: proc(decls: []Declaration, defaults := false) -> bool {
    for d in decls { if !valid_declaration(d, defaults) { return false } }
    return true
}
@(private)
valid_custom :: proc(decls: []Custom_Declaration, defaults := false) -> bool {
    for d in decls { if len(d.name) < 3 || d.name[:2] != "--" || !valid_declaration(d.declaration, defaults, true) { return false } }
    return true
}

@(private)
clone_vars :: proc(e: ^Engine, input: []Calc_Var) -> []Calc_Var {
    if len(input) == 0 { return nil }
    output := make([]Calc_Var, len(input))
    for v, i in input {
        output[i] = v
        output[i].name = strings.clone(v.name)
        custom_index(e, v.name)
    }
    return output
}
@(private)
free_vars :: proc(vars: []Calc_Var) {
    for v in vars { delete(v.name) }
    delete(vars)
}
@(private)
clone_declaration :: proc(e: ^Engine, input: Declaration) -> Declaration {
    d := input
    d.source.file = strings.clone(d.source.file)
    if d.value.kind == .Family { d.value.number = intern_family(e, d.families) }
    d.families = nil
    if d.value.kind == .Tracks { d.value.number = intern_tracks(e, d.tracks) }
    d.tracks = nil
    if d.value.kind == .Areas { d.value.number = intern_areas(e, d.areas) }
    d.areas = nil
    if d.value.kind == .Filter { d.value.number = intern_filter(e, d.filter) }
    d.filter = {}
    if d.value.kind == .Shadows { d.value.number = intern_shadows(e, d.shadows) }
    d.shadows = nil
    if d.value.kind == .Gradient { d.value.number = intern_gradient(e, d.gradient) }
    d.gradient = {}
    d.variable = strings.clone(d.variable)
    if d.variable != "" { custom_index(e, d.variable) }
    d.vars = clone_vars(e, d.vars)
    d.math = nil
    if len(input.math) > 0 {
        d.math = make([]Math_Op, len(input.math))
        for op, i in input.math {
            d.math[i] = op
            d.math[i].vars = clone_vars(e, op.vars)
        }
    }
    d.transform = nil
    if len(input.transform) > 0 {
        d.transform = make([]Transform_Op, len(input.transform))
        copy(d.transform, input.transform)
    }
    return d
}
@(private)
free_declaration :: proc(d: Declaration) {
    delete(d.source.file); delete(d.variable)
    free_vars(d.vars)
    for op in d.math { free_vars(op.vars) }
    delete(d.math); delete(d.transform)
}
@(private)
clone_declarations :: proc(e: ^Engine, input: []Declaration) -> []Declaration {
    output := make([]Declaration, len(input))
    for d, i in input { output[i] = clone_declaration(e, d) }
    return output
}
@(private)
free_declarations :: proc(decls: []Declaration) {
    for d in decls { free_declaration(d) }
    delete(decls)
}
@(private)
clone_custom :: proc(e: ^Engine, input: []Custom_Declaration) -> []Custom_Declaration {
    if len(input) == 0 { return nil }
    output := make([]Custom_Declaration, len(input))
    for d, i in input {
        output[i] = {strings.clone(d.name), clone_declaration(e, d.declaration)}
        custom_index(e, d.name)
    }
    return output
}
@(private)
free_custom :: proc(decls: []Custom_Declaration) {
    for d in decls { delete(d.name); free_declaration(d.declaration) }
    delete(decls)
}

// set the inline custom properties of a node
// they win over sheet rules, same as set_inline
set_inline_custom :: proc(e: ^Engine, id: Node_Id, declarations: []Custom_Declaration) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    if !valid_custom(declarations) { return .Invalid_Declaration }
    context.allocator = e.allocator
    replacement := clone_custom(e, declarations)
    free_custom(e.nodes[i].inline_custom)
    e.nodes[i].inline_custom = replacement; e.dirty = true
    return .None
}
// get the computed value of a custom property, property decide what its units and percent mean
// always fail while the engine is dirty
custom_value :: proc(e: ^Engine, id: Node_Id, name: string, property: Property = .Translate_X) -> (Value, bool) {
    i := node_index(e, id)
    if e.dirty || i < 0 || !e.nodes[i].initialized { return {}, false }
    node := &e.nodes[i]
    c := Context{e = e, node = node, parent = parent_record(e, node), scope = node}
    ref, ok := custom_lookup(c, name)
    if !ok { return {}, false }
    c.scope = &e.nodes[ref.scope]
    return resolve(c, property, ref.declaration^, 1)
}
@(private)
parent_record :: proc(e: ^Engine, node: ^Record) -> ^Record {
    i := node_index(e, e.tree.parent(e.tree.data, node.id))
    return &e.nodes[i] if i >= 0 else nil
}

@(private)
length_parts :: proc(v: Value) -> (px, percent: f32) {
    #partial switch v.unit {
    case .Percent: return 0, v.number
    case .Calc: return v.number, v.percent
    }
    return v.number, 0
}
@(private)
linear :: proc(c: Context, p: Property, terms: [Unit]f32, vars: []Calc_Var, depth: int) -> (px, percent: f32, ok: bool) {
    for coefficient, unit in terms {
        if coefficient == 0 || unit == .Calc || unit == .Math { continue }
        term := resolve_value(c.e, c.node, c.parent, p, length(coefficient, unit), c.presentation)
        if term.unit == .Percent { percent += term.number } else { px += term.number }
    }
    for v in vars {
        ref := custom_lookup(c, v.name) or_return
        inner := c
        // a var resolve where it was declared, so its own var() look up from there
        inner.scope = &c.e.nodes[ref.scope]
        value := resolve(inner, p, ref.declaration^, depth+1) or_return
        if v.numeric {
            if value.kind != .Number { return 0, 0, false }
            term := resolve_value(c.e, c.node, c.parent, p, length(v.factor*value.number, v.unit), c.presentation)
            if term.unit == .Percent { percent += term.number } else { px += term.number }
        } else {
            if value.kind != .Length || value.unit == .Math { return 0, 0, false }
            value_px, value_percent := length_parts(value)
            px += v.factor*value_px
            percent += v.factor*value_percent
        }
    }
    return px, percent, finite(px) && finite(percent)
}
@(private)
run :: proc(program: []Resolved_Op, basis: f32) -> f32 {
    stack: [64]f32
    top := 0
    for op in program {
        switch op.kind {
        case .Term:
            stack[top] = op.px + op.percent*basis/100
            top += 1
        case .Min, .Max:
            n := int(op.count)
            result := stack[top-n]
            for value in stack[top-n+1:top] { result = min(result, value) if op.kind == .Min else max(result, value) }
            top -= n-1
            stack[top-1] = result
        case .Clamp:
            stack[top-3] = max(stack[top-3], min(stack[top-2], stack[top-1]))
            top -= 2
        case .Add, .Sub:
            stack[top-2] += stack[top-1] if op.kind == .Add else -stack[top-1]
            top -= 1
        case .Scale: stack[top-1] *= op.factor
        }
    }
    return stack[0]
}
@(private)
resolve_math :: proc(c: Context, p: Property, ops: []Math_Op, depth: int) -> (v: Value, ok: bool) {
    resolved: [64]Resolved_Op
    nonlinear, percentage := false, false
    for op, i in ops {
        resolved[i] = {kind = op.kind, count = op.count, factor = op.factor}
        if op.kind == .Term {
            resolved[i].px, resolved[i].percent = linear(c, p, op.calc, op.vars, depth) or_return
            if resolved[i].percent != 0 { percentage = true }
        } else if op.kind == .Min || op.kind == .Max || op.kind == .Clamp { nonlinear = true }
    }
    program := resolved[:len(ops)]
    if nonlinear && percentage {
        return {kind = .Length, unit = .Math, number = f32(intern_expression(c.e, program))}, true
    }
    px := run(program, 0)
    percent := run(program, 100)-px if percentage else 0
    if percent == 0 && !negative_allowed(p) { px = max(0, px) }
    return mixed(px, percent), finite(px) && finite(percent)
}
@(private)
resolve_transform :: proc(c: Context, ops: []Transform_Op) -> (v: Value, ok: bool) {
    resolved: [64]Transform_Op
    for op, i in ops {
        resolved[i] = op
        if op.kind != .Translate { continue }
        axes := [2]Property{.Translate_X, .Translate_Y}
        values := [2]Value{op.x, op.y}
        terms := [2][Unit]f32{op.x_calc, op.y_calc}
        for p, axis in axes {
            if values[axis].unit == .Calc {
                px, percent := linear(c, p, terms[axis], nil, 0) or_return
                values[axis] = mixed(px, percent)
            } else { values[axis] = resolve_value(c.e, c.node, c.parent, p, values[axis], c.presentation) }
            if !finite(values[axis].number) || !finite(values[axis].percent) { return {}, false }
        }
        resolved[i].x, resolved[i].y = values[0], values[1]
        resolved[i].x_calc, resolved[i].y_calc = {}, {}
    }
    return {kind = .Transform, number = f32(intern_transform(c.e, resolved[:len(ops)]))}, true
}
@(private)
resolve :: proc(c: Context, p: Property, d: Declaration, depth := 0) -> (v: Value, ok: bool) {
    if depth > 16 { return {}, false }
    if d.variable != "" {
        if ref, found := custom_lookup(c, d.variable); found {
            inner := c
            // a var resolve where it was declared, so its own var() look up from there
            inner.scope = &c.e.nodes[ref.scope]
            if v, ok = resolve(inner, p, ref.declaration^, depth+1); ok { return }
        }
        if !d.has_fallback { return {}, false }
    }
    v = d.value
    if v.kind == .Transform { return resolve_transform(c, d.transform) }
    if v.kind != .Length { return v, true }
    #partial switch v.unit {
    case .Calc:
        px, percent := linear(c, p, d.calc, d.vars, depth) or_return
        if percent == 0 && !negative_allowed(p) { px = max(0, px) }
        return mixed(px, percent), true
    case .Math: return resolve_math(c, p, d.math, depth)
    }
    v = resolve_value(c.e, c.node, c.parent, p, v, c.presentation)
    return v, finite(v.number)
}

@(private)
intern_expression :: proc(e: ^Engine, program: []Resolved_Op) -> int {
    free_slot := -1
    search: for &slot, i in e.expressions {
        if i == 0 { continue }
        if !slot.used { free_slot = i; continue }
        if len(slot.ops) != len(program) { continue }
        for op, j in program { if slot.ops[j] != op { continue search } }
        slot.marked = true
        return i
    }
    ops := make([]Resolved_Op, len(program))
    copy(ops, program)
    if free_slot < 0 {
        append(&e.expressions, Expression{})
        free_slot = len(e.expressions)-1
    }
    e.expressions[free_slot] = {ops = ops, used = true, marked = true}
    return free_slot
}
@(private)
intern_transform :: proc(e: ^Engine, list: []Transform_Op) -> int {
    free_slot := -1
    search: for &slot, i in e.transforms {
        if i == 0 { continue }
        if !slot.used { free_slot = i; continue }
        if len(slot.ops) != len(list) { continue }
        for op, j in list { if slot.ops[j] != op { continue search } }
        slot.marked = true
        return i
    }
    ops := make([]Transform_Op, len(list))
    copy(ops, list)
    if free_slot < 0 {
        append(&e.transforms, Transform_List{})
        free_slot = len(e.transforms)-1
    }
    e.transforms[free_slot] = {ops = ops, used = true, marked = true}
    return free_slot
}
// resolve a computed length to px, basis is what its percent is of
evaluate :: proc(e: ^Engine, v: Value, basis: f32) -> f32 {
    if v.kind != .Length || v.unit != .Math { return resolve_percent(v, basis) }
    i := int(v.number)
    if e == nil || i <= 0 || i >= len(e.expressions) || !e.expressions[i].used { return 0 }
    return run(e.expressions[i].ops, basis)
}
// get the function list of a computed transform
// translations are already resolved, the list die on the next update
transform_ops :: proc(e: ^Engine, v: Value) -> []Transform_Op {
    i := int(v.number)
    if e == nil || v.kind != .Transform || i <= 0 || i >= len(e.transforms) || !e.transforms[i].used { return nil }
    return e.transforms[i].ops
}

@(private)
mark :: proc(e: ^Engine, v: Value) {
    i := int(v.number)
    if v.kind == .Length && v.unit == .Math && i > 0 && i < len(e.expressions) { e.expressions[i].marked = true }
    if v.kind == .Transform && i > 0 && i < len(e.transforms) { e.transforms[i].marked = true }
}
// free the expressions and transform lists nothing point at anymore
@(private)
collect :: proc(e: ^Engine) {
    if len(e.expressions) <= 1 && len(e.transforms) <= 1 { return }
    for &slot in e.expressions { slot.marked = false }
    for &slot in e.transforms { slot.marked = false }
    for &node in e.nodes {
        for p in Property { mark(e, node.pending[p]); mark(e, node.presented[p]) }
        for style in node.pseudo { if style != nil { for v in style { mark(e, v) } } }
        for tween in node.tweens { mark(e, tween.from); mark(e, tween.to); mark(e, tween.reversing_start) }
    }
    for &slot in e.expressions {
        if slot.used && !slot.marked { delete(slot.ops); slot = {} }
    }
    for &slot in e.transforms {
        if slot.used && !slot.marked { delete(slot.ops); slot = {} }
    }
}

@(private)
identity_op :: proc(kind: Transform_Kind) -> Transform_Op {
    op := Transform_Op{kind = kind, x = length(0), y = length(0)}
    if kind == .Scale { op.numbers = {1, 1, 0, 0, 0, 0} }
    if kind == .Matrix { op.numbers = {1, 0, 0, 1, 0, 0} }
    return op
}
// true when both lists have the same functions, `none` count as matching any list
@(private)
transforms_interpolable :: proc(e: ^Engine, a, b: Value) -> bool {
    a_ops, b_ops := transform_ops(e, a), transform_ops(e, b)
    if len(a_ops) == 0 || len(b_ops) == 0 { return len(a_ops)+len(b_ops) > 0 }
    if len(a_ops) != len(b_ops) { return false }
    for op, i in a_ops { if op.kind != b_ops[i].kind { return false } }
    return true
}
@(private)
interpolate_transform :: proc(e: ^Engine, a, b: Value, t: f32) -> Value {
    a_ops, b_ops := transform_ops(e, a), transform_ops(e, b)
    count := max(len(a_ops), len(b_ops))
    result: [64]Transform_Op
    for i in 0..<count {
        from := a_ops[i] if len(a_ops) > 0 else identity_op(b_ops[i].kind)
        to := b_ops[i] if len(b_ops) > 0 else identity_op(a_ops[i].kind)
        result[i] = to
        if to.kind == .Translate {
            result[i].x = interpolate(e, from.x, to.x, t)
            result[i].y = interpolate(e, from.y, to.y, t)
        }
        for n, j in from.numbers { result[i].numbers[j] = n + (to.numbers[j]-n)*t }
    }
    return {kind = .Transform, number = f32(intern_transform(e, result[:count]))}
}
