package scroll_area

import "base:runtime"
import css "src:core/style"
import style_native "src:core/style/native"

CSS_TAG :: "scroll_area"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    css.rule(&css_defaults, CSS_TAG)->set_overflow(.Auto)
}

apply_style :: proc(n: ^Node, c: css.Computed_Style, alpha: f32, pseudo: style_native.Pseudo_Styles) {
    area := cast(^Scroll_Area)n
    s := area->style()
    if thumb := style_native.color(c[.Scrollbar_Thumb_Color], alpha); thumb.a > 0 {
        s.thumb_color, s.thumb_hover, s.thumb_pressed = thumb, thumb, thumb
        area._v_thumb->style().background = thumb
        area._h_thumb->style().background = thumb
    }
    if track := style_native.color(c[.Scrollbar_Track_Color], alpha); track.a > 0 {
        s.track_color, s.button_color = track, track
        area._v_track->style().background = track
        area._h_track->style().background = track
        area._arrow_up.btn->style().background = track
        area._arrow_down.btn->style().background = track
        area._arrow_left.btn->style().background = track
        area._arrow_right.btn->style().background = track
    }
    #partial switch c[.Scrollbar_Width].keyword {
    case .Thin: s.scrollbar_size = 8
    case .None: s.vertical, s.horizontal = .Hidden, .Hidden
    }
}
