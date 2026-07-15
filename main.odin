package test

import "core:fmt"
import "src:core/common"
import "src:core/painter"
import "src:core/platform"
import "src:core/render"

App_State :: struct {
    image: ^render.Image,
}

render_frame :: proc(window: ^platform.Window) {
    app := cast(^App_State)window.state
    if app == nil || app.image == nil do return
    image := app.image

    painter.begin_frame(window.painter, common.Color{24, 27, 34, 255})

    padding: f32 = 48
    available_w := max(f32(window.width) - padding * 2, 1)
    available_h := max(f32(window.height) - padding * 2, 1)
    scale := min(available_w / f32(image.w), available_h / f32(image.h), 1)
    draw_w := f32(image.w) * scale
    draw_h := f32(image.h) * scale
    destination := common.Rect {
        x = (f32(window.width) - draw_w) * 0.5,
        y = (f32(window.height) - draw_h) * 0.5,
        w = draw_w,
        h = draw_h,
    }

    painter.image(window.painter, image, destination)
    painter.end_frame(window.painter)
}

main :: proc() {
    window := platform.New({
        width  = 960,
        height = 640,
        title  = "Banana image test",
        vsync  = true,
    })
    defer platform.free(window)

    image, image_err := platform.load_image(window, "./test-image.jpg")
    if image_err != .None {
        fmt.eprintfln("failed to load test image: {}", image_err)
        return
    }

    app := App_State{image = image}
    window.state = &app

    window.on_refresh = render_frame
    for platform.update(window) {
        render_frame(window)
    }
}
