package svg_node

import "core:strings"
import "src:core/common"
import "src:core/node"
import "src:core/painter"
import "src:core/svg"

Fit :: enum {
	Meet,    // preserve aspect ratio and center inside the node
	Stretch, // fill the node's complete layout rectangle
}

SVG_Style :: struct {
    using base: Style,
    tint: Color,
    fit:  Fit,
}

SVG_Node :: struct {
    using node: Node,
    style:   proc(self: ^SVG_Node) -> ^SVG_Style,
    set_svg: proc(self: ^SVG_Node, source: string) -> svg.Error,
    get_svg: proc(self: ^SVG_Node) -> string,
}

@(private="file")
_SVG_Data :: struct {
    source: string,
    doc:    svg.Document,
    cache:  svg.Cache,
}

New :: proc(source: string = "", style: SVG_Style = {}, key: Maybe(string) = nil) -> (^SVG_Node, svg.Error) {
    n := new(SVG_Node)
    node.Init(auto_cast(n), key)
    n.style = _get_style
    n.set_svg = _set_svg
    n.get_svg = _get_svg
    n.data = new(_SVG_Data)
    st := style
    if st.tint == {} do st.tint = common.COLOR_WHITE
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free
    n.measure = transmute(node.MeasureCallback)_measure
    n->apply_measure()
    err := _set_svg(n, source)
    return n, err
}

@(private="file")
_data :: proc(n:^SVG_Node)-> ^_SVG_Data {
     return auto_cast(n.data)
}

@(private="file")
_get_style :: proc(n:^SVG_Node)->^SVG_Style {
    return auto_cast(n._internal_style)
}

@(private="file")
_get_svg :: proc(n:^SVG_Node)->string {
     return _data(n).source
}

@(private="file")
_set_svg :: proc(n:^SVG_Node, source:string)->svg.Error {
    // An empty source leaves the node blank rather than failing; New passes "" when a caller wants to supply the document later.
    if source == "" {
        d := _data(n)
        svg.cache_destroy(&d.cache)
        svg.destroy(&d.doc)
        delete(d.source)
        d.source = ""
        n->dirty()
        return .None
    }
    doc, err := svg.parse(source)
    if err != .None do return err
    d := _data(n)
    svg.cache_destroy(&d.cache)
    svg.destroy(&d.doc)
    delete(d.source)
    d.doc = doc
    d.source = strings.clone(source)
    n->dirty()
    return .None
}

@(private="file")
_measure :: proc(n:^SVG_Node, w:f32, wm:node.MeasureMode, h:f32, hm:node.MeasureMode)->(ow,oh:f32) {
    vb := _data(n).doc.view_box
    ow, oh = max(vb.w, 0), max(vb.h, 0)
    if wm == .Exactly do ow = w
    if hm == .Exactly do oh = h
    if wm == .AtMost do ow = min(ow,w)
    if hm == .AtMost do oh = min(oh,h)
    return
}

@(private="file")
_draw :: proc(n:^SVG_Node) {
    st := n->style()
    d:=_data(n)
    svg.draw_cached(&d.doc, painter.get(), &d.cache, n.rect, st.fit == .Meet, st.tint)
}

@(private="file")
_free :: proc(n:^SVG_Node) {
    d := _data(n)
    svg.cache_destroy(&d.cache)
    svg.destroy(&d.doc)
    delete(d.source)
    free(d)
    free(n._internal_style)
}
