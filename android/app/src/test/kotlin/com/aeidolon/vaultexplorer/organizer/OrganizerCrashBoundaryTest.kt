package com.aeidolon.vaultexplorer.organizer

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

/** Abrupt termination bypasses exception recovery, unlike an ordinary I/O error. */
class OrganizerCrashBoundaryTest {
    private class ProcessStopped : Error()
    private class Journal(val cut: Int, val afterCommit: Boolean) : OrganizerJournal {
        val records = linkedMapOf<String, OrganizerJob>()
        var writes = 0
        var armed = true
        override fun read(id: String) = checkNotNull(records[id])
        override fun write(job: OrganizerJob) {
            writes++
            if (armed && writes == cut && !afterCommit) throw ProcessStopped()
            records[job.id] = job.copy()
            if (armed && writes == cut && afterCommit) throw ProcessStopped()
        }
    }

    private fun exercise(move: Boolean, cut: Int, after: Boolean): Int {
        val root = Files.createTempDirectory("organizer-crash-fixture-")
        val bytes = ByteArray(OrganizerTransfer.BUFFER + 37) { (it % 251).toByte() }
        try {
            Files.write(root.resolve("original.jpg"), bytes)
            Files.createDirectory(root.resolve("destination"))
            val sentinel = root.resolve("destination/unrelated.jpg")
            Files.write(sentinel, byteArrayOf(8, 9, 10))
            val files = RawOrganizerFiles()
            val journal = Journal(cut, after)
            val engine = OrganizerTransfer(files, journal)
            try {
                val plan = engine.prepare(MediaLocation(root.toString(), "original.jpg"),
                    MediaLocation(root.toString(), "destination"), "sorted.jpg", move)
                engine.execute(plan.id)
            } catch (_: ProcessStopped) { /* Intentionally skip all normal recovery. */ }
            val boundaryCount = journal.writes
            fun assertRetained() {
                val intact = Files.walk(root).use { paths -> paths.filter { Files.isRegularFile(it) }
                    .anyMatch { Files.readAllBytes(it).contentEquals(bytes) } }
                assertTrue("No complete original survived move=$move cut=$cut after=$after", intact)
                assertArrayEquals(byteArrayOf(8, 9, 10), Files.readAllBytes(sentinel))
            }
            assertRetained()
            journal.armed = false
            // A new worker may resume only states whose ownership is established.
            val recovered = OrganizerTransfer(files, journal)
            for (job in journal.records.values.toList()) {
                if (job.state in setOf("planned", "copying", "verifying", "copied", "interrupted", "quarantining")) {
                    recovered.execute(job.id)
                }
            }
            assertRetained()
            for (job in journal.records.values) {
                if (job.state == "complete") {
                    assertArrayEquals(bytes, Files.readAllBytes(root.resolve(job.created!!.path.trimStart('/'))))
                    if (move) assertArrayEquals(bytes, Files.readAllBytes(root.resolve(job.trash!!.path.trimStart('/'))))
                }
                if (job.state == "creating") {
                    // The output may exist, but without its durable receipt it
                    // must never be adopted, appended to, or silently removed.
                    val path = root.resolve("destination/sorted.jpg")
                    if (Files.exists(path)) assertEquals(0L, Files.size(path))
                }
            }
            return boundaryCount
        } finally { root.toFile().deleteRecursively() }
    }

    @Test fun copySurvivesBeforeAndAfterEveryJournalCommit() = allBoundaries(false)
    @Test fun moveSurvivesBeforeAndAfterEveryJournalCommit() = allBoundaries(true)
    private fun allBoundaries(move: Boolean) {
        val count = exercise(move, Int.MAX_VALUE, false)
        assertTrue(count >= 6)
        for (cut in 1..count) for (after in listOf(false, true)) exercise(move, cut, after)
    }
}
