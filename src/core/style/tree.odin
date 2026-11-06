package style

@(private)
selector_callbacks :: proc(t: Tree_API, selector: Selector) -> Error {
    for step in selector.steps {
        if (step.next == .Adjacent_Sibling || step.next == .General_Sibling) && t.previous_sibling == nil { return .Missing_Tree_API }
        for test in step.tests {
            #partial switch test.kind {
            case .Tag: if t.tag == nil { return .Missing_Tree_API }
            case .Class: if t.classes == nil { return .Missing_Tree_API }
            case .Id: if t.id == nil { return .Missing_Tree_API }
            case .State: if t.states == nil { return .Missing_Tree_API }
            case .Attribute_Exists, .Attribute_Equals, .Attribute_Includes, .Attribute_Dash, .Attribute_Prefix, .Attribute_Suffix, .Attribute_Substring:
                if t.attribute == nil { return .Missing_Tree_API }
            case .First_Child, .Last_Child, .Only_Child, .Nth_Child, .Nth_Last_Child:
                if t.previous_sibling == nil { return .Missing_Tree_API }
            case .First_Of_Type, .Last_Of_Type, .Only_Of_Type, .Nth_Of_Type, .Nth_Last_Of_Type:
                if t.previous_sibling == nil || t.tag == nil { return .Missing_Tree_API }
            }
            for nested in test.selectors { if err := selector_callbacks(t, nested); err != .None { return err } }
        }
    }
    return .None
}
@(private)
validate_callbacks :: proc(e: ^Engine, desc: Stylesheet_Desc) -> Error {
    if e.tree.parent == nil { return .Missing_Tree_API }
    for rule in desc.rules { for selector in rule.selectors {
        if err := selector_callbacks(e.tree, selector); err != .None { return err }
    } }
    return .None
}

// validate the tree and fill order with parents before children
@(private)
tree_order :: proc(e: ^Engine, order: ^[dynamic]int, siblings := false) -> Error {
    if siblings && e.tree.previous_sibling == nil { return .None }
    for &n in e.nodes { n.visit = 0 }
    // walk up with an explicit path, not recursion, so a deep app tree cant blow the stack
    path: [dynamic]int
    defer delete(path)
    for _, i in e.nodes {
        if e.nodes[i].visit == 2 { continue }
        clear(&path)
        at := i
        for {
            n := &e.nodes[at]
            if n.visit == 2 { break }
            if n.visit == 1 { return .Invalid_Tree }
            n.visit = 1
            append(&path, at)
            id := e.tree.previous_sibling(e.tree.data, n.id) if siblings else e.tree.parent(e.tree.data, n.id)
            if id == 0 { break }
            next := node_index(e, id)
            if next < 0 { return .Invalid_Tree }
            if siblings && e.tree.parent(e.tree.data, id) != e.tree.parent(e.tree.data, n.id) { return .Invalid_Tree }
            at = next
        }
        for j := len(path)-1; j >= 0; j -= 1 {
            e.nodes[path[j]].visit = 2
            if !siblings { append(order, path[j]) }
        }
    }
    if siblings {
        Pair :: struct { parent, previous: Node_Id }
        successors := make(map[Pair]bool)
        defer delete(successors)
        for n in e.nodes {
            parent := e.tree.parent(e.tree.data, n.id)
            if parent == 0 { continue } // many style roots is fine
            pair := Pair{parent, e.tree.previous_sibling(e.tree.data, n.id)}
            if successors[pair] { return .Invalid_Tree } // two nodes claim the same previous sibling
            successors[pair] = true
        }
    }
    return .None
}
