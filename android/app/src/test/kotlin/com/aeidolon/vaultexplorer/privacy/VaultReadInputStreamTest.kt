package com.aeidolon.vaultexplorer.privacy

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream

class VaultReadInputStreamTest {
    private val data = ByteArray(1000) { (it % 251).toByte() }
    private fun source(offset: Long, length: Int) =
        data.copyOfRange(offset.toInt(), minOf(data.size, offset.toInt() + length))
    private fun fails(block: () -> Unit) {
        try { block(); fail("Expected IOException") } catch (_: IOException) {}
    }
    @Test fun streamsExactlyWithBoundedReadsAndWipesChunks() {
        val requests = mutableListOf<Int>(); val returned = mutableListOf<ByteArray>()
        val input = VaultReadInputStream(data.size.toLong(), { offset, length ->
            requests += length; source(offset,length).also { returned += it }
        }, 17)
        input.use { assertArrayEquals(data, it.readBytes()) }
        assertTrue(requests.all { it in 1..17 })
        assertTrue(returned.all { a -> a.all { it == 0.toByte() } })
    }
    @Test fun markResetAndSkipSupportTwoPassImageDecoding() {
        VaultReadInputStream(data.size.toLong(), ::source).use {
            assertEquals(0, it.read()); it.mark(5)
            assertEquals(1, it.read()); it.reset(); assertEquals(1, it.read())
            assertEquals(998, it.skip(Long.MAX_VALUE)); assertEquals(-1,it.read())
            assertEquals(0,it.read(ByteArray(0),0,0)); assertEquals(0,it.skip(-1))
        }
    }
    @Test fun failedEmptyAndOversizedReadsCannotLookLikeSuccessfulEof() {
        fails { VaultReadInputStream(5, {_,_->null}).read() }
        fails { VaultReadInputStream(5, {_,_->byteArrayOf()}).read() }
        fails { VaultReadInputStream(5, {_,_->ByteArray(20)}).read() }
    }
    @Test fun shortChunksAreContinuedInsteadOfTruncating() {
        val output = ByteArrayOutputStream()
        val n = VaultStreamTransfer.copy(data.size.toLong(), {offset,length -> source(offset,minOf(7,length))}, output)
        assertEquals(data.size.toLong(), n); assertArrayEquals(data,output.toByteArray())
    }
    @Test fun outputFailurePropagatesAndTransferBufferIsWiped() {
        var held: ByteArray? = null
        val output = object: OutputStream() {
            override fun write(value: Int) { throw IOException("full") }
            override fun write(bytes: ByteArray, off: Int, len: Int) { held=bytes; throw IOException("full") }
        }
        fails { VaultStreamTransfer.copy(data.size.toLong(),::source,output) }
        assertNotNull(held); assertTrue(held!!.all {it==0.toByte()})
    }
    @Test fun cancellationStopsBeforeAnyWrites() {
        val output=ByteArrayOutputStream()
        fails { VaultStreamTransfer.copy(data.size.toLong(),::source,output,
            checkCancelled={throw IOException("cancelled")}) }
        assertEquals(0,output.size())
    }
    @Test fun cancellationBetweenChunksStopsTransfer() {
        val output=ByteArrayOutputStream();var checks=0
        fails { VaultStreamTransfer.copy(800000,{_,len->ByteArray(len)},output,
            checkCancelled={if(++checks==3)throw IOException("cancelled")}) }
        assertEquals(256*1024,output.size())
    }
    @Test fun emptyFilesWorkWithoutSourceReadsAndFlushIsRequired() {
        val output=ByteArrayOutputStream()
        assertEquals(0, VaultStreamTransfer.copy(0,{_,_->error("no read")},output))
        fails { VaultStreamTransfer.copy(0,{_,_->error("no read")},object:OutputStream(){
            override fun write(value:Int){};override fun flush(){throw IOException("flush")}
        }) }
    }
    @Test fun closedStreamsRejectAccess() {
        val input=VaultReadInputStream(1,::source);input.close();fails {input.read()};fails{input.reset()}
    }
    @Test fun invalidRangesAndSizesAreRejected() {
        try {VaultReadInputStream(-1,::source);fail()}catch(_:IllegalArgumentException){}
        val input=VaultReadInputStream(1,::source)
        try {input.read(ByteArray(2),1,Int.MAX_VALUE);fail()}catch(_:IndexOutOfBoundsException){}
    }
}
