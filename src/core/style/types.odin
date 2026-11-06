package style

import "base:runtime"

IR_VERSION   :: 4
Node_Id      :: distinct u64 // 0 is nil. a reused handle must carry a generation or the old style leak into the new node
Sheet_Id     :: distinct u64
Animation_Id :: distinct u64
State :: enum {
    Hover,
    Active,
    Focus,
    Disabled,
    Enabled,
    Checked,
    Indeterminate,
    Target,
    Focus_Within,
    Focus_Visible
}
State_Set :: bit_set[State]

Tree_API :: struct {
    data:             rawptr,
    parent:           proc(r: rawptr, N: Node_Id) -> Node_Id,
    previous_sibling: proc(r: rawptr, N: Node_Id) -> Node_Id,
    tag:              proc(r: rawptr, N: Node_Id) -> string,
    id:               proc(r: rawptr, N: Node_Id) -> string,
    classes:          proc(r: rawptr, N: Node_Id) -> []string,
    attribute:        proc(r: rawptr, N: Node_Id, s: string) -> (string, bool),
    states:           proc(r: rawptr, N: Node_Id) -> State_Set,
    has_text:         proc(r: rawptr, N: Node_Id) -> bool, // whitespace text count but comments dont, used by :empty
}
Test_Kind :: enum {
    Universal,
    Tag,
    Id,
    Class,
    State,
    Attribute_Exists,
    Attribute_Equals,
    Attribute_Includes,
    Attribute_Dash,
    Attribute_Prefix,
    Attribute_Suffix,
    Attribute_Substring,
    Root,
    Empty,
    First_Child,
    Last_Child,
    Only_Child,
    First_Of_Type,
    Last_Of_Type,
    Only_Of_Type,
    Nth_Child,
    Nth_Last_Child,
    Nth_Of_Type,
    Nth_Last_Of_Type,
    Is,
    Where,
    Has,
}
Selector_Test :: struct {
    kind:              Test_Kind,
    name:              string,
    value:             string,
    state:             State,
    negate:            bool, // :not(), specificity come from the argument. :not(a, b) is just a negated Is
    a:                 i32,
    b:                 i32,  // an+b with n >= 0
    ascii_insensitive: bool,
    // selectors inside :is(), :where() or :has()
    // in :has() even the last step has a combinator, it say how the leftmost part relate to the tested element
    selectors:         []Selector,
}
Combinator :: enum {
    None,
    Child,
    Descendant,
    Adjacent_Sibling,
    General_Sibling
}
Selector_Step :: struct {
    tests: []Selector_Test,
    next:  Combinator, // relation to the next step, matching walk right to left
}
Pseudo_Element :: enum u8 {
    None,
    Placeholder,
    Selection
}
Selector :: struct {
    steps:  []Selector_Step,
    pseudo: Pseudo_Element
}
Specificity :: [3]u32 // ids, then classes attributes and states, then tags
Property :: enum u8 {
    Color,
    Background_Color,
    Opacity,
    Font_Size,
    Width,
    Height,
    Min_Width,
    Min_Height,
    Max_Width,
    Max_Height,
    Margin_Top,
    Margin_Right,
    Margin_Bottom,
    Margin_Left,
    Padding_Top,
    Padding_Right,
    Padding_Bottom,
    Padding_Left,
    Top,
    Right,
    Bottom,
    Left,
    Border_Top_Width,
    Border_Right_Width,
    Border_Bottom_Width,
    Border_Left_Width,
    Row_Gap,
    Column_Gap,
    Flex_Basis,
    Flex_Grow,
    Flex_Shrink,
    Display,
    Position,
    Flex_Direction,
    Flex_Wrap,
    Justify_Content,
    Align_Items,
    Align_Self,
    Align_Content,
    Box_Sizing,
    Overflow_X,
    Overflow_Y,
    Z_Index,
    Line_Height,
    Font_Weight,
    Visibility,
    Pointer_Events,
    Direction,
    Border_Top_Color,
    Border_Right_Color,
    Border_Bottom_Color,
    Border_Left_Color,
    Border_Top_Style,
    Border_Right_Style,
    Border_Bottom_Style,
    Border_Left_Style,
    Border_Top_Left_Radius,
    Border_Top_Right_Radius,
    Border_Bottom_Right_Radius,
    Border_Bottom_Left_Radius,
    Font_Family,
    Text_Align,
    Cursor,
    // applied in order translate, rotate, scale. rotate is in degrees
    Translate_X,
    Translate_Y,
    Rotate,
    Scale_X,
    Scale_Y,
    Transform_Origin_X,
    Transform_Origin_Y,
    Transform, // a function list, applied after translate, rotate and scale
    User_Select,
    Aspect_Ratio,
    Grid_Template_Columns,
    Grid_Template_Rows,
    Grid_Auto_Columns,
    Grid_Auto_Rows,
    // a line number, auto, or SPAN with the count in number
    Grid_Column_Start,
    Grid_Column_End,
    Grid_Row_Start,
    Grid_Row_End,
    Justify_Items,
    Justify_Self,
    Text_Transform,
    Letter_Spacing,
    White_Space,
    Text_Decoration_Line,
    Text_Overflow,
    Box_Shadow,
    Background_Image,
    Outline_Width,
    Outline_Style,
    Outline_Color,
    Outline_Offset,
    Grid_Template_Areas,
    // vertical corner radii, auto means same as the horizontal one
    Border_Top_Left_Radius_Y,
    Border_Top_Right_Radius_Y,
    Border_Bottom_Right_Radius_Y,
    Border_Bottom_Left_Radius_Y,
    Filter,
    // a color value has no keyword slot, so transparent mean auto for these two colors
    Scrollbar_Width,
    Scrollbar_Thumb_Color,
    Scrollbar_Track_Color,
}
Value_Kind :: enum u8 {
    Color,
    Number,
    Length,
    Keyword,
    Family,
    Transform,
    Tracks,
    Shadows,
    Gradient,
    Areas,
    Filter
}
Unit :: enum u8 {
    Px,
    Percent,
    Em,
    Rem,
    Vw,
    Vh,
    Vmin,
    Vmax,
    Pt,
    Pc,
    In,
    Cm,
    Mm,
    Q,
    Ex,
    Ch,
    Calc,
    Math
}
Keyword :: enum u8 {
    Auto,
    Initial,
    Inherit,
    Unset,
    None,
    Normal,
    Current_Color,
    Flex,
    Relative,
    Absolute,
    Row,
    Row_Reverse,
    Column,
    Column_Reverse,
    No_Wrap,
    Wrap,
    Wrap_Reverse,
    Flex_Start,
    Flex_End,
    Center,
    Stretch,
    Baseline,
    Space_Between,
    Space_Around,
    Space_Evenly,
    Content_Box,
    Border_Box,
    Visible,
    Hidden,
    Scroll,
    Ltr,
    Rtl,
    Solid,
    Left,
    Right,
    Start,
    End,
    Default,
    Pointer,
    Text,
    Ew_Resize,
    Ns_Resize,
    Nwse_Resize,
    Nesw_Resize,
    All,
    Block,
    Inline,
    Inline_Block,
    Inline_Flex,
    Flow_Root,
    Contents,
    Grid,
    Inline_Grid,
    Span,
    Underline,
    Line_Through,
    Uppercase,
    Lowercase,
    Capitalize,
    Pre,
    Clip,
    Ellipsis,
    Fixed,
    Area,
    Sticky,
    Thin,
}
Value :: struct {
    color:   [4]f32,
    number:  f32, // the length or number, or the engine list index for Family, Transform and Math
    percent: f32, // the percent part of a computed Calc
    kind:    Value_Kind,
    unit:    Unit,
    keyword: Keyword,
}
#assert(size_of(Value) == 28)
CALC         :: Value{kind = .Length, unit = .Calc}
MATH         :: Value{kind = .Length, unit = .Math}
FAMILY       :: Value{kind = .Family}
TRANSFORM    :: Value{kind = .Transform}
TRACKS       :: Value{kind = .Tracks}
Track_Kind   :: enum u8 { Auto, Px, Percent, Fr, Min_Content, Max_Content }
Track_Repeat :: enum u8 { Once, Auto_Fill, Auto_Fit }
Track        :: struct { kind: Track_Kind, value, min: f32, repeat: Track_Repeat }
span         :: proc(count: int) -> Value { return {kind = .Keyword, keyword = .Span, number = f32(count)} }
AREAS        :: Value{kind = .Areas}
Area         :: struct { name: u32, row, column, row_span, column_span: u16 }
area_name :: proc(name: string) -> u32 {
    h := u32(2166136261)
    for b in transmute([]u8)name { h = (h ~ u32(b)) * 16777619 }
    // fold to 24 bit cuz the id ride in Value.number and f32 cant hold more exactly
    return max((h >> 24) ~ (h & 0xFFFFFF), 1)
}
area :: proc(name: string) -> Value { return {kind = .Keyword, keyword = .Area, number = f32(area_name(name))} }
grid_areas :: proc(areas: []Area, important := false) -> Declaration {
    return {property = .Grid_Template_Areas, value = AREAS, areas = areas, important = important}
}
SHADOWS       :: Value{kind = .Shadows}
GRADIENT      :: Value{kind = .Gradient}
Shadow        :: struct { x, y, blur, spread: f32, color: [4]f32, inset: bool }
Gradient_Stop :: struct { color: [4]f32, position: f32 }
Gradient_Kind :: enum u8 { Linear, Radial }
Gradient      :: struct { kind: Gradient_Kind, angle: f32, stops: []Gradient_Stop }
FILTER        :: Value{kind = .Filter}
// a css filter list folded by the frontend into one blur, one color matrix and shadows
Filter          :: struct { blur: f32, color: [4][4]f32, offset: [4]f32, shadows: []Shadow }
FILTER_IDENTITY :: Filter{color = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}}
grid_tracks :: proc(property: Property, tracks: []Track, important := false) -> Declaration {
    return {property = property, value = TRACKS, tracks = tracks, important = important}
}
rgba    :: proc(r, g, b, a: f32) -> Value { return {kind = .Color, color = {r, g, b, a}} }
number  :: proc(n: f32) -> Value { return {kind = .Number, number = n} }
length  :: proc(n: f32, unit: Unit = .Px) -> Value { return {kind = .Length, number = n, unit = unit} }
keyword :: proc(k: Keyword) -> Value { return {kind = .Keyword, keyword = k} }
mixed :: proc(px, percent: f32) -> Value {
    if percent == 0 { return length(px) }
    if px == 0 { return length(percent, .Percent) }
    return {kind = .Length, unit = .Calc, number = px, percent = percent}
}
// make a calc() declaration from one coefficient per unit
// calc(100% - 20px) is written as calc(.Width, #partial [Unit]f32{.Percent = 100, .Px = -20})
calc :: proc(property: Property, terms: [Unit]f32, important := false) -> Declaration {
    return {property = property, value = CALC, calc = terms, important = important}
}
// make a font-family declaration
// the host try names in order, no match keep the inherited font
font_family :: proc(names: []string, important := false) -> Declaration {
    return {property = .Font_Family, value = FAMILY, families = names, important = important}
}
// resolve a computed length against the size its percent is of
// a Math value give 0 here, use evaluate for those
resolve_percent :: proc(v: Value, basis: f32) -> f32 {
    #partial switch v.unit {
    case .Percent: return v.number * basis / 100
    case .Calc: return v.number + v.percent * basis / 100
    case .Math: return 0
    }
    return v.number
}
Source_Span :: struct { file: string, line, column: u32 }
// factor * var(name) inside a calc sum
// numeric means the var is a plain number and the term is in unit
Calc_Var  :: struct { name: string, factor: f32, unit: Unit, numeric: bool }
Math_Kind :: enum u8 { Term, Min, Max, Clamp, Add, Sub, Scale }
// one step of a min(), max() or clamp() expression, the engine run the steps as a stack program
// Term push calc and vars, Min and Max pop count values, Clamp pop min, value and max, Add and Sub pop two, Scale multiply the top by factor
Math_Op        :: struct { kind: Math_Kind, count: i32, factor: f32, calc: [Unit]f32, vars: []Calc_Var }
Transform_Kind :: enum u8 { Translate, Rotate, Scale, Skew, Matrix }
// one function of a css transform list
// Translate use x and y (CALC read x_calc and y_calc), Rotate use numbers[0] in degrees, Scale and Skew use numbers[0..1], Matrix use numbers[0..5] in css matrix(a, b, c, d, e, f) order
Transform_Op :: struct { kind: Transform_Kind, x, y: Value, x_calc, y_calc: [Unit]f32, numbers: [6]f32 }
Declaration :: struct {
    property: Property, value: Value, important: bool, source: Source_Span,
    calc:         [Unit]f32, // only when value is CALC
    families:     []string,  // only when value is FAMILY
    // when set this is var(variable) and value become the fallback if has_fallback
    variable:     string,
    has_fallback: bool,
    vars:         []Calc_Var,     // only when value is CALC
    math:         []Math_Op,      // only when value is MATH
    transform:    []Transform_Op, // only when value is TRANSFORM
    tracks:       []Track,        // only when value is TRACKS
    areas:        []Area,         // only when value is AREAS
    shadows:      []Shadow,       // only when value is SHADOWS
    gradient:     Gradient,       // only when value is GRADIENT
    filter:       Filter,         // only when value is FILTER
}
// name keep the leading dashes and declaration.property is ignored
Custom_Declaration :: struct { name: string, declaration: Declaration }
// @font-face
Font_Face   :: struct { family, source: string }
Environment :: struct { width, height: f32, root_font_size: f32, reduced_motion: bool }
Media_Test :: struct {
    feature: enum { Min_Width, Max_Width, Min_Height, Max_Height, Portrait, Landscape, Reduced_Motion },
    value:   f32,
    negate:  bool,
}
// conditions are AND, the frontend split OR into separate rules
Rule :: struct { selectors: []Selector, declarations: []Declaration, conditions: []Media_Test, motion: []Motion_Declaration, custom: []Custom_Declaration }
// names are global across sheets, on a duplicate the highest order sheet win
Keyframes_Desc  :: struct { name: string, frames: []Keyframe }
Stylesheet_Desc :: struct { version: u32, rules: []Rule, keyframes: []Keyframes_Desc, font_faces: []Font_Face }
// ex and ch as a ratio of font size
Font_Metrics_Proc :: proc(data: rawptr, node: Node_Id, families: []string, weight: f32) -> (ex, ch: f32)
Motion_Event_Kind :: enum u8 {
    Transition_Run, Transition_Start, Transition_End, Transition_Cancel,
    Animation_Start, Animation_Iteration, Animation_End, Animation_Cancel,
}
// name is empty for play_animation, elapsed is seconds since it began
Motion_Event :: struct { node: Node_Id, kind: Motion_Event_Kind, property: Property, name: string, animation: Animation_Id, elapsed: f32 }

