package yoga

import "core:c"

when ODIN_ARCH == .wasm32 {
    foreign import yoga "./libc/wasm/yogacore.o"
} else when ODIN_OS == .Windows {
    foreign import yoga "./libc/windows/yogacore.lib"
} else when ODIN_OS == .Darwin {
    foreign import yoga "./libc/macos/libyogacore.a"
} else {
    foreign import yoga "./libc/linux/libyogacore.a"
}

// IEEE-754 special f32 values used by Yoga layout.
NAN            :: f32(0h7fc0_0000)
UNDEFINED      :: NAN
INFINITY       :: f32(0h7f80_0000)
NEG_INFINITY   :: f32(0hff80_0000)

NodeRef        :: distinct rawptr
ConfigRef      :: distinct rawptr
ConfigConstRef :: distinct rawptr

Align :: enum c.int {
	Auto,
	FlexStart,
	Center,
	FlexEnd,
	Stretch,
	Baseline,
	SpaceBetween,
	SpaceAround,
	SpaceEvenly,
	Start,
	End,
}

BoxSizing :: enum c.int {
	BorderBox,
	ContentBox,
}

Dimension :: enum c.int {
	Width,
	Height,
}

Direction :: enum c.int {
	Inherit,
	LTR,
	RTL,
}

Display :: enum c.int {
	Flex,
	None,
	Contents,
	Grid,
}

Edge :: enum c.int {
	Left,
	Top,
	Right,
	Bottom,
	Start,
	End,
	Horizontal,
	Vertical,
	All,
}

FlexDirection :: enum c.int {
	Column,
	ColumnReverse,
	Row,
	RowReverse,
}

GridTrackType :: enum c.int {
	Auto,
	Points,
	Percent,
	Fr,
	Minmax,
}

Gutter :: enum c.int {
	Column,
	Row,
	All,
}

// Must match YGJustify in YGEnums.h exactly.
Justify :: enum c.int {
	FlexStart,
	Center,
	FlexEnd,
	SpaceBetween,
	SpaceAround,
	SpaceEvenly,
}

MeasureMode :: enum c.int {
	Undefined,
	Exactly,
	AtMost,
}

NodeType :: enum c.int {
	Default,
	Text,
}

Overflow :: enum c.int {
	Visible,
	Hidden,
	Scroll,
}

PositionType :: enum c.int {
	Static,
	Relative,
	Absolute,
}

Unit :: enum c.int {
	Undefined,
	Point,
	Percent,
	Auto,
	MaxContent,
	FitContent,
	Stretch,
}

Wrap :: enum c.int {
	NoWrap,
	Wrap,
	WrapReverse,
}

Value :: struct {
    value: f32,
    unit:  Unit,
}

Size :: struct {
    width:  f32,
    height: f32,
}

MeasureFunc :: #type proc "c" (
	node: NodeRef,
	width: f32,
	width_mode: MeasureMode,
	height: f32,
	height_mode: MeasureMode,
) -> Size

BaselineFunc :: #type proc "c" (node: NodeRef, width, height: f32) -> f32
DirtiedFunc  :: #type proc "c" (node: NodeRef)

IsNaN :: proc "contextless" (x: f32) -> bool {
    return x != x
}

