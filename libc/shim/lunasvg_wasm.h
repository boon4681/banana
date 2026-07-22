#ifndef BANANA_WASM_COMPAT_H
#define BANANA_WASM_COMPAT_H

#ifdef __wasm__

// read binding in lunasvg/wasm.odin
#define _SETJMP_H
#define __wasi_setjmp_h
#define _WASI_EMULATED_SETJMP

#include <stdint.h>

// Storage for the LLVM/Emscripten Wasm SjLj ABI: invocation id, label, and
// the two-word exception payload. Keep this in sync with src/lunasvg/wasm.odin.
typedef uintptr_t jmp_buf[4];

#ifdef __cplusplus
extern "C" {
#endif

int setjmp(jmp_buf env);
void longjmp(jmp_buf env, int value);

#ifdef __cplusplus
}
#endif

#endif // __wasm__
#endif // BANANA_WASM_COMPAT_H
