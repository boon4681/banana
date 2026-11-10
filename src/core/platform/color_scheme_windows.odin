#+build windows
package platform

import win32 "core:sys/windows"
import "core:time"

@(private = "file")
_dark: bool

@(private = "file")
_checked: time.Tick

@(private = "file")
_ever_checked: bool

// a theme switch show up within half a second, without a registry read every frame
@(private = "file")
RECHECK :: 500 * time.Millisecond

@(private = "file")
_prefers_dark :: proc() -> bool {
    if _ever_checked && time.tick_since(_checked) < RECHECK {
        return _dark
    }
    _ever_checked = true
    _checked = time.tick_now()
    light: win32.DWORD = 1
    size := win32.DWORD(size_of(light))
    status := win32.RegGetValueW(
        win32.HKEY_CURRENT_USER,
        win32.L(`Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`),
        win32.L("AppsUseLightTheme"),
        win32.RRF_RT_REG_DWORD,
        nil,
        &light,
        &size,
    )
    // windows before 10 has no such setting, and those apps are light
    _dark = status == 0 && light == 0
    return _dark
}

COLOR_SCHEME :: Color_Scheme_Interface {
    prefers_dark = _prefers_dark,
}
