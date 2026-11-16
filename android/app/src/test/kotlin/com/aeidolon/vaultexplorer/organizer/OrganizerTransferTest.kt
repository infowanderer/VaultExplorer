package com.aeidolon.vaultexplorer.organizer

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime

class OrganizerTransferTest {
    @Test fun interruptedUndoCannotBeReclassifiedAsForwardTransfer() = fixture { dir, raw, journal, engine ->
        val src = source(dir); val dst = destination(dir)
        val completed = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        var relocations = 0
        val interruptedFiles = object : OrganizerFiles by raw {
            override fun relocate(source: MediaLocation, target: MediaLocation) {
                if (++relocations == 2) throw java.util.concurrent.CancellationException()
                raw.relocate(source, target)
            }
        }
        try { OrganizerTransfer(interruptedFiles, journal).undo(completed.id); fail("Expected interrupted undo") }
        catch (_: java.util.concurrent.CancellationException) { /* Original restored, output still in place. */ }
        assertEquals("undoing", journal.read(completed.id).state)
        repeat(3) {
            val reconciled = OrganizerTransfer(raw, journal).reconcile(completed.id)
            assertEquals("undoing", reconciled.state)
            assertTrue(Files.exists(dir.resolve("photo.jpg")))
            assertTrue(Files.exists(dir.resolve("keep/photo.jpg")))
        }
        try { engine.execute(completed.id); fail("An interrupted undo must not resume forward") }
        catch (_: IllegalArgumentException) { /* Forward execution remains blocked. */ }
    }

