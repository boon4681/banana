package node

import "core:thread"

Describe_Kind :: enum u8 {
    Element,
    Component,
    If,
    Each,
    Render,
    Transparent
}

Description :: struct {
    tag,
    classes: string,
    kind: Describe_Kind
}

@(private)
Query :: struct {
    tag, key: string,
    classes:  [8]string,
    count:    int,
}

// What a node is to its author, for tools; set by the system that builds the tree.
describe: proc(n: ^BaseNode) -> (Description, bool)

// Answers the tag and class parts of a query; set by the style system that knows them.
Query_Match :: proc(n: ^BaseNode, tag: string, classes: []string) -> bool

@(thread_local)
// static stable method for query match
query_match: Query_Match
