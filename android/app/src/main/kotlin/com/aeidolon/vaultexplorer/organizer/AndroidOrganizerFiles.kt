package com.aeidolon.vaultexplorer.organizer

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract as Docs
import com.aeidolon.vaultexplorer.saf.SafStorageManager
import java.io.InputStream
import java.io.OutputStream

/** SAF reads/writes use provider descriptors directly; no mirror or temp copy. */
class AndroidOrganizerFiles(private val context: Context, private val saf: SafStorageManager) : OrganizerFiles {
    private val raw = RawOrganizerFiles(
        pathIdentity = { path -> android.system.Os.lstat(path.toString()).let { "${it.st_dev}:${it.st_ino}" } },
        openedIdentity = { file -> android.system.Os.fstat(file.fd).let { "${it.st_dev}:${it.st_ino}" } },
        renameNoReplace = { from, to -> com.aeidolon.vaultexplorer.NativeEngine.organizerRenameNoReplace(
            from.toString().toByteArray(Charsets.UTF_8), to.toString().toByteArray(Charsets.UTF_8)) },
        syncDirectory = ::organizerSyncDirectory,
    )
    private fun isSaf(file: MediaLocation) = file.root.startsWith("content://")
    private fun uri(file: MediaLocation): Uri {
        val root = Uri.parse(file.root)
        // V1 is deliberately local, SD and USB, never a cloud document provider.
        require(root.authority == "com.android.externalstorage.documents") { "Select local, SD or USB storage" }
        require(file.path.split('/').none { it == ".." || it == "." }) { "Invalid relative path" }
        val target = file.uri?.let(Uri::parse) ?: saf.getDocumentUri(root, file.path.trim('/'))
            ?: throw IllegalStateException("Storage document unavailable")
        require(target.authority == root.authority)
        val rootId = Docs.getTreeDocumentId(root)
        val id = if (Docs.isTreeUri(target) && !target.path.orEmpty().contains("/document/")) Docs.getTreeDocumentId(target) else Docs.getDocumentId(target)
        require(id == rootId || id.startsWith(if (rootId.endsWith(":")) rootId else rootId.trimEnd('/') + "/")) { "Document leaves selected storage" }
        return if (target.path.orEmpty().contains("/document/")) target else Docs.buildDocumentUriUsingTree(root, id)
    }
    private data class Document(val uri: Uri, val name: String, val mime: String, val flags: Int, val size: Long, val modified: Long)
    private fun document(file: MediaLocation): Document {
        val target = uri(file)
        val columns = arrayOf(Docs.Document.COLUMN_DISPLAY_NAME, Docs.Document.COLUMN_MIME_TYPE,
            Docs.Document.COLUMN_FLAGS, Docs.Document.COLUMN_SIZE, Docs.Document.COLUMN_LAST_MODIFIED)
        val cursor = context.contentResolver.query(target, columns, null, null, null)
            ?: throw IllegalStateException("Storage query failed")
        cursor.use {
            check(it.moveToFirst()) { "Document missing" }
            return Document(target, it.getString(0), it.getString(1), it.getInt(2),
                if (it.isNull(3)) -1 else it.getLong(3), if (it.isNull(4)) 0 else it.getLong(4))
        }
    }
    private fun children(directory: MediaLocation): Map<String, String> {
        val parent = document(directory)
        check(parent.mime == Docs.Document.MIME_TYPE_DIR) { "Not a destination directory" }
        val childUri = Docs.buildChildDocumentsUriUsingTree(Uri.parse(directory.root), Docs.getDocumentId(parent.uri))
        val cursor = context.contentResolver.query(childUri, arrayOf(Docs.Document.COLUMN_DOCUMENT_ID, Docs.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?: throw IllegalStateException("Folder query failed")
        cursor.use {
            val result = linkedMapOf<String, String>()
            while (it.moveToNext()) result[it.getString(0)] = it.getString(1)
            return result
        }
    }
    override fun stat(file: MediaLocation): MediaVersion {
        if (!isSaf(file)) return raw.stat(file)
        val doc = document(file)
        check(doc.mime != Docs.Document.MIME_TYPE_DIR && doc.flags and Docs.Document.FLAG_VIRTUAL_DOCUMENT == 0) { "Not a readable media document" }
        check(doc.size >= 0) { "Provider reports unknown size" }
        return MediaVersion(doc.uri.authority + ":" + Docs.getDocumentId(doc.uri), doc.size, doc.modified)
    }
    override fun availableBytes(directory: MediaLocation): Long? = if (isSaf(directory)) null else raw.availableBytes(directory)
    override fun names(directory: MediaLocation): Set<String> = if (isSaf(directory)) children(directory).values.toSet() else raw.names(directory)
    override fun read(file: MediaLocation): InputStream = if (!isSaf(file)) raw.read(file) else {
        val descriptor = context.contentResolver.openFileDescriptor(uri(file), "r") ?: error("Cannot open media")
        ParcelFileDescriptor.AutoCloseInputStream(descriptor)
    }
    override fun create(directory: MediaLocation, name: String): MediaLocation {
        if (!isSaf(directory)) return raw.create(directory, name)
        require(OrganizerTransfer.validName(name))
        val parent = document(directory)
        check(parent.flags and Docs.Document.FLAG_DIR_SUPPORTS_CREATE != 0) { "Folder is read-only" }
        val before = children(directory)
        check(before.values.none { it.equals(name, true) }) { "Destination name already exists" }
        val created = Docs.createDocument(context.contentResolver, parent.uri,
            android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase(java.util.Locale.ROOT)) ?: "application/octet-stream", name) ?: error("Document creation refused")
        val id = Docs.getDocumentId(created)
        check(!before.containsKey(id)) { "Provider returned an existing file; write refused" }
        val target = MediaLocation(directory.root, directory.path.trim('/') + "/" + name, created.toString())
        val actual = document(target)
        return target.copy(path = directory.path.trim('/') + "/" + actual.name)
    }
    override fun write(file: MediaLocation, offset: Long, expectedIdentity: String): OutputStream {
        if (!isSaf(file)) return raw.write(file, offset, expectedIdentity)
        require(offset == 0L && stat(file).size == 0L && stat(file).identity == expectedIdentity) { "SAF partial writes cannot be resumed safely" }
        val descriptor = context.contentResolver.openFileDescriptor(uri(file), "w") ?: error("Cannot write new document")
        val output = ParcelFileDescriptor.AutoCloseOutputStream(descriptor)
        return object : OutputStream() {
            override fun write(b: Int) = output.write(b)
            override fun write(b: ByteArray, off: Int, len: Int) = output.write(b, off, len)
            override fun flush() { output.flush(); descriptor.fileDescriptor.sync() }
            override fun close() { try { flush() } finally { output.close() } }
        }
    }
    override fun supportsResume(file: MediaLocation) = !isSaf(file)
    override fun supportsTrash(file: MediaLocation) = !isSaf(file)
    override fun trashSlot(file: MediaLocation, id: String): MediaLocation {
        require(!isSaf(file)) { "This source supports copies only; recoverable Trash is unavailable" }
        return raw.trashSlot(file, id)
    }
    override fun relocate(source: MediaLocation, target: MediaLocation) {
        require(!isSaf(source) && !isSaf(target)) { "Provider cannot safely retain originals" }
        raw.relocate(source, target)
    }
}