// each longhand cascade on its own
// transition-property and animation-name decide the count, the other lists repeat to fit
Motion_Property :: enum u8 {
    Transition_Property, Transition_Duration, Transition_Delay, Transition_Timing_Function,
    Animation_Name, Animation_Duration, Animation_Delay, Animation_Timing_Function,
    Animation_Iteration_Count, Animation_Direction, Animation_Fill_Mode, Animation_Play_State,
}
// one comma-separated entry of a transition or animation longhand
// only the field for that longhand is used
Motion_Item :: struct {
    all: bool, property: Property, // Transition_Property
    seconds:   f32,                // durations and delays
    easing:    Easing,
    name:      string, // Animation_Name, empty means none
    count:     f32,    // Animation_Iteration_Count, +inf means infinite
    direction: Animation_Direction,
    fill:      Animation_Fill,
    paused:    bool,
}
// an empty Transition_Property or Animation_Name list means none
Motion_Declaration :: struct {
    property:  Motion_Property,
    items:     []Motion_Item,
    important: bool,
    source:    Source_Span
}
EASE :: Easing{kind = .Cubic_Bezier, x1 = 0.25, y1 = 0.1, x2 = 0.25, y2 = 1}
Origin :: enum {
    Defaults,
    Author
}
Sheet_Options :: struct {
    origin: Origin,
    order:  i64
}
Computed_Style :: [Property]Value
Property_Set   :: bit_set[Property]
Winner :: struct {
    found:             bool,
    sheet:             Sheet_Id, // 0 means inline
    rule_index:        int,
    declaration_index: int,
    specificity:       Specificity,
    important:         bool,
    inline_style:      bool,
    source:            Source_Span,
}
Change :: struct {
    node:           Node_Id,
    style:          Computed_Style,
    properties:     Property_Set,
    affects_layout: bool,
    affects_paint:  bool,
    pseudo:         bool,
}
Error :: enum {
    None,
    Invalid_Version,
    Invalid_Selector,
    Invalid_Declaration,
    Unknown_Sheet,
    Unknown_Node,
    Invalid_Tree,
    Invalid_Environment,
    Invalid_Time,
    Invalid_Motion,
    Missing_Tree_API
}

