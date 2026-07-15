#include <cstddef>
#include <cstdlib>

void* operator new(std::size_t size) {
    if (size == 0) size = 1;
    void* p = std::malloc(size);
    if (p == nullptr) std::abort();
    return p;
}

void* operator new[](std::size_t size) {
    return ::operator new(size);
}

void operator delete(void* p) noexcept {
    std::free(p);
}

void operator delete[](void* p) noexcept {
    std::free(p);
}

void operator delete(void* p, std::size_t) noexcept {
    std::free(p);
}

void operator delete[](void* p, std::size_t) noexcept {
    std::free(p);
}

extern "C" void __cxa_pure_virtual() {
    std::abort();
}

namespace std {
[[noreturn]] void terminate() noexcept {
    std::abort();
}
inline namespace __1 {
void __libcpp_verbose_abort(const char*, ...) {
    std::abort();
}
}
}
