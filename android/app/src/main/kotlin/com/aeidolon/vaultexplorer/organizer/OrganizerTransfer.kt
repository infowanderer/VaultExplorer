package com.aeidolon.vaultexplorer.organizer

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CancellationException

/** Stable provider handles are kept alongside display paths. No permanent-delete API. */
data class MediaLocation(val root: String, val path: String, val uri: String? = null)
data class MediaVersion(val identity: String, val size: Long, val modified: Long)
data class OrganizerJob(
    val id: String,
    val source: MediaLocation,
    val destination: MediaLocation,
    val move: Boolean,
    val sourceVersion: MediaVersion,
    val sha256: String,
    val state: String = "planned",
    val created: MediaLocation? = null,
    val createdIdentity: String? = null,
    val trash: MediaLocation? = null,
    val message: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val annotation: String? = null,
)
interface OrganizerJournal {
    fun read(id: String): OrganizerJob
    /** Must durably commit protected data and verify it, or throw. */
    fun write(job: OrganizerJob)
}
interface OrganizerFiles {
    fun stat(file: MediaLocation): MediaVersion
    fun read(file: MediaLocation): InputStream
    fun availableBytes(directory: MediaLocation): Long? = null
    fun names(directory: MediaLocation): Set<String>
    /** Exclusive creation; never open an existing document for replacement. */
    fun create(directory: MediaLocation, name: String): MediaLocation
    fun write(file: MediaLocation, offset: Long, expectedIdentity: String): OutputStream
    fun supportsResume(file: MediaLocation): Boolean
    fun supportsTrash(file: MediaLocation): Boolean
    /** Reserve an empty, app-owned, unique trash slot without moving media. */
    fun trashSlot(file: MediaLocation, id: String): MediaLocation
    fun relocate(source: MediaLocation, target: MediaLocation)
}

