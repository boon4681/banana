package text

SCRIPT_HAN  :: u32(0x48616E69) // 'Hani'
SCRIPT_HIRA :: u32(0x48697261) // 'Hira'
SCRIPT_KANA :: u32(0x4B616E61) // 'Kana'
SCRIPT_HANG :: u32(0x48616E67) // 'Hang'
SCRIPT_BOPO :: u32(0x426F706F) // 'Bopo'

// BCP 47 fallback tags; leave Hani to the host, but pin kana and Hangul.
script_language :: proc(script: u32) -> string {
    switch script {
    case SCRIPT_HIRA, SCRIPT_KANA: return "ja"
    case SCRIPT_HANG:              return "ko"
    case SCRIPT_BOPO:              return "zh-TW"
    case SCRIPT_HAN:               return han_language
    }
    return ""
}

// Which Han variant unified codepoints resolve to. Set once at startup.
han_language := "zh-Hans"

set_han_language :: proc(tag: string) {
    han_language = tag
}
