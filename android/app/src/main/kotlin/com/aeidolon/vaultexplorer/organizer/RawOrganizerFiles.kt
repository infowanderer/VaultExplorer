package com.aeidolon.vaultexplorer.organizer

import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.channels.Channels
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardOpenOption.*
import java.nio.file.attribute.BasicFileAttributes

/** Raw, user-selected storage only; every media mutation is no-replace. */
class RawOrganizerFiles(
    private val pathIdentity: ((Path) -> String)? = null,
    private val openedIdentity: ((RandomAccessFile) -> String)? = null,
    private val renameNoReplace: ((Path, Path) -> Boolean)? = null,
    private val syncDirectory: ((Path) -> Unit)? = null,
) : OrganizerFiles {
    private fun sync(directory: Path) {
        if (syncDirectory != null) syncDirectory.invoke(directory)
        else FileChannel.open(directory, READ, NOFOLLOW_LINKS).use { it.force(true) }
    }
    private fun path(file: MediaLocation): Path {
        require(!file.root.startsWith("content:"))
        val root = Paths.get(file.root).toRealPath()
        val relative = file.path.trimStart('/')
        require(relative.split('/').none { it == ".." || it == "." }) { "Invalid relative path" }
        val target = root.resolve(relative).normalize()
        require(target.startsWith(root)) { "Path leaves selected storage" }
        var cursor = root
        for (part in root.relativize(target)) {
            cursor = cursor.resolve(part)
            check(!Files.isSymbolicLink(cursor)) { "Symbolic links are not supported for organizer transfers" }
        }
        return target
    }
    override fun stat(file: MediaLocation): MediaVersion {
        val attr = Files.readAttributes(path(file), BasicFileAttributes::class.java, NOFOLLOW_LINKS)
        check(attr.isRegularFile) { "Not a regular file" }
        val identity = pathIdentity?.invoke(path(file)) ?: checkNotNull(attr.fileKey()) { "Storage does not expose a safe file identity" }.toString()
        return MediaVersion(identity, attr.size(), attr.lastModifiedTime().toMillis())
    }
    override fun read(file: MediaLocation): InputStream = Channels.newInputStream(FileChannel.open(path(file), READ, NOFOLLOW_LINKS))
    override fun availableBytes(directory: MediaLocation): Long? = try {
        Files.getFileStore(path(directory)).usableSpace.takeIf { it >= 0 }
    } catch (_: Exception) { null }
    override fun names(directory: MediaLocation): Set<String> {
        val dir = path(directory)
        check(Files.isDirectory(dir, NOFOLLOW_LINKS)) { "Destination folder unavailable" }
        Files.newDirectoryStream(dir).use { return it.map { child -> child.fileName.toString() }.toSet() }
    }
    override fun create(directory: MediaLocation, name: String): MediaLocation {
        require(OrganizerTransfer.validName(name))
        check(names(directory).none { it.equals(name, true) }) { "Destination name already exists" }
        val file = MediaLocation(directory.root, directory.path.trimEnd('/') + "/" + name)
        FileChannel.open(path(file), WRITE, CREATE_NEW, NOFOLLOW_LINKS).use { it.force(true) }
        sync(path(file).parent) // Persist the new name before recording ownership.
        return file
    }
    override fun write(file: MediaLocation, offset: Long, expectedIdentity: String): OutputStream {
        check(stat(file).identity == expectedIdentity) { "Output identity changed" }
        val opened = RandomAccessFile(path(file).toFile(), "rw") // No truncation.
        val channel = opened.channel
        try {
            if (openedIdentity != null) check(openedIdentity.invoke(opened) == expectedIdentity) { "Output was replaced while opening" }
            check(stat(file).identity == expectedIdentity && channel.size() == offset) { "Output changed before writing" }
            channel.position(offset)
        } catch (error: Exception) { opened.close(); throw error }
        val output = Channels.newOutputStream(channel)
        return object : OutputStream() {
            override fun write(b: Int) = output.write(b)
            override fun write(b: ByteArray, off: Int, len: Int) = output.write(b, off, len)
            override fun flush() = channel.force(true)
            override fun close() { try { channel.force(true) } finally { opened.close() } }
        }
    }
    override fun supportsResume(file: MediaLocation) = true
    override fun supportsTrash(file: MediaLocation) = try { Files.isWritable(path(file).parent) } catch (_: Exception) { false }
    override fun trashSlot(file: MediaLocation, id: String): MediaLocation {
        require(id.matches(Regex("[a-zA-Z0-9-]{1,64}")))
        val relativeParent = file.path.substringBeforeLast('/', "").trim('/')
        val trashParent = MediaLocation(file.root, listOf(relativeParent, ".MediaOrganizerTrash").filter { it.isNotEmpty() }.joinToString("/"))
        val trash = path(trashParent)
        if (!Files.exists(trash, NOFOLLOW_LINKS)) {
            Files.createDirectory(trash)
            sync(trash.parent)
        }
        check(Files.isDirectory(trash, NOFOLLOW_LINKS) && !Files.isSymbolicLink(trash)) { "Trash unavailable" }
        val slot = MediaLocation(file.root, trashParent.path + "/" + id)
        Files.createDirectory(path(slot)) // A reserved, unpredictable, empty slot.
        sync(trash) // Persist the slot before it can retain an original.
        return MediaLocation(file.root, slot.path + "/" + file.path.substringAfterLast('/'))
    }
    override fun relocate(source: MediaLocation, target: MediaLocation) {
        val from = path(source); val to = path(target)
        if (renameNoReplace == null) check(Files.getFileStore(from) == Files.getFileStore(to.parent)) { "Trash must be on the source filesystem" }
        check(!Files.exists(to, NOFOLLOW_LINKS)) { "Restore name already exists" }
        // No REPLACE_EXISTING and no ATOMIC_MOVE (whose target-replace behavior
        // is provider-specific). The destination is a reserved private slot.
        if (renameNoReplace != null) check(renameNoReplace.invoke(from, to)) { "Filesystem cannot safely retain or restore this file" }
        else Files.move(from, to)
    }
}
