// Windows-only: the linux/macos targets link a real libc++ via zig.

#include <chrono>
#include <thread>
#include <shared_mutex>
#include <condition_variable>

#include <windows.h>

namespace std {
inline namespace __1 {

namespace chrono {

system_clock::time_point system_clock::now() noexcept {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    unsigned long long ticks = (static_cast<unsigned long long>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    const unsigned long long EPOCH_DIFF_100NS = 116444736000000000ULL;
    unsigned long long us = (ticks - EPOCH_DIFF_100NS) / 10ULL;
    return time_point(duration_cast<system_clock::duration>(microseconds(us)));
}

steady_clock::time_point steady_clock::now() noexcept {
    static LARGE_INTEGER freq = [] {
        LARGE_INTEGER f;
        QueryPerformanceFrequency(&f);
        return f;
    }();
    LARGE_INTEGER ctr;
    QueryPerformanceCounter(&ctr);
    long long whole = ctr.QuadPart / freq.QuadPart;
    long long part = ctr.QuadPart % freq.QuadPart;
    long long ns = whole * 1000000000LL + (part * 1000000000LL) / freq.QuadPart;
    return time_point(nanoseconds(ns));
}

} // namespace chrono

void this_thread::sleep_for(const chrono::nanoseconds& ns) {
    if (ns.count() <= 0) {
        SwitchToThread();
        return;
    }
    // Round up so a sub-millisecond request never becomes a busy Sleep(0).
    long long ms = (ns.count() + 999999LL) / 1000000LL;
    Sleep(static_cast<DWORD>(ms));
}

unsigned thread::hardware_concurrency() noexcept {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwNumberOfProcessors;
}

// the shared_* half of the interface is never referenced, so an SRWLOCK in exclusive mode is
// sufficient. __shared_mutex_base's layout is a mutex + condvars, which is at
// least as large as the single pointer an SRWLOCK needs.
static_assert(sizeof(__shared_mutex_base) >= sizeof(SRWLOCK), "__shared_mutex_base too small to hold an SRWLOCK");

__shared_mutex_base::__shared_mutex_base() {
    SRWLOCK* l = reinterpret_cast<SRWLOCK*>(this);
    InitializeSRWLock(l);
}

void __shared_mutex_base::lock() {
    AcquireSRWLockExclusive(reinterpret_cast<SRWLOCK*>(this));
}

bool __shared_mutex_base::try_lock() {
    return TryAcquireSRWLockExclusive(reinterpret_cast<SRWLOCK*>(this)) != 0;
}

void __shared_mutex_base::unlock() {
    ReleaseSRWLockExclusive(reinterpret_cast<SRWLOCK*>(this));
}

// Tracy's Worker() thread runs even with sampling and system tracing disabled,
// and shutdown blocks until it drains, so this genuinely has to wake a waiter.
// libc++'s condition_variable wraps a __libcpp_condvar_t, which on this target
// is layout-compatible with CONDITION_VARIABLE.
static_assert(sizeof(condition_variable) >= sizeof(CONDITION_VARIABLE), "condition_variable too small to hold a CONDITION_VARIABLE");

void condition_variable::notify_one() noexcept {
    WakeConditionVariable(reinterpret_cast<PCONDITION_VARIABLE>(this));
}

}
}