/** One operation at a time, owned by the process-wide native worker. */
class OrganizerTransfer(private val files: OrganizerFiles, private val journal: OrganizerJournal) {
    companion object {
        const val BUFFER = 256 * 1024
        fun validName(name: String): Boolean = name.isNotBlank() && name != "." && name != ".." &&
            name.toByteArray(Charsets.UTF_8).size <= 240 &&
            name.none { it.code < 32 || it in "/\\\u0000:*?\"<>|" } &&
            !name.endsWith('.') && !name.endsWith(' ')
    }
    private fun same(a: MediaVersion, b: MediaVersion) = a == b
    private fun digest(file: MediaLocation, limit: Long? = null, cancelled: () -> Boolean = { false }): String {
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(BUFFER)
        var left = limit
        try {
            files.read(file).use { input ->
                while (left == null || left > 0) {
                    if (cancelled()) throw CancellationException()
                    val count = input.read(buffer, 0, minOf(buffer.size.toLong(), left ?: Long.MAX_VALUE).toInt())
                    if (count < 0) { check(left == null || left == 0L) { "Unexpected end of file" }; break }
                    check(count > 0) { "Storage stopped responding" }
                    hash.update(buffer, 0, count)
                    if (left != null) left -= count
                }
            }
        } finally { buffer.fill(0) }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    fun fingerprint(file: MediaLocation, cancelled: () -> Boolean = { false }): Pair<MediaVersion, String> {
        val before = files.stat(file)
        val hash = digest(file, cancelled = cancelled)
        check(before == files.stat(file)) { "Media changed while reading" }
        return before to hash
    }
    fun prepare(source: MediaLocation, directory: MediaLocation, name: String, move: Boolean, expected: MediaVersion? = null, annotation: String? = null, annotationHash: String? = null, cancelled: () -> Boolean = { false }): OrganizerJob {
        require(validName(name)) { "Invalid destination filename" }
        require(!move || files.supportsTrash(source)) { "This source supports verified copies only" }
        check(files.names(directory).none { it.equals(name, ignoreCase = true) }) { "Destination name already exists" }
        val version = files.stat(source)
        check(expected == null || expected == version) { "Source changed since staging" }
        require(version.size >= 0) { "Unknown source size" }
        files.availableBytes(directory)?.let { check(it >= version.size) { "Insufficient destination space" } }
        val hash = digest(source, cancelled = cancelled)
        if (cancelled()) throw CancellationException()
        check(same(version, files.stat(source))) { "Source changed while planning" }
        return OrganizerJob(UUID.randomUUID().toString(), source,
            MediaLocation(directory.root, directory.path.trimEnd('/') + "/" + name), move, version, hash, annotation = if (annotationHash == hash) annotation else null)
            .also { journal.write(it) }
    }
    private fun parent(file: MediaLocation) = MediaLocation(file.root, file.path.substringBeforeLast('/', ""))
    private fun name(file: MediaLocation) = file.path.substringAfterLast('/')
    private fun owned(job: OrganizerJob): MediaLocation {
        val target = checkNotNull(job.created) { "No owned output was recorded" }
        check(files.stat(target).identity == job.createdIdentity) { "Output identity changed" }
        return target
    }
    fun execute(id: String, cancelled: () -> Boolean = { false }, progress: (Long, Long) -> Unit = { _, _ -> }): OrganizerJob {
        var job = journal.read(id)
        if (job.state in setOf("complete", "undone")) return job
        // A crash during source quarantine is reconciled, never blindly repeated.
        if (job.state == "quarantining") return recoverQuarantine(job)
        require(job.state in setOf("planned", "copying", "verifying", "copied", "interrupted")) {
            "Inspect this operation before retrying; ownership is uncertain"
        }
        try {
            check(same(files.stat(job.source), job.sourceVersion)) { "Source identity or metadata changed" }
            check(digest(job.source, cancelled = cancelled) == job.sha256) { "Source content changed" }
            if (job.created == null) {
                check(job.state == "planned" || job.state == "interrupted") { "Output ownership is uncertain" }
                check(files.names(parent(job.destination)).none { it.equals(name(job.destination), true) }) { "Destination name already exists" }
                job = job.copy(state = "creating"); journal.write(job) // Intent before any output creation.
                val created = files.create(parent(job.destination), name(job.destination))
                job = job.copy(state = "copying", created = created, createdIdentity = files.stat(created).identity)
                journal.write(job) // Receipt before opening output for writing.
                check(name(created) == name(job.destination)) { "Provider changed the destination name; inspect the empty output" }
            }
            val target = owned(job)
            var offset = files.stat(target).size
            check(offset in 0..job.sourceVersion.size) { "Output size changed" }
            if (offset < job.sourceVersion.size) {
                files.availableBytes(parent(target))?.let { check(it >= job.sourceVersion.size - offset) { "Insufficient destination space" } }
                check(offset == 0L || files.supportsResume(target)) { "This provider cannot resume a partial copy; keep it and choose a new name" }
                check(digest(target) == digest(job.source, offset, cancelled)) { "Partial output was modified" }
                job = job.copy(state = "copying", message = null); journal.write(job)
                val buffer = ByteArray(BUFFER)
                try {
                    files.read(job.source).use { input ->
                        var skip = offset
                        while (skip > 0) { val n = input.skip(skip); check(n > 0) { "Cannot resume source" }; skip -= n }
                        files.write(target, offset, checkNotNull(job.createdIdentity)).use { output ->
                            while (offset < job.sourceVersion.size) {
                                if (cancelled()) throw CancellationException()
                                val count = input.read(buffer, 0, minOf(buffer.size.toLong(), job.sourceVersion.size - offset).toInt())
                                check(count > 0) { "Unexpected source end" }
                                output.write(buffer, 0, count); offset += count
                                progress(offset, job.sourceVersion.size)
                            }
                            check(input.read() == -1) { "Source grew during copy" }
                            output.flush()
                        }
                    }
                } finally { buffer.fill(0) }
            } else if (offset == 0L) {
                // A zero-byte document must still have a successful close/flush.
                files.write(target, 0, checkNotNull(job.createdIdentity)).use { it.flush() }
            }
            job = job.copy(state = "verifying"); journal.write(job)
            check(files.stat(target).identity == job.createdIdentity && files.stat(target).size == job.sourceVersion.size) { "Output changed during transfer" }
            check(digest(target, cancelled = cancelled) == job.sha256) { "Output read-back verification failed" }
            check(same(files.stat(job.source), job.sourceVersion) && digest(job.source, cancelled = cancelled) == job.sha256) { "Source changed during transfer" }
            job = job.copy(state = "copied"); journal.write(job)
            if (cancelled()) throw CancellationException()
            if (job.move) {
                val trash = files.trashSlot(job.source, UUID.randomUUID().toString())
                job = job.copy(state = "quarantining", trash = trash); journal.write(job)
                if (cancelled()) throw CancellationException()
                files.relocate(job.source, trash)
                return recoverQuarantine(job)
            }
            job = job.copy(state = "complete"); journal.write(job)
            return job
        } catch (error: Exception) {
            // Never remove a partial output, the source, or any third-party file.
            // If the protected journal itself failed, its earlier intent remains.
            val state = if (job.state == "creating" || job.state == "quarantining") "needsReview"
                else if (error is CancellationException) "interrupted" else "interrupted"
            val message = if (error is CancellationException) "Paused; original retained" else error.message?.take(160) ?: "Storage unavailable"
            val failed = job.copy(state = state, message = message)
            journal.write(failed)
            return failed
        }
    }
    private fun recoverQuarantine(job: OrganizerJob): OrganizerJob {
        // Both the copy and retained original must still match before completion.
        return try {
            val target = owned(job)
            check(digest(target) == job.sha256) { "Destination changed" }
            val trash = checkNotNull(job.trash)
            check(files.stat(trash).identity == job.sourceVersion.identity && digest(trash) == job.sha256) { "Retained original changed; inspect Trash" }
            job.copy(state = "complete", message = null).also { journal.write(it) }
        } catch (_: Exception) {
            var restored = false
            try {
                val trash = job.trash
                if (trash != null && files.names(parent(job.source)).none { it.equals(name(job.source), true) }) {
                    files.relocate(trash, job.source)
                    restored = true
                }
            } catch (_: Exception) { /* Keep all bytes and the intent for manual recovery. */ }
            job.copy(state = "needsReview", message = if (restored) "Move verification stopped; original restored. Inspect the retained copy."
                else "Inspect source, destination and retained Trash; nothing is deleted")
                .also { journal.write(it) }
        }
    }
    /** Explicit, read-only filesystem reconciliation. Never adopt an unrecorded output. */
    fun reconcile(id: String, cancelled: () -> Boolean = { false }): OrganizerJob {
        val job = journal.read(id)
        if (job.state == "complete" || job.state == "undone") return job
        return try {
            val created = checkNotNull(job.created)
            fun matches(file: MediaLocation, identity: String) = files.stat(file).identity == identity &&
                files.stat(file).size == job.sourceVersion.size && digest(file, cancelled = cancelled) == job.sha256
            val result = if (job.state == "undoing") {
                check(matches(job.destination, checkNotNull(job.createdIdentity))) { "Undo retention not complete" }
                if (job.move) check(matches(job.source, job.sourceVersion.identity)) { "Original restore not complete" }
                job.copy(state = "undone", message = null)
            } else {
                check(matches(created, checkNotNull(job.createdIdentity))) { "Copy is partial or changed" }
                val retained = try { job.trash != null && matches(job.trash, job.sourceVersion.identity) } catch (_: Exception) { false }
                if (job.move && retained) job.copy(state = "complete", message = null)
                else {
                    check(same(files.stat(job.source), job.sourceVersion) && digest(job.source, cancelled = cancelled) == job.sha256) { "Source changed" }
                    job.copy(state = "copied", message = "Copy verified; Resume finishes this operation")
                }
            }
            journal.write(result); result
        } catch (_: Exception) {
            job.copy(state = "needsReview", message = "Ownership or content is uncertain. Inspect recorded locations; no files were changed by verification.")
                .also { journal.write(it) }
        }
    }
    fun undo(id: String, cancelled: () -> Boolean = { false }): OrganizerJob {
        var job = journal.read(id)
        require(job.state == "complete") { "Only a completed transfer can be undone" }
        val target = owned(job)
        if (cancelled()) throw CancellationException()
        check(digest(target, cancelled = cancelled) == job.sha256) { "Destination was modified; undo refused" }
        require(files.supportsTrash(target)) { "This provider has no safe undo; keep the verified copy" }
        if (job.move) {
            val original = checkNotNull(job.trash)
            check(files.stat(original).identity == job.sourceVersion.identity && digest(original, cancelled = cancelled) == job.sha256) { "Retained original changed" }
            check(files.names(parent(job.source)).none { it.equals(name(job.source), true) }) { "Original name is occupied; undo refused" }
        }
        val undoTrash = files.trashSlot(target, UUID.randomUUID().toString())
        // The intent includes both restore and output-retention locations.
        job = job.copy(state = "undoing", message = null)
        journal.write(job.copy(destination = undoTrash))
        if (cancelled()) throw CancellationException()
        if (job.move) files.relocate(checkNotNull(job.trash), job.source)
        if (cancelled()) throw CancellationException()
        files.relocate(target, undoTrash)
        check(files.stat(undoTrash).identity == job.createdIdentity && digest(undoTrash, cancelled = cancelled) == job.sha256) { "Undo output changed; inspect retained bytes" }
        if (job.move) check(files.stat(job.source).identity == job.sourceVersion.identity && digest(job.source, cancelled = cancelled) == job.sha256) { "Restored source changed" }
        job = job.copy(state = "undone", destination = undoTrash)
        journal.write(job)
        return job
    }
}