    @Test fun interruptedUndoRemainsReconciliableAfterStorageReturns() = fixture { dir, raw, journal, engine ->
        val src = source(dir); val dst = destination(dir)
        val completed = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        var relocations = 0
        val interruptedFiles = object : OrganizerFiles by raw {
            override fun relocate(source: MediaLocation, target: MediaLocation) {
                raw.relocate(source, target)
                if (++relocations == 2) throw java.util.concurrent.CancellationException()
            }
        }
        try { OrganizerTransfer(interruptedFiles, journal).undo(completed.id); fail("Expected interrupted undo") }
        catch (_: java.util.concurrent.CancellationException) { /* Both renames completed, final journal commit did not. */ }
        val unavailable = object : OrganizerFiles by raw {
            override fun stat(file: MediaLocation): MediaVersion = throw java.io.IOException("Disconnected fixture")
        }
        assertEquals("undoing", OrganizerTransfer(unavailable, journal).reconcile(completed.id).state)
        assertEquals("undone", OrganizerTransfer(raw, journal).reconcile(completed.id).state)
        assertTrue(Files.exists(dir.resolve("photo.jpg")))
        assertFalse(Files.exists(dir.resolve("keep/photo.jpg")))
    }
    private class Journal : OrganizerJournal {
        val jobs = linkedMapOf<String, OrganizerJob>()
        var fail = false
        override fun read(id: String) = checkNotNull(jobs[id])
        override fun write(job: OrganizerJob) { check(!fail) { "Keystore unavailable" }; jobs[job.id] = job.copy() }
    }
    private fun fixture(action: (Path, RawOrganizerFiles, Journal, OrganizerTransfer) -> Unit) {
        val dir = Files.createTempDirectory("organizer-synthetic-")
        try { val files = RawOrganizerFiles(); val journal = Journal(); action(dir, files, journal, OrganizerTransfer(files, journal)) }
        finally { dir.toFile().deleteRecursively() }
    }
    private fun source(dir: Path, bytes: ByteArray = "vacation fixture".toByteArray()): MediaLocation {
        Files.write(dir.resolve("photo.jpg"), bytes); return MediaLocation(dir.toString(), "photo.jpg")
    }
    private fun destination(dir: Path): MediaLocation { Files.createDirectory(dir.resolve("keep")); return MediaLocation(dir.toString(), "keep") }
    @Test fun copyVerifiesAndUndoRetainsEveryByteInTrash() = fixture { dir, files, journal, engine ->
        val src = source(dir); val dst = destination(dir)
        val plan = engine.prepare(src, dst, "photo.jpg", false)
        val done = engine.execute(plan.id)
        assertEquals("complete", done.state); assertArrayEquals(Files.readAllBytes(dir.resolve("photo.jpg")), Files.readAllBytes(dir.resolve("keep/photo.jpg")))
        val undo = engine.undo(plan.id)
        assertEquals("undone", undo.state); assertTrue(Files.exists(dir.resolve("photo.jpg")))
        assertFalse(Files.exists(dir.resolve("keep/photo.jpg")))
        assertArrayEquals(Files.readAllBytes(dir.resolve("photo.jpg")), Files.readAllBytes(dir.resolve(undo.destination.path)))
        assertEquals(done.sha256, journal.read(plan.id).sha256)
    }
    @Test fun moveRetainsOriginalAndUndoRestoresWithoutDeletion() = fixture { dir, _, _, engine ->
        val src = source(dir); val dst = destination(dir)
        val done = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        assertEquals("complete", done.state); assertFalse(Files.exists(dir.resolve("photo.jpg")))
        assertTrue(Files.exists(dir.resolve(done.trash!!.path)))
        val undo = engine.undo(done.id)
        assertEquals("undone", undo.state); assertTrue(Files.exists(dir.resolve("photo.jpg")))
        assertTrue(Files.exists(dir.resolve(undo.destination.path)))
    }
    @Test fun collisionsIncludingCaseVariantsNeverOverwrite() = fixture { dir, _, _, engine ->
        val src = source(dir); val dst = destination(dir); Files.write(dir.resolve("keep/PHOTO.JPG"), byteArrayOf(9))
        try { engine.prepare(src, dst, "photo.jpg", false); fail("collision accepted") } catch (_: IllegalStateException) {}
        assertArrayEquals(byteArrayOf(9), Files.readAllBytes(dir.resolve("keep/PHOTO.JPG")))
        assertTrue(Files.exists(dir.resolve("photo.jpg")))
    }
    @Test fun changedSameSizeSourceWithRestoredTimestampIsRefused() = fixture { dir, _, _, engine ->
        val src = source(dir, byteArrayOf(1,2,3)); val dst = destination(dir)
        val plan = engine.prepare(src, dst, "photo.jpg", true); val time = Files.getLastModifiedTime(dir.resolve("photo.jpg"))
        Files.write(dir.resolve("photo.jpg"), byteArrayOf(4,5,6)); Files.setLastModifiedTime(dir.resolve("photo.jpg"), time)
        assertEquals("interrupted", engine.execute(plan.id).state)
        assertFalse(Files.exists(dir.resolve("keep/photo.jpg")))
        assertArrayEquals(byteArrayOf(4,5,6), Files.readAllBytes(dir.resolve("photo.jpg")))
    }
    @Test fun cancellationIsResumableAcrossEngineInstancesWithVerifiedPrefix() = fixture { dir, files, journal, engine ->
        val bytes = ByteArray(OrganizerTransfer.BUFFER * 3 + 17) { (it % 251).toByte() }
        val src = source(dir, bytes); val dst = destination(dir); val plan = engine.prepare(src, dst, "photo.jpg", true)
        var copied = false
        val paused = engine.execute(plan.id, { copied }) { _, _ -> copied = true }
        assertEquals("interrupted", paused.state); assertTrue(Files.exists(dir.resolve("photo.jpg")))
        assertEquals(OrganizerTransfer.BUFFER.toLong(), Files.size(dir.resolve("keep/photo.jpg")))
        val recovered = OrganizerTransfer(files, journal).execute(plan.id)
        assertEquals("complete", recovered.state); assertArrayEquals(bytes, Files.readAllBytes(dir.resolve("keep/photo.jpg")))
        assertArrayEquals(bytes, Files.readAllBytes(dir.resolve(recovered.trash!!.path)))
    }
    @Test fun modifiedPartialAndEditedDestinationRefuseResumeAndUndo() = fixture { dir, _, _, engine ->
        val src = source(dir, ByteArray(OrganizerTransfer.BUFFER * 2) { 2 }); val dst = destination(dir)
        val plan = engine.prepare(src, dst, "photo.jpg", false); var stop = false
        engine.execute(plan.id, { stop }) { _, _ -> stop = true }
        val target = dir.resolve("keep/photo.jpg"); Files.write(target, byteArrayOf(9))
        assertEquals("interrupted", engine.execute(plan.id).state)
        assertArrayEquals(byteArrayOf(9), Files.readAllBytes(target))
        val second = engine.execute(engine.prepare(src, dst, "another.jpg", false).id)
        Files.write(dir.resolve("keep/another.jpg"), byteArrayOf(8))
        try { engine.undo(second.id); fail("edited output removed") } catch (_: IllegalStateException) {}
        assertArrayEquals(byteArrayOf(8), Files.readAllBytes(dir.resolve("keep/another.jpg")))
    }
    @Test fun protectedJournalFailurePreventsFileMutation() = fixture { dir, _, journal, engine ->
        val src = source(dir); val dst = destination(dir); journal.fail = true
        try { engine.prepare(src, dst, "photo.jpg", true); fail("unprotected operation accepted") } catch (_: IllegalStateException) {}
        assertEquals(0L, Files.list(dir.resolve("keep")).use { it.count() })
        assertTrue(Files.exists(dir.resolve("photo.jpg")))
    }
    @Test fun createRaceCannotTruncateAnExistingFile() = fixture { dir, raw, journal, _ ->
        val src = source(dir); val dst = destination(dir)
        val racing = object : OrganizerFiles by raw {
            override fun create(directory: MediaLocation, name: String): MediaLocation {
                Files.write(dir.resolve("keep/photo.jpg"), byteArrayOf(99))
                return raw.create(directory, name)
            }
        }
        val engine = OrganizerTransfer(racing, journal); val plan = engine.prepare(src, dst, "photo.jpg", true)
        assertEquals("needsReview", engine.execute(plan.id).state)
        assertArrayEquals(byteArrayOf(99), Files.readAllBytes(dir.resolve("keep/photo.jpg")))
        assertTrue(Files.exists(dir.resolve("photo.jpg")))
    }
    @Test fun zeroByteAndOccupiedUndoAreHandledSafely() = fixture { dir, _, _, engine ->
        val src = source(dir, byteArrayOf()); val dst = destination(dir)
        val done = engine.execute(engine.prepare(src, dst, "empty.jpg", true).id)
        assertEquals("complete", done.state); assertEquals(0L, Files.size(dir.resolve("keep/empty.jpg")))
        Files.write(dir.resolve("photo.jpg"), byteArrayOf(7))
        try { engine.undo(done.id); fail("occupied original replaced") } catch (_: IllegalStateException) {}
        assertArrayEquals(byteArrayOf(7), Files.readAllBytes(dir.resolve("photo.jpg")))
        assertTrue(Files.exists(dir.resolve(done.trash!!.path)))
    }
    @Test fun traversalAndSymbolicLinkDestinationsAreRefused() = fixture { dir, raw, _, engine ->
        val src = source(dir); val outside = Files.createTempDirectory("organizer-outside-")
        try {
            Files.createSymbolicLink(dir.resolve("linked"), outside)
            try { raw.names(MediaLocation(dir.toString(), "../")); fail("traversal accepted") } catch (_: IllegalArgumentException) {}
            try { engine.prepare(src, MediaLocation(dir.toString(), "linked"), "photo.jpg", false); fail("symlink accepted") } catch (_: IllegalStateException) {}
            assertEquals(0L, Files.list(outside).use { it.count() })
        } finally { outside.toFile().deleteRecursively() }
    }
    @Test fun reconciliationVerifiesAnInterruptedMoveWithoutReplayingFileActions() = fixture { dir, files, journal, engine ->
        val src = source(dir); val dst = destination(dir)
        val done = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        journal.jobs[done.id] = done.copy(state = "quarantining") // Crash before completion acknowledgement.
        val snapshot = Files.walk(dir).use { stream -> stream.map { dir.relativize(it).toString() }.sorted().toList() }
        assertEquals("complete", OrganizerTransfer(files, journal).reconcile(done.id).state)
        assertEquals(snapshot, Files.walk(dir).use { stream -> stream.map { dir.relativize(it).toString() }.sorted().toList() })
    }
    @Test fun modifiedSourceDuringQuarantineIsRestoredAndReported() = fixture { dir, raw, journal, _ ->
        val src = source(dir); val dst = destination(dir)
        val changing = object : OrganizerFiles by raw {
            override fun relocate(source: MediaLocation, target: MediaLocation) {
                if (source.path == "photo.jpg") Files.write(dir.resolve("photo.jpg"), "changed bytes".toByteArray())
                raw.relocate(source, target)
            }
        }
        val engine = OrganizerTransfer(changing, journal)
        val failed = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        assertEquals("needsReview", failed.state)
        assertArrayEquals("changed bytes".toByteArray(), Files.readAllBytes(dir.resolve("photo.jpg")))
        assertArrayEquals("vacation fixture".toByteArray(), Files.readAllBytes(dir.resolve("keep/photo.jpg")))
    }
    @Test fun reviewAnnotationCannotFollowDifferentFileContents() = fixture { dir, _, _, engine ->
        val src = source(dir); val dst = destination(dir)
        val hash = engine.fingerprint(src).second
        val valid = engine.prepare(src, dst, "noted.jpg", false, annotation = "saved review", annotationHash = hash)
        assertEquals("saved review", valid.annotation)
        val invalid = engine.prepare(src, dst, "other.jpg", false, annotation = "stale review", annotationHash = "0".repeat(64))
        assertNull(invalid.annotation)
    }
    @Test fun interruptedUndoAcknowledgementCanBeReconciledWithoutMovingAgain() = fixture { dir, files, journal, engine ->
        val src = source(dir); val dst = destination(dir)
        val done = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        val undo = engine.undo(done.id)
        journal.jobs[done.id] = undo.copy(state = "undoing")
        assertEquals("undone", OrganizerTransfer(files, journal).reconcile(done.id).state)
        assertTrue(Files.exists(dir.resolve("photo.jpg")))
        assertTrue(Files.exists(dir.resolve(undo.destination.path)))
    }

