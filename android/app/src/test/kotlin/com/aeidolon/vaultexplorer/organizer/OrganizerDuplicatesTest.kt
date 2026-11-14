package com.aeidolon.vaultexplorer.organizer

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class OrganizerDuplicatesTest {
    private fun fixture(action: (Path, RawOrganizerFiles, OrganizerTransfer) -> Unit) {
        val root = Files.createTempDirectory("dupe-synthetic-")
        val noWrites = object : OrganizerJournal {
            override fun read(id: String): OrganizerJob = error("Scanner must not read transfer plans")
            override fun write(job: OrganizerJob): Unit = error("Scanner must not create transfer plans")
        }
        try { val raw = RawOrganizerFiles(); action(root, raw, OrganizerTransfer(raw, noWrites)) }
        finally { root.toFile().deleteRecursively() }
    }
    private fun put(root: Path, name: String, value: String): MediaLocation {
        Files.write(root.resolve(name), value.toByteArray())
        return MediaLocation(root.toString(), name)
    }
    @Test fun sameSizeDifferentContentIsNotADuplicateAndSingletonsAreNotRead() = fixture { root, raw, engine ->
        val a = put(root, "a.jpg", "same")
        val b = put(root, "b.jpg", "same")
        val c = put(root, "c.jpg", "diff")
        val d = put(root, "large.mp4", "single-size")
        var reads = 0
        val observed = object : OrganizerFiles by raw {
            override fun read(file: MediaLocation): java.io.InputStream {
                assertNotEquals(d, file); reads++; return raw.read(file)
            }
        }
        val journal = object : OrganizerJournal {
            override fun read(id: String): OrganizerJob = error("Unexpected plan read")
            override fun write(job: OrganizerJob): Unit = error("Unexpected plan write")
        }
        val report = OrganizerDuplicates(observed, OrganizerTransfer(observed, journal)).scan(listOf(a, b, c, d))
        assertEquals(4, report.examined); assertEquals(3, report.hashed); assertEquals(3, reads)
        assertEquals(listOf(a, b), report.groups.single().members.map { it.file })
        assertEquals(4L, report.groups.single().size)
        assertArrayEquals("same".toByteArray(), Files.readAllBytes(root.resolve("a.jpg")))
        assertEquals(4L, Files.list(root).use { it.count() })
    }
    @Test fun emptyFilesAreReportedWithoutMutation() = fixture { root, raw, engine ->
        val files = listOf(put(root, "one", ""), put(root, "two", ""))
        val report = OrganizerDuplicates(raw, engine).scan(files)
        assertEquals(0L, report.groups.single().size)
        assertEquals(2, report.groups.single().members.size)
    }
    @Test fun cancellationNeverReturnsAPartialDuplicateReport() = fixture { root, raw, engine ->
        val files = listOf(put(root, "one", "aa"), put(root, "two", "aa"))
        var stop = false
        try {
            OrganizerDuplicates(raw, engine).scan(files, { stop }) { done, _ -> if (done == 1) stop = true }
            fail("Cancelled scan returned results")
        } catch (_: CancellationException) { /* No partial report is published. */ }
        assertEquals(2L, Files.list(root).use { it.count() })
    }
    @Test fun aSourceChangedAfterHashingInvalidatesTheReport() = fixture { root, raw, engine ->
        val files = listOf(put(root, "one", "aa"), put(root, "two", "aa"))
        try {
            OrganizerDuplicates(raw, engine).scan(files) { done, _ ->
                if (done == 2) Files.setLastModifiedTime(root.resolve("one"), FileTime.fromMillis(1))
            }
            fail("Stale identity accepted")
        } catch (_: IllegalStateException) { /* A report cannot hide a detected source change. */ }
    }
    @Test fun invalidBatchesAreRejectedBeforeStorageAccess() = fixture { root, raw, engine ->
        val one = put(root, "one", "a")
        for (batch in listOf(emptyList(), listOf(one, one), List(501) { one })) {
            try { OrganizerDuplicates(raw, engine).scan(batch); fail("Invalid batch accepted") }
            catch (_: IllegalArgumentException) { /* Bounded and unique handles required. */ }
        }
    }
}