Easing :: struct {
    kind:       enum { Linear, Cubic_Bezier, Steps },
    x1:         f32,
    y1:         f32,
    x2:         f32,
    y2:         f32,
    steps:      int,
    step_start: bool,
}
Transition :: struct {
    property: Property,
    duration: f64,
    delay:    f64,
    easing:   Easing,
    all:      bool
}
// easing run from this keyframe to the next, override the animation one
Keyframe :: struct {
    offset:       f32,
    declarations: []Declaration,
    easing:       Maybe(Easing)
}
Animation_Direction :: enum u8 {
    Normal,
    Reverse,
    Alternate,
    Alternate_Reverse
}
Animation_Fill :: enum u8 { None, Backwards, Forwards, Both }
Animation_Desc :: struct {
    frames:     []Keyframe,
    duration:   f64,
    delay:      f64,
    iterations: f64, // must be above 0, fractions ok, +inf repeat forever
    easing:     Easing,
    direction:  Animation_Direction,
    fill:       Animation_Fill,
}
@(private)
Playback :: struct {
    id:             Animation_Id,
    desc:           Animation_Desc,
    start:          f64,
    paused_at:      f64,
    paused:         bool,
    unstarted:      bool,
    resume_pending: bool,
    cascade:        bool,
    claimed:        bool,
    name:           string,
    started:        bool,
    ended:          bool,
    iteration:      f64,
}
@(private)
Tween :: struct {
    property:        Property,
    active:          bool,
    started:         bool,
    from:            Value,
    to:              Value,
    reversing_start: Value,
    start:           f64,
    duration:        f64,
    shortening:      f64,
    easing:          Easing
}
@(private)
Resolved_Op :: struct {
    kind:    Math_Kind,
    count:   i32,
    factor:  f32,
    px:      f32,
    percent: f32
}
@(private)
Expression :: struct {
    ops:    []Resolved_Op,
    used:   bool,
    marked: bool
}
@(private)
Transform_List :: struct {
    ops:    []Transform_Op,
    used:   bool,
    marked: bool
}
@(private)
Winner_Ref :: struct {
    sheet:        Sheet_Id,
    rule:         i32,
    declaration:  i32,
    specificity:  Specificity,
    found:        bool,
    important:    bool,
    inline_style: bool
}

