#include <stdint.h>

struct wasm_longjmp_args {
    void* env;
    int value;
};

struct wasm_jmp_buf {
    void* function_invocation_id;
    uint32_t label;
    struct wasm_longjmp_args args;
};

// LLVM reserves tag 1 for C longjmp. This must be compiled with native Wasm
// exception handling; LLVM rewrites the matching setjmp site into a catch.
__attribute__((noreturn))
void __wasm_longjmp(void* env, int value) {
    struct wasm_jmp_buf* buf = env;
    if (value == 0)
        value = 1;
    buf->args.env = env;
    buf->args.value = value;
    __builtin_wasm_throw(1, &buf->args);
    __builtin_unreachable();
}
