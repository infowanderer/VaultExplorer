package com.aeidolon.vaultexplorer.privacy

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/** Bounded, seekable-by-reopening vault reads. Never creates a file or falls back to disk. */
class VaultReadInputStream(
    private val size: Long,
    private val readChunk: (Long, Int) -> ByteArray?,
    private val maxChunk: Int = 256 * 1024,
) : InputStream() {
    init { require(size >= 0); require(maxChunk > 0) }
    var position = 0L
        private set
    private var marked = 0L
    private var closed = false
    private fun ensureOpen() { if (closed) throw IOException("Vault stream is closed") }
    override fun read(): Int {
        val one = ByteArray(1)
        return try { if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 255 }
        finally { one.fill(0) }
    }
    override fun read(b: ByteArray, off: Int, len: Int): Int {
        ensureOpen()
        if (off < 0 || len < 0 || off > b.size - len) throw IndexOutOfBoundsException()
        if (len == 0) return 0
        if (position == size) return -1
        val wanted = minOf(len.toLong(), maxChunk.toLong(), size - position).toInt()
        val chunk = readChunk(position, wanted) ?: throw IOException("Vault read failed")
        try {
            if (chunk.isEmpty() || chunk.size > wanted) throw IOException("Invalid vault read length")
            chunk.copyInto(b, off)
            position += chunk.size
            return chunk.size
        } finally { chunk.fill(0) }
    }
    override fun skip(n: Long): Long {
        ensureOpen()
        val count = minOf(n.coerceAtLeast(0), size - position)
        position += count
        return count
    }
    override fun available(): Int { ensureOpen(); return minOf(size - position, Int.MAX_VALUE.toLong()).toInt() }
    override fun markSupported() = true
    override fun mark(readlimit: Int) { marked = position }
    override fun reset() { ensureOpen(); position = marked }
    override fun close() { closed = true }
}

/** Copies only to the explicitly supplied destination, with no plaintext staging. */
object VaultStreamTransfer {
    fun copy(
        size: Long,
        readChunk: (Long, Int) -> ByteArray?,
        output: OutputStream,
        checkCancelled: () -> Unit = {},
        onProgress: (Long) -> Unit = {},
    ): Long {
        checkCancelled()
        val buffer = ByteArray(256 * 1024)
        try {
            VaultReadInputStream(size, readChunk).use { input ->
                while (true) {
                    checkCancelled()
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    onProgress(count.toLong())
                }
                checkCancelled()
                output.flush()
                return input.position
            }
        } finally { buffer.fill(0) }
    }
}
