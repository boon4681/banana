#+build !windows
#+build !js
package platform

// linux and macos have no setting read yet, so they stay light
@(private = "file")
_prefers_dark :: proc() -> bool {
    return false
}

COLOR_SCHEME :: Color_Scheme_Interface {
    prefers_dark = _prefers_dark,
}
