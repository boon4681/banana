#+build !js
package test

import "core:fmt"
import "core:os"
import "core:time"
import "src:core/layout"
import "src:core/platform"
import "src:core/text"

main :: proc() {
	layout.scheduler_setup()
	defer layout.scheduler_shutdown()

	ui_font = text.set_create()
	defer text.set_destroy(ui_font)
    text.load_font(ui_font, "C:/Windows/Fonts/segoeui.ttf")
    text.load_font(ui_font, "C:/Windows/Fonts/leelawui.ttf")
    text.load_font(ui_font, "C:/Windows/Fonts/msyh.ttc")

	window := platform.New({width=960,height=640,title="Banana layout test",msaa_samples=8})
	defer platform.free(window)
	build_ui(window.root)
	layout.awake_window(window)

	shot_path: string
	benchmark, dynamic_benchmark := false, false
	for arg, i in os.args {
		if arg == "--shot" && i+1 < len(os.args) do shot_path = os.args[i+1]
		if arg == "--bench" do benchmark = true
		if arg == "--bench-dynamic" do dynamic_benchmark = true
	}
	if shot_path != "" {
		platform.update(window); render_frame(window)
		if !platform.capture(window, shot_path) do os.exit(1)
		return
	}
	if benchmark || dynamic_benchmark {
		if dynamic_benchmark do stress_text->set_text(dynamic_stress_text(0))
		for _ in 0..<120 { if !platform.update(window) do return; render_frame(window) }
		start := time.tick_now(); frame_count := 3000
		for frame in 0..<frame_count {
			if dynamic_benchmark && frame%60==0 do stress_text->set_text(dynamic_stress_text(1+frame/60))
			if !platform.update(window) do return
			render_frame(window)
		}
		elapsed := time.duration_seconds(time.tick_diff(start,time.tick_now()))
		name := dynamic_benchmark ? "dynamic" : "steady"
		fmt.printfln("{} benchmark: {} frames in {:.3f}s = {:.0f} FPS ({:.3f} ms/frame)",name,frame_count,elapsed,f64(frame_count)/elapsed,elapsed*1000/f64(frame_count))
		return
	}
	window.on_refresh = render_frame
	for platform.update(window) do render_frame(window)
}
