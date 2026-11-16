package com.aeidolon.vaultexplorer.privacy

import java.io.File
import java.io.IOException

/** Strict privacy build: callers must stream or use encrypted workspace storage. */
object PlaintextScratch {
    const val MESSAGE = "This operation is unavailable in strict privacy mode because it requires an unencrypted temporary file outside the vault."
    val allowed: Boolean get() = false
    fun requireAllowed() { if (!allowed) throw IOException(MESSAGE) }
    @Suppress("UNUSED_PARAMETER")
    fun tempFile(prefix: String, suffix: String?, directory: File? = null): File {
        throw IOException(MESSAGE)
    }
    @Suppress("UNUSED_PARAMETER")
    fun file(directory: File?, name: String): File {
        throw IOException(MESSAGE)
    }
}