@(private)
Sheet :: struct {
    id:      Sheet_Id,
    desc:    Stylesheet_Desc,
    options: Sheet_Options
}
@(private)
Record :: struct {
    id:                   Node_Id,
    inline:               []Declaration,
    pending:              Computed_Style, // the cascade result, only committed when update succeed
    presented:            Computed_Style, // pending with motion and animated inheritance on top
    inherited_properties: Property_Set,
    relative:             Property_Set, // specified as a non-px length, re-resolved while the font animate
    changed:              Property_Set, // pending changed since the last update
    restyled:             Property_Set, // presented changed since the last update
    current_color:        Property_Set, // specified as currentColor, must follow an animated color
    transitions:          []Transition,
    tweens:               [dynamic]Tween, // active ones only
    tweening:             Property_Set,
    animations:           [dynamic]Playback,
    winners:              [Property]Winner_Ref,
    inline_motion:        []Motion_Declaration,
    motion_winners:       [Motion_Property]Winner_Ref,
    inline_custom:        []Custom_Declaration,
    custom:               []Custom_Ref,                    // indexed by custom name, nil means unset. garbage while the engine is dirty
    pseudo:               [Pseudo_Element]^Computed_Style, // nil when no rule target it
    pseudo_changed:       bool,
    initialized:          bool,
    visit:                u8,
}
Engine :: struct {
    tree:                 Tree_API,
    allocator:            runtime.Allocator,
    sheets:               [dynamic]Sheet,
    nodes:                [dynamic]Record,
    node_lookup:          map[Node_Id]int,
    // interned so Value.number can point at them, index 0 is reserved for empty or none
    families:             [dynamic][]string,
    expressions:          [dynamic]Expression,
    transforms:           [dynamic]Transform_List,
    tracks:               [dynamic][]Track,
    shadows:              [dynamic][]Shadow,
    gradients:            [dynamic]Gradient,
    areas:                [dynamic][]Area,
    filters:              [dynamic]Filter,
    custom_names:         map[string]int,
    font_metrics:         Font_Metrics_Proc,
    font_metrics_data:    rawptr,
    font_face_generation: u64,
    events:               [dynamic]Motion_Event,
    changes:              [dynamic]Change,
    next_sheet:           u64,
    dirty:                bool,
    environment:          Environment,
    last_time:            f64,
    next_animation:       u64,
}
