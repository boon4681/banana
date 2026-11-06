package theme

import "src:core/common"

Color :: common.Color

BACKGROUND         :: Color{10, 10, 10, 255}
FOREGROUND         :: Color{250, 250, 250, 255}
PRIMARY            :: Color{229, 229, 229, 255}
PRIMARY_FOREGROUND :: Color{23, 23, 23, 255}
MUTED              :: Color{38, 38, 38, 255}
MUTED_FOREGROUND   :: Color{161, 161, 161, 255}
ACCENT             :: Color{38, 38, 38, 255}
POPOVER            :: Color{23, 23, 23, 255}
BORDER             :: Color{255, 255, 255, 26}
INPUT              :: Color{255, 255, 255, 38}
INPUT_FILL         :: Color{255, 255, 255, 11}
RING               :: Color{115, 115, 115, 128}

RADIUS :: f32(6)

floats :: proc(c: Color) -> [4]f32 {
    return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}
}
