#pragma once
#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <mutex>
#include <stdexcept>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <vector>
#if defined(__linux__)
#include <linux/memfd.h>
#endif

namespace vault_privacy {
// Anonymous RAM storage only. OS swap/hibernation and compromised processes remain
// outside this guarantee. Never fall back to /tmp, cacheDir, O_TMPFILE or mkstemp.
class RamScratch {
public:
    static constexpr int64_t fileLimit = 32LL * 1024 * 1024;
    static constexpr int64_t totalLimit = 128LL * 1024 * 1024;
    RamScratch() {
#if defined(SYS_memfd_create) && defined(MFD_CLOEXEC)
        fd_ = static_cast<int>(::syscall(SYS_memfd_create, "vault-scratch", MFD_CLOEXEC));
#endif
        if (fd_ < 0) throw std::runtime_error("Strict privacy: anonymous RAM scratch is unavailable");
    }
    ~RamScratch() {
        if (fd_ >= 0) ::close(fd_);
        std::lock_guard<std::mutex> lock(budgetMutex_);
        reservedTotal_ -= reserved_;
    }
    RamScratch(const RamScratch&) = delete;
    RamScratch& operator=(const RamScratch&) = delete;
    bool writeAt(const uint8_t* data, size_t length, int64_t offset) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (offset < 0 || offset > fileLimit || length > static_cast<size_t>(fileLimit - offset)) return false;
        if (length == 0) return true;
        const int64_t end = offset + static_cast<int64_t>(length);
        if (end > reserved_) {
            std::lock_guard<std::mutex> budgetLock(budgetMutex_);
            const auto growth = end - reserved_;
            if (growth > totalLimit - reservedTotal_) return false;
            reservedTotal_ += growth;
            reserved_ = end;
        }
        size_t done = 0;
        while (done < length) {
            const auto n = ::pwrite(fd_, data + done, length - done, offset + static_cast<int64_t>(done));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) return false;
            done += static_cast<size_t>(n);
        }
        return true;
    }
    int64_t size() { std::lock_guard<std::mutex> lock(mutex_); return sizeLocked(); }
    int fd() const { return fd_; }
    std::vector<uint8_t> readAt(int64_t offset, int length) {
        std::lock_guard<std::mutex> lock(mutex_);
        const int64_t available = sizeLocked();
        if (offset < 0 || offset >= available || length <= 0) return {};
        std::vector<uint8_t> out(static_cast<size_t>(std::min<int64_t>(length, available - offset)));
        size_t done = 0;
        while (done < out.size()) {
            const auto n = ::pread(fd_, out.data() + done, out.size() - done, offset + static_cast<int64_t>(done));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            done += static_cast<size_t>(n);
        }
        out.resize(done); return out;
    }
private:
    int64_t sizeLocked() const { struct stat s{}; return ::fstat(fd_, &s) == 0 ? s.st_size : 0; }
    int fd_ = -1;
    int64_t reserved_ = 0;
    std::mutex mutex_;
    inline static std::mutex budgetMutex_;
    inline static int64_t reservedTotal_ = 0;
};
}
