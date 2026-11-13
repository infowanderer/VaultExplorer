package com.aeidolon.vaultexplorer.organizer

import android.system.Os
import android.system.OsConstants
import java.nio.file.Path

/** Unsupported directory durability refuses the operation; no weaker fallback. */
internal fun organizerSyncDirectory(path: Path) {
    val fd = Os.open(path.toString(), OsConstants.O_RDONLY or
        OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW, 0)
    try {
        check(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)) { "Storage directory changed" }
        Os.fsync(fd)
    } finally { Os.close(fd) }
}
