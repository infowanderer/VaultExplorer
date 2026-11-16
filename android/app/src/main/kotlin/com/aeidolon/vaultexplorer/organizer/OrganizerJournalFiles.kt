package com.aeidolon.vaultexplorer.organizer

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.nio.file.Files

/** Each atomic journal/backup contains ciphertext only, never serialized paths.
 * Per-job files avoid rewriting the entire secure-preferences catalog per chunk.
 * Encryption uses the host's existing Android Keystore AES-GCM implementation.
 */
class OrganizerJournalFiles(
    private val context: Context,
    private val encrypt: (String) -> String?,
    private val decrypt: (String) -> String?,
) {
    companion object {
        private val lock = Any()
        private fun directory(context: Context) = File(context.noBackupFilesDir, "organizer-journal-v1")
        fun clear(context: Context): Boolean = synchronized(lock) {
            val dir = directory(context)
            if (!dir.exists()) return@synchronized true
            check(dir.isDirectory && !Files.isSymbolicLink(dir.toPath())) { "Protected journal location changed" }
            val files = checkNotNull(dir.listFiles())
            var okay = true
            for (file in files) { if (!file.isFile || !file.delete()) okay = false }
            if (okay) okay = dir.delete()
            okay
        }
    }
    private fun file(key: String): File {
        require(key.startsWith("organizer_job_"))
        val id = key.removePrefix("organizer_job_")
        require(id.matches(Regex("[a-zA-Z0-9-]{1,64}")))
        val dir = directory(context)
        check(!Files.isSymbolicLink(dir.toPath())) { "Protected journal location changed" }
        return File(dir, "$id.enc")
    }
    fun read(key: String): String? = synchronized(lock) {
        check(OrganizerHandlers.currentWorkerIsValid()) { "Organizer session expired" }
        val base = file(key)
        if (!base.exists() && !File(base.path + ".bak").exists()) return@synchronized null
        val encoded = AtomicFile(base).openRead().use {
            check(it.channel.size() in 1..(512L * 1024)) { "Invalid protected journal size" }
            String(it.readBytes(), Charsets.UTF_8)
        }
        checkNotNull(decrypt(encoded)) { "Protected journal unavailable" }
    }
    fun write(key: String, value: String) = synchronized(lock) {
        check(OrganizerHandlers.currentWorkerIsValid()) { "Organizer session expired" }
        require(value.toByteArray(Charsets.UTF_8).size <= 256 * 1024)
        read(key) // Existing unreadable data must not be overwritten.
        val encrypted = checkNotNull(encrypt(value)) { "Protected journal encryption failed" }
        val base = file(key)
        if (!base.parentFile!!.isDirectory) {
            check(base.parentFile!!.mkdirs()) { "Protected journal directory unavailable" }
            organizerSyncDirectory(base.parentFile!!.parentFile!!.toPath())
        }
        val atomic = AtomicFile(base)
        val output = atomic.startWrite()
        try {
            // AtomicFile's .new/.bak files hold the already-encrypted bytes too.
            output.write(encrypted.toByteArray(Charsets.UTF_8))
            output.fd.sync()
            atomic.finishWrite(output)
            organizerSyncDirectory(base.parentFile!!.toPath())
        } catch (error: Exception) { atomic.failWrite(output); throw error }
        check(read(key) == value) { "Protected journal read-back failed" }
    }
    fun keys(): Set<String> = synchronized(lock) {
        check(OrganizerHandlers.currentWorkerIsValid()) { "Organizer session expired" }
        val dir = directory(context)
        if (!dir.exists()) return@synchronized emptySet()
        check(dir.isDirectory && !Files.isSymbolicLink(dir.toPath()))
        val names = checkNotNull(dir.listFiles()) { "Protected journal directory unavailable" }
        val result = linkedSetOf<String>()
        for (file in names) {
            if (file.name.endsWith(".enc.new")) continue // Uncommitted ciphertext; never delete or adopt its media.
            val id = file.name.removeSuffix(".bak").removeSuffix(".enc")
            check(file.isFile && id.matches(Regex("[a-zA-Z0-9-]{1,64}"))) { "Unrecognized protected journal record" }
            result.add("organizer_job_$id")
        }
        result
    }
}
