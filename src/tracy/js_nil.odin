#+build js
package tracy

TRACY_ENABLE    :: false
TRACY_AUTO      :: false
TRACY_CALLSTACK :: i32(0)

ZoneCtx :: struct {}

ZoneBegin :: proc(active: bool, depth: i32, loc := #caller_location) -> ZoneCtx {
	return {}
}

ZoneName  :: proc(ctx: ZoneCtx, name: string) {}
ZoneEnd   :: proc(ctx: ZoneCtx) {}
FrameMark :: proc(name: cstring = nil) {}

IsConnected :: proc() -> bool { return false }