    @Test fun knownInsufficientSpaceRefusesBeforeOutputCreation() = fixture { dir, raw, journal, _ ->
        val src = source(dir); val dst = destination(dir)
        val full = object : OrganizerFiles by raw { override fun availableBytes(directory: MediaLocation) = 0L }
        try { OrganizerTransfer(full, journal).prepare(src, dst, "photo.jpg", true); fail("full destination accepted") } catch (_: IllegalStateException) {}
        assertTrue(journal.jobs.isEmpty()); assertTrue(Files.exists(dir.resolve("photo.jpg")))
        assertFalse(Files.exists(dir.resolve("keep/photo.jpg")))
    }

    @Test fun outputDirectorySyncFailureRetainsOriginalAndRefusesOwnership() = fixture { dir, _, journal, _ ->
        val src = source(dir); val dst = destination(dir)
        val files = RawOrganizerFiles(syncDirectory = { throw java.io.IOException("fixture directory sync refused") })
        val engine = OrganizerTransfer(files, journal)
        val job = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        assertEquals("needsReview", job.state); assertNull(job.created)
        assertArrayEquals("vacation fixture".toByteArray(), Files.readAllBytes(dir.resolve("photo.jpg")))
        assertEquals(0L, Files.size(dir.resolve("keep/photo.jpg")))
    }

    @Test fun trashDirectorySyncFailureNeverQuarantinesOriginal() = fixture { dir, _, journal, _ ->
        val src = source(dir); val dst = destination(dir)
        val files = RawOrganizerFiles(syncDirectory = { path ->
            if (path.fileName.toString() == ".MediaOrganizerTrash") throw java.io.IOException("fixture directory sync refused")
            java.nio.channels.FileChannel.open(path, java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        })
        val engine = OrganizerTransfer(files, journal)
        val job = engine.execute(engine.prepare(src, dst, "photo.jpg", true).id)
        assertEquals("interrupted", job.state); assertNull(job.trash)
        assertArrayEquals("vacation fixture".toByteArray(), Files.readAllBytes(dir.resolve("photo.jpg")))
        assertArrayEquals("vacation fixture".toByteArray(), Files.readAllBytes(dir.resolve("keep/photo.jpg")))
    }

}
