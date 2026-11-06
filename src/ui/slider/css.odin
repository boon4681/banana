package slider

import "base:runtime"
import css "src:core/style"
import style_native "src:core/style/native"
import "src:ui/shared/theme"

CSS_TAG :: "slider"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    r := css.rule(&css_defaults, CSS_TAG)
    r->set_width(200)
    r->set_height(THUMB)
    r->set_flex_shrink(0)
    r->set_user_select(.None)
    r->set_background_color(theme.MUTED)
    r->set_color(theme.PRIMARY)

    ring := css.rule(&css_defaults, CSS_TAG, {.Focus_Visible})
    ring->set(.Outline_Style, css.keyword(.Solid))
    ring->set(.Outline_Width, css.length(3))
    ring->set(.Outline_Color, css.rgba(115.0/255, 115.0/255, 115.0/255, 0.5))

    css.rule(&css_defaults, CSS_TAG, {.Disabled})->set_opacity(0.5)
}

css_states :: proc(n: ^Node) -> css.State_Set {
    return {.Disabled} if (cast(^Slider)n).disabled else {.Enabled}
}

// `background-color` is the track, `color` the filled part and the thumb's ring.
apply_style :: proc(n: ^Node, c: css.Computed_Style, alpha: f32, pseudo: style_native.Pseudo_Styles) {
    s := cast(^Slider_Style)n._internal_style
    s.track = style_native.color(c[.Background_Color], alpha)
    s.range = style_native.color(c[.Color], alpha)
    s.thumb_border = s.range
    s.thumb = theme.FOREGROUND
    s.thumb.a = u8(clamp(alpha * 255, 0, 255))
}
