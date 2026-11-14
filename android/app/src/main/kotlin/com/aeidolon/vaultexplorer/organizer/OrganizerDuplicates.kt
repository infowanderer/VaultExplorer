package com.aeidolon.vaultexplorer.organizer

import java.util.concurrent.CancellationException

data class ExactDuplicateMember(val file: MediaLocation, val version: MediaVersion)
data class ExactDuplicateGroup(val sha256: String, val size: Long, val members: List<ExactDuplicateMember>)
data class ExactDuplicateReport(val examined: Int, val hashed: Int, val groups: List<ExactDuplicateGroup>)

/** Bounded read-only scan. Size buckets avoid hashing files without a peer.
 * Results are observations, never authority to delete, move, or reclaim bytes.
 */
class OrganizerDuplicates(private val files: OrganizerFiles, private val transfer: OrganizerTransfer) {
    fun scan(sources: List<MediaLocation>, cancelled: () -> Boolean = { false },
             progress: (Int, Int) -> Unit = { _, _ -> }): ExactDuplicateReport {
        require(sources.size in 1..500) { "Select 1–500 files" }
        require(sources.distinct().size == sources.size) { "Repeated source handle" }
        fun checkActive() { if (cancelled()) throw CancellationException() }
        val versions = linkedMapOf<MediaLocation, MediaVersion>()
        for (source in sources) {
            checkActive()
            val version = files.stat(source)
            require(version.size >= 0) { "Unknown file size" }
            versions[source] = version
        }
        val candidates = versions.entries.groupBy { it.value.size }.values
            .filter { it.size > 1 }.flatten()
        val matches = linkedMapOf<Pair<Long, String>, MutableList<ExactDuplicateMember>>()
        var hashed = 0
        progress(0, candidates.size)
        for ((source, expected) in candidates) {
            checkActive()
            val (version, hash) = transfer.fingerprint(source, cancelled)
            check(version == expected) { "Source changed during scan" }
            matches.getOrPut(version.size to hash) { mutableListOf() }
                .add(ExactDuplicateMember(source, version))
            progress(++hashed, candidates.size)
        }
        val groups = matches.filterValues { it.size > 1 }.map { (key, members) ->
            // Earlier members may have changed while later members were read.
            for (member in members) {
                checkActive()
                check(files.stat(member.file) == member.version) { "Source changed after hashing" }
            }
            ExactDuplicateGroup(key.second, key.first, members.toList())
        }
        checkActive()
        return ExactDuplicateReport(sources.size, hashed, groups)
    }
}
