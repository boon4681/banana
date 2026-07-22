package test

import "core:fmt"
import "core:strings"
import "core:time"
import "src:core/common"
import "src:core/layout"
import "src:core/node"
import "src:core/paint"
import "src:core/painter"
import "src:core/platform"
import "src:core/text"
import "src:ui/box"
import "src:ui/img"
import "src:ui/svg_node"
import "src:ui/text_node"

TIGER_SVG :: #load("tiger.svg")

ui_font: ^text.Font_Set
fps_label: ^text_node.Text_Node
stress_text: ^text_node.Text_Node
photo: ^img.Img_Node
last_frame: time.Tick
fps_smooth: f32

build_ui :: proc(root: ^node.Node) {
    // Mirrors index.html's `* { box-sizing: border-box }`; Yoga's default has
    // varied across major versions, so pin it rather than inherit it.
    root->style()->set_box_sizing(.BorderBox)->set_flex_direction(.Row)->set_padding_all(16)->set_gap_all(16)

    sidebar := box.New({background = {35, 39, 50, 255}, radius = 8}, "sidebar")
    sidebar->style()->set_width(220)->set_padding_all(12)->set_gap_all(8)
    for i in 0 ..< 5 {
        item := box.New({background = {52, 58, 74, 255}, radius = 6}, "item")
        item->style()->set_height(36)
        if i == 0 do item->style().background = {88, 101, 242, 255}
        sidebar->add(item)
    }

    main_col := node.New("main")
    main_col->style()->set_flex_grow(1)->set_flex_shrink(1)->set_flex_basis(0, node.percent)->set_flex_direction(.Column)->set_gap_all(16)

    header := box.New({background = {35, 39, 50, 255}, radius = 8}, "header")
    header->style()->set_height(56)

    cards := node.New("cards")
    cards->style()->set_flex_direction(.Row)->set_gap_all(16)->set_height(120)
    card_colors := [3]common.Color{
        {87, 242, 135, 255},
        {254, 231, 92, 255},
        {235, 69, 158, 255},
    }
    for color in card_colors {
        card := box.New({background = color, radius = 10}, "card")
        card->style()->set_flex_grow(1)
        cards->add(card)
    }

    content := box.New({background = {35, 39, 50, 255}, radius = 8}, "content")
    content->style()->set_flex_grow(1)->set_flex_direction(.Row)->set_gap_all(16)->set_padding_all(16)->set_overflow(.Hidden)->set_color({220, 224, 235, 255})->set_font_size(10)->set_line_height(1.35, node.percent)->set_font(ui_font)

    tiger, tiger_err := svg_node.New(string(TIGER_SVG), {}, "tiger")
    assert(tiger_err == .None, "failed to parse embedded tiger.svg")
    tiger->style()->set_flex_grow(1)->set_flex_basis(0, node.percent)->set_height(100, node.percent)
    content->add(tiger)

    photo = img.New("test-gif.gif", {fit = .Cover}, "photo")
    photo->style()->set_flex_grow(1)->set_flex_basis(0, node.percent)->set_height(100, node.percent)
    content->add(photo)

    text_panel := node.New("stress-text-panel")
    text_panel->style()->set_flex_grow(1)->set_flex_shrink(0)->set_flex_basis(0, node.percent)->set_overflow(.Hidden)
    stress_text = text_node.New(
            "Banana; GPU curve-rendered text via HarfBuzz. " +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "This paragraph wraps greedily at word boundaries when the box gets narrow.\n" +
            "Fallback: สวัสดีชาวโลก 你好世界，こんにちは。 مرحبا بالعالم mixed with Latin.\n" +
            "Explicit newlines work too.",
            "hello",
    )
    text_panel->add(stress_text)
    content->add(text_panel)

    main_col->add(header, cards, content)
    root->add(sidebar, main_col)

    fps_box := box.New({}, "fps")
    fps_box->style()->
        set_position_type(.Absolute)->
        set_position_top(4)->
        set_position_right(8)->
        set_font(ui_font)->
        set_font_size(14)->
        set_color({255, 255, 255, 180})
    fps_label = text_node.New("-- FPS")
    fps_box->add(fps_label)
    root->add(fps_box)
}

render_frame :: proc(window: ^platform.Window) {
    now := time.tick_now()
    if last_frame != {} {
        dt := f32(time.duration_seconds(time.tick_diff(last_frame, now)))
        if dt > 0 {
            fps_smooth = fps_smooth * 0.9 + (1 / dt) * 0.1
        }
    }
    last_frame = now
    fps_label->set_text(fmt.tprintf("%.0f FPS", fps_smooth))

    s := window.scale if window.scale > 0 else 1
    layout.update(window.root, f32(window.width) / s, f32(window.height) / s)

    painter.begin_frame(window.painter, common.Color{24, 27, 34, 255})
    dpi := common.IDENTITY_TRANSFORM
    dpi.scale = {s, s}
    painter.push_transform(window.painter, dpi, {0, 0})
    paint.draw(window.painter, window.root)
    painter.pop_transform(window.painter)
    painter.end_frame(window.painter)
    free_all(context.temp_allocator)
}

dynamic_stress_text :: proc(variant: int) -> string {
    b := strings.builder_make(context.temp_allocator)
    for line in 0 ..< 80 {
        strings.write_string(&b, "Deterministic dynamic text: HarfBuzz shaping, layout, atlas insertion, and retained mesh replacement. ")
        // Eight previously unseen CJK glyphs per change; all are covered by the
        // registered Microsoft YaHei fallback font.
        for j in 0 ..< 8 do strings.write_rune(&b, rune(0x4E00 + variant * 8 + j))
        strings.write_string(&b, " mixed with Latin and wrapping text.\n")
        _ = line
    }
    return strings.to_string(b)
}
