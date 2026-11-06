package style

import "core:strings"

@(private)
specificity :: proc(selector: Selector) -> (result: Specificity) {
    for step in selector.steps {
        for test in step.tests {
            #partial switch test.kind {
            case .Id: result[0] += 1
            case .Tag: result[2] += 1
            case .Universal, .Where:
            case .Is, .Has:
                best: Specificity
                for nested in test.selectors {
                    if candidate := specificity(nested); compare_specificity(candidate, best) > 0 { best = candidate }
                }
                result += best
            case: result[1] += 1
            }
        }
    }
    if selector.pseudo != .None { result[2] += 1 }
    return
}
@(private)
valid_selector :: proc(selector: Selector, relative := false, depth := 0) -> bool {
    if depth > 8 || len(selector.steps) == 0 || len(selector.steps) > 64 || int(selector.pseudo) >= len(Pseudo_Element) { return false }
    if relative && selector.pseudo != .None { return false }
    for step, i in selector.steps {
        if len(step.tests) == 0 || int(step.next) < 0 || int(step.next) > int(Combinator.General_Sibling) { return false }
        last := i == len(selector.steps)-1
        if (last && !relative) != (step.next == .None) { return false }
        for test in step.tests {
            if int(test.kind) < 0 || int(test.kind) >= len(Test_Kind) { return false }
            if (test.kind == .Tag || test.kind == .Id || test.kind == .Class || (test.kind >= .Attribute_Exists && test.kind <= .Attribute_Substring)) && test.name == "" { return false }
            if test.kind == .State && (int(test.state) < 0 || int(test.state) >= len(State)) { return false }
            nested := test.kind == .Is || test.kind == .Where || test.kind == .Has
            if nested != (len(test.selectors) > 0) { return false }
            for inner in test.selectors {
                if inner.pseudo != .None || !valid_selector(inner, test.kind == .Has, depth+1) { return false }
            }
        }
    }
    return true
}
@(private)
clone_selectors :: proc(input: []Selector) -> []Selector {
    if len(input) == 0 { return nil }
    output := make([]Selector, len(input))
    for selector, j in input {
        steps := make([]Selector_Step, len(selector.steps))
        output[j] = {steps = steps, pseudo = selector.pseudo}
        for step, k in selector.steps {
            steps[k] = {next = step.next, tests = make([]Selector_Test, len(step.tests))}
            for test, n in step.tests {
                steps[k].tests[n] = test
                steps[k].tests[n].name = strings.clone(test.name)
                steps[k].tests[n].value = strings.clone(test.value)
                steps[k].tests[n].selectors = clone_selectors(test.selectors)
            }
        }
    }
    return output
}
@(private)
free_selectors :: proc(selectors: []Selector) {
    for selector in selectors {
        for step in selector.steps {
            for test in step.tests { delete(test.name); delete(test.value); free_selectors(test.selectors) }
            delete(step.tests)
        }
        delete(selector.steps)
    }
    delete(selectors)
}
@(private)
compare_specificity :: proc(a, b: Specificity) -> int {
    for i in 0..<3 { if a[i] != b[i] { return 1 if a[i] > b[i] else -1 } }
    return 0
}
@(private)
matches_test :: proc(e: ^Engine, node: Node_Id, test: Selector_Test) -> bool {
    result := matches_positive_test(e, node, test)
    return !result if test.negate else result
}
@(private)
ascii_equal :: proc(a, b: string, insensitive: bool) -> bool {
    if len(a) != len(b) { return false }
    for i in 0..<len(a) {
        x, y := a[i], b[i]
        if insensitive {
            if x >= 'A' && x <= 'Z' { x += 'a'-'A' }
            if y >= 'A' && y <= 'Z' { y += 'a'-'A' }
        }
        if x != y { return false }
    }
    return true
}
@(private)
css_space :: proc(c: u8) -> bool { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' }
@(private)
attribute_matches :: proc(value: string, test: Selector_Test) -> bool {
    needle := test.value
    eq := test.ascii_insensitive
    #partial switch test.kind {
    case .Attribute_Exists: return true
    case .Attribute_Equals: return ascii_equal(value, needle, eq)
    case .Attribute_Dash:
        return ascii_equal(value, needle, eq) || (len(value) > len(needle) && value[len(needle)] == '-' && ascii_equal(value[:len(needle)], needle, eq))
    case .Attribute_Includes:
        if len(needle) == 0 { return false }
        start := 0
        for i := 0; i <= len(value); i += 1 {
            if i == len(value) || css_space(value[i]) {
                if ascii_equal(value[start:i], needle, eq) { return true }
                start = i+1
            }
        }
    case .Attribute_Prefix, .Attribute_Suffix, .Attribute_Substring:
        if len(needle) == 0 || len(needle) > len(value) { return false }
        if test.kind == .Attribute_Prefix { return ascii_equal(value[:len(needle)], needle, eq) }
        if test.kind == .Attribute_Suffix { return ascii_equal(value[len(value)-len(needle):], needle, eq) }
        for i in 0..=len(value)-len(needle) { if ascii_equal(value[i:i+len(needle)], needle, eq) { return true } }
    case:
    }
    return false
}
@(private)
nth_matches :: proc(index: int, a, b: i32) -> bool {
    delta := i64(index)-i64(b)
    return delta == 0 if a == 0 else delta % i64(a) == 0 && delta / i64(a) >= 0
}
@(private)
matches_positive_test :: proc(e: ^Engine, node: Node_Id, test: Selector_Test) -> bool {
    t := e.tree
    #partial switch test.kind {
    case .Universal: return true
    case .Tag: return t.tag != nil && t.tag(t.data, node) == test.name
    case .Id: return t.id != nil && t.id(t.data, node) == test.name
    case .Class:
        if t.classes != nil { for name in t.classes(t.data, node) { if name == test.name { return true } } }
    case .State: return t.states != nil && test.state in t.states(t.data, node)
    case .Attribute_Exists, .Attribute_Equals, .Attribute_Includes, .Attribute_Dash, .Attribute_Prefix, .Attribute_Suffix, .Attribute_Substring:
        if t.attribute != nil {
            value, present := t.attribute(t.data, node, test.name)
            return present && attribute_matches(value, test)
        }
    case .Root: return t.parent(t.data, node) == 0
    case .Empty:
        if t.has_text != nil && t.has_text(t.data, node) { return false }
        for record in e.nodes { if t.parent(t.data, record.id) == node { return false } }
        return true
    case .First_Child, .Last_Child, .Only_Child, .First_Of_Type, .Last_Of_Type, .Only_Of_Type,
         .Nth_Child, .Nth_Last_Child, .Nth_Of_Type, .Nth_Last_Of_Type:
        parent := t.parent(t.data, node)
        of_type := test.kind == .First_Of_Type || test.kind == .Last_Of_Type || test.kind == .Only_Of_Type || test.kind == .Nth_Of_Type || test.kind == .Nth_Last_Of_Type
        if of_type && t.tag == nil { return false }
        index, total := 1, 0
        if parent == 0 { total = 1 } // root count as its own only sibling
        else {
            for record in e.nodes {
                if t.parent(t.data, record.id) == parent && (!of_type || t.tag(t.data, record.id) == t.tag(t.data, node)) { total += 1 }
            }
        }
        if parent != 0 && t.previous_sibling != nil {
            at := t.previous_sibling(t.data, node)
            for at != 0 {
                if !of_type || t.tag(t.data, at) == t.tag(t.data, node) { index += 1 }
                at = t.previous_sibling(t.data, at)
            }
        }
        #partial switch test.kind {
        case .First_Child, .First_Of_Type: return index == 1
        case .Last_Child, .Last_Of_Type: return index == total
        case .Only_Child, .Only_Of_Type: return total == 1
        case .Nth_Last_Child, .Nth_Last_Of_Type: return nth_matches(total-index+1, test.a, test.b)
        case: return nth_matches(index, test.a, test.b)
        }
    case .Is, .Where:
        for nested in test.selectors { if matches(e, node, nested.steps) { return true } }
    case .Has:
        for nested in test.selectors {
            for record in e.nodes { if record.id != node && matches(e, record.id, nested.steps, node) { return true } }
        }
    }
    return false
}
// true when node match the selector steps
// anchor is for :has() relative selectors
@(private)
matches :: proc(e: ^Engine, node: Node_Id, steps: []Selector_Step, anchor: Node_Id = 0) -> bool {
    if node == 0 || len(steps) == 0 { return false }
    for test in steps[0].tests { if !matches_test(e, node, test) { return false } }
    t := e.tree
    last := len(steps) == 1
    if last && anchor == 0 { return true }
    #partial switch steps[0].next {
    case .None: return false
    case .Child:
        parent := t.parent(t.data, node)
        return parent == anchor if last else matches(e, parent, steps[1:], anchor)
    case .Adjacent_Sibling:
        if t.previous_sibling == nil { return false }
        previous := t.previous_sibling(t.data, node)
        return previous != 0 && previous == anchor if last else matches(e, previous, steps[1:], anchor)
    case .Descendant:
        for at := t.parent(t.data, node); at != 0; at = t.parent(t.data, at) {
            if (at == anchor if last else matches(e, at, steps[1:], anchor)) { return true }
        }
    case .General_Sibling:
        if t.previous_sibling == nil { return false }
        for at := t.previous_sibling(t.data, node); at != 0; at = t.previous_sibling(t.data, at) {
            if (at == anchor if last else matches(e, at, steps[1:], anchor)) { return true }
        }
    }
    return false
}
