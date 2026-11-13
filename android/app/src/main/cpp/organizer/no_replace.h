#pragma once
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <string>

namespace organizer {
inline bool syncParent(const char* path) {
    const std::string value(path);
    const auto slash = value.find_last_of('/');
    if (slash == std::string::npos) return false;
    const auto parent = slash == 0 ? std::string("/") : value.substr(0, slash);
    const int fd = ::open(parent.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return false;
    const bool okay = ::fsync(fd) == 0;
    ::close(fd);
    return okay;
}

inline bool renameNoReplace(const char* source, const char* destination) {
#if defined(__linux__) && defined(SYS_renameat2)
    // RENAME_NOREPLACE is atomic; unsupported filesystems fail closed.
    if (::syscall(SYS_renameat2, AT_FDCWD, source, AT_FDCWD, destination, 1U) != 0) return false;
    // A false result after the rename is an uncertain durability acknowledgement;
    // the operation journal retains both locations for explicit reconciliation.
    const bool sourceSynced = syncParent(source);
    const bool destinationSynced = syncParent(destination);
    return sourceSynced && destinationSynced;
#else
    return false;
#endif
}
}
