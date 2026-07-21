#include <string>
#include <memory>

template class std::basic_string<char>;

namespace std {
inline namespace __1 {

__shared_count::~__shared_count() {}

__shared_weak_count::~__shared_weak_count() {}

void __shared_weak_count::__release_weak() noexcept {
    if (__libcpp_atomic_refcount_decrement(__shared_weak_owners_) == -1)
        __on_zero_shared_weak();
}

const void *__shared_weak_count::__get_deleter(const type_info &) const noexcept {
    return nullptr;
}

}
}
