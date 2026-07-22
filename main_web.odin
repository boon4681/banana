#+build js
package test

import "src:core/layout"
import "src:core/platform"
import "src:core/text"

web_window: ^platform.Window

main :: proc() {
	layout.scheduler_setup()
	ui_font = text.set_create()
	text.load_font(ui_font, "./fonts/segoeui.ttf") // Latin
	text.load_font(ui_font, "./fonts/leelawui.ttf") // Thai
	text.load_font(ui_font, "./fonts/msyh.ttc") // CJK
    
	web_window = platform.New({
		title        = "Banana WebGL",
		width        = 960,
		height       = 640,
		msaa_samples = 8,
		canvas       = "banana-canvas",
	})
	build_ui(web_window.root)
	layout.awake_window(web_window)
	web_window.on_refresh = render_frame
}

@(export)
step :: proc(delta_time: f64) -> bool {
	_ = delta_time
	if web_window == nil || !platform.update(web_window) do return false
	render_frame(web_window)
	return true
}
