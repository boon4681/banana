#ifndef BANANA_WASM_COMPAT_H
#define BANANA_WASM_COMPAT_H

#ifdef __wasm__

// read binding in lunasvg/wasm.odin
#define _SETJMP_H
#define __wasi_setjmp_h
#define _WASI_EMULATED_SETJMP

typedef int jmp_buf[1];

#ifdef __cplusplus
extern "C" {
#endif

int setjmp(jmp_buf env);
void longjmp(jmp_buf env, int value);

#ifdef __cplusplus
}
#endif

// read binding in lunasvg/wasm.odin
#define longjmp( env, val )   do { longjmp( env, val ); goto Exit; } while ( 0 )

#endif // __wasm__
#endif // BANANA_WASM_COMPAT_H