@(default_calling_convention = "c", link_prefix = "YG")
foreign yoga {
    // Node lifecycle
    NodeNew           :: proc() -> NodeRef ---
    NodeNewWithConfig :: proc(config: ConfigConstRef) -> NodeRef ---
    NodeClone         :: proc(node: NodeRef) -> NodeRef ---
    NodeFree          :: proc(node: NodeRef) ---
    NodeFreeRecursive :: proc(node: NodeRef) ---
    NodeFinalize      :: proc(node: NodeRef) ---
    NodeReset         :: proc(node: NodeRef) ---

    // Tree
    NodeInsertChild       :: proc(node, child: NodeRef, index: c.size_t) ---
    NodeSwapChild         :: proc(node, child: NodeRef, index: c.size_t) ---
    NodeRemoveChild       :: proc(node, child: NodeRef) ---
    NodeRemoveAllChildren :: proc(node: NodeRef) ---
    NodeSetChildren       :: proc(owner: NodeRef, children: [^]NodeRef, count: c.size_t) ---
    NodeGetChild          :: proc(node: NodeRef, index: c.size_t) -> NodeRef ---
    NodeGetChildCount     :: proc(node: NodeRef) -> c.size_t ---
    NodeGetOwner          :: proc(node: NodeRef) -> NodeRef ---
    NodeGetParent         :: proc(node: NodeRef) -> NodeRef ---

    // Layout
    NodeCalculateLayout :: proc(node: NodeRef, available_width, available_height: f32, owner_direction: Direction) ---
    NodeGetHasNewLayout :: proc(node: NodeRef) -> bool ---
    NodeSetHasNewLayout :: proc(node: NodeRef, has_new_layout: bool) ---
    NodeIsDirty         :: proc(node: NodeRef) -> bool ---
    NodeMarkDirty       :: proc(node: NodeRef) ---

    // Measure / baseline callbacks
    NodeSetMeasureFunc  :: proc(node: NodeRef, measure_func: MeasureFunc) ---
    NodeHasMeasureFunc  :: proc(node: NodeRef) -> bool ---
    NodeSetBaselineFunc :: proc(node: NodeRef, baseline_func: BaselineFunc) ---
    NodeSetDirtiedFunc  :: proc(node: NodeRef, dirtied_func: DirtiedFunc) ---
    NodeSetContext      :: proc(node: NodeRef, context_: rawptr) ---
    NodeGetContext      :: proc(node: NodeRef) -> rawptr ---
    NodeSetNodeType     :: proc(node: NodeRef, node_type: NodeType) ---

    // Style: direction / flex
    NodeStyleSetDirection        :: proc(node: NodeRef, direction: Direction) ---
    NodeStyleGetDirection        :: proc(node: NodeRef) -> Direction ---
    NodeStyleSetFlexDirection    :: proc(node: NodeRef, flex_direction: FlexDirection) ---
    NodeStyleGetFlexDirection    :: proc(node: NodeRef) -> FlexDirection ---

    NodeStyleSetJustifyContent   :: proc(node: NodeRef, justify: Justify) ---
    NodeStyleGetJustifyContent   :: proc(node: NodeRef) -> Justify ---
    NodeStyleSetAlignContent     :: proc(node: NodeRef, align: Align) ---
    NodeStyleGetAlignContent     :: proc(node: NodeRef) -> Align ---
    NodeStyleSetAlignItems       :: proc(node: NodeRef, align: Align) ---
    NodeStyleGetAlignItems       :: proc(node: NodeRef) -> Align ---
    NodeStyleSetAlignSelf        :: proc(node: NodeRef, align: Align) ---
    NodeStyleGetAlignSelf        :: proc(node: NodeRef) -> Align ---

    NodeStyleSetPositionType     :: proc(node: NodeRef, position_type: PositionType) ---
    NodeStyleGetPositionType     :: proc(node: NodeRef) -> PositionType ---
    NodeStyleSetFlexWrap         :: proc(node: NodeRef, wrap: Wrap) ---
    NodeStyleGetFlexWrap         :: proc(node: NodeRef) -> Wrap ---
    NodeStyleSetOverflow         :: proc(node: NodeRef, overflow: Overflow) ---
    NodeStyleGetOverflow         :: proc(node: NodeRef) -> Overflow ---
    NodeStyleSetDisplay          :: proc(node: NodeRef, display: Display) ---
    NodeStyleGetDisplay          :: proc(node: NodeRef) -> Display ---

    NodeStyleSetFlex             :: proc(node: NodeRef, flex: f32) ---
    NodeStyleGetFlex             :: proc(node: NodeRef) -> f32 ---
    NodeStyleSetFlexGrow         :: proc(node: NodeRef, flex_grow: f32) ---
    NodeStyleGetFlexGrow         :: proc(node: NodeRef) -> f32 ---
    NodeStyleSetFlexShrink       :: proc(node: NodeRef, flex_shrink: f32) ---
    NodeStyleGetFlexShrink       :: proc(node: NodeRef) -> f32 ---

    NodeStyleSetFlexBasis        :: proc(node: NodeRef, flex_basis: f32) ---
    NodeStyleSetFlexBasisPercent :: proc(node: NodeRef, flex_basis: f32) ---
    NodeStyleSetFlexBasisAuto    :: proc(node: NodeRef) ---
    NodeStyleGetFlexBasis        :: proc(node: NodeRef) -> Value ---

    // Style: box model (edges)
    NodeStyleSetPosition        :: proc(node: NodeRef, edge: Edge, position: f32) ---
    NodeStyleSetPositionPercent :: proc(node: NodeRef, edge: Edge, position: f32) ---
    NodeStyleSetPositionAuto    :: proc(node: NodeRef, edge: Edge) ---
    NodeStyleGetPosition        :: proc(node: NodeRef, edge: Edge) -> Value ---

    NodeStyleSetMargin          :: proc(node: NodeRef, edge: Edge, margin: f32) ---
    NodeStyleSetMarginPercent   :: proc(node: NodeRef, edge: Edge, margin: f32) ---
    NodeStyleSetMarginAuto      :: proc(node: NodeRef, edge: Edge) ---
    NodeStyleGetMargin          :: proc(node: NodeRef, edge: Edge) -> Value ---

    NodeStyleSetPadding         :: proc(node: NodeRef, edge: Edge, padding: f32) ---
    NodeStyleSetPaddingPercent  :: proc(node: NodeRef, edge: Edge, padding: f32) ---
    NodeStyleGetPadding         :: proc(node: NodeRef, edge: Edge) -> Value ---

    NodeStyleSetBorder          :: proc(node: NodeRef, edge: Edge, border: f32) ---
    NodeStyleGetBorder          :: proc(node: NodeRef, edge: Edge) -> f32 ---

    NodeStyleSetGap             :: proc(node: NodeRef, gutter: Gutter, gap_length: f32) ---
    NodeStyleSetGapPercent      :: proc(node: NodeRef, gutter: Gutter, gap_length: f32) ---
    NodeStyleGetGap             :: proc(node: NodeRef, gutter: Gutter) -> Value ---

    NodeStyleSetBoxSizing       :: proc(node: NodeRef, box_sizing: BoxSizing) ---
    NodeStyleGetBoxSizing       :: proc(node: NodeRef) -> BoxSizing ---

    // Style: dimensions
    NodeStyleSetWidth            :: proc(node: NodeRef, width: f32) ---
    NodeStyleSetWidthPercent     :: proc(node: NodeRef, width: f32) ---
    NodeStyleSetWidthAuto        :: proc(node: NodeRef) ---
    NodeStyleGetWidth            :: proc(node: NodeRef) -> Value ---

    NodeStyleSetHeight           :: proc(node: NodeRef, height: f32) ---
    NodeStyleSetHeightPercent    :: proc(node: NodeRef, height: f32) ---
    NodeStyleSetHeightAuto       :: proc(node: NodeRef) ---
    NodeStyleGetHeight           :: proc(node: NodeRef) -> Value ---

    NodeStyleSetMinWidth         :: proc(node: NodeRef, min_width: f32) ---
    NodeStyleSetMinWidthPercent  :: proc(node: NodeRef, min_width: f32) ---
    NodeStyleGetMinWidth         :: proc(node: NodeRef) -> Value ---
    NodeStyleSetMinHeight        :: proc(node: NodeRef, min_height: f32) ---
    NodeStyleSetMinHeightPercent :: proc(node: NodeRef, min_height: f32) ---
    NodeStyleGetMinHeight        :: proc(node: NodeRef) -> Value ---

    NodeStyleSetMaxWidth         :: proc(node: NodeRef, max_width: f32) ---
    NodeStyleSetMaxWidthPercent  :: proc(node: NodeRef, max_width: f32) ---
    NodeStyleGetMaxWidth         :: proc(node: NodeRef) -> Value ---
    NodeStyleSetMaxHeight        :: proc(node: NodeRef, max_height: f32) ---
    NodeStyleSetMaxHeightPercent :: proc(node: NodeRef, max_height: f32) ---
    NodeStyleGetMaxHeight        :: proc(node: NodeRef) -> Value ---

    NodeStyleSetAspectRatio      :: proc(node: NodeRef, aspect_ratio: f32) ---
    NodeStyleGetAspectRatio      :: proc(node: NodeRef) -> f32 ---

    // Computed layout results
    NodeLayoutGetLeft        :: proc(node: NodeRef) -> f32 ---
    NodeLayoutGetTop         :: proc(node: NodeRef) -> f32 ---
    NodeLayoutGetRight       :: proc(node: NodeRef) -> f32 ---
    NodeLayoutGetBottom      :: proc(node: NodeRef) -> f32 ---
    NodeLayoutGetWidth       :: proc(node: NodeRef) -> f32 ---
    NodeLayoutGetHeight      :: proc(node: NodeRef) -> f32 ---
    NodeLayoutGetDirection   :: proc(node: NodeRef) -> Direction ---
    NodeLayoutGetHadOverflow :: proc(node: NodeRef) -> bool ---
    NodeLayoutGetMargin      :: proc(node: NodeRef, edge: Edge) -> f32 ---
    NodeLayoutGetBorder      :: proc(node: NodeRef, edge: Edge) -> f32 ---
    NodeLayoutGetPadding     :: proc(node: NodeRef, edge: Edge) -> f32 ---

    // Config
    ConfigNew                 :: proc() -> ConfigRef ---
    ConfigFree                :: proc(config: ConfigRef) ---
    ConfigGetDefault          :: proc() -> ConfigConstRef ---
    ConfigSetPointScaleFactor :: proc(config: ConfigRef, pixels_in_point: f32) ---
}
