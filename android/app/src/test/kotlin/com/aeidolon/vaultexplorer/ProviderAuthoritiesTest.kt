package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.container.ContainerDocumentsProvider
import com.aeidolon.vaultexplorer.container.ContainerShareProvider
import com.aeidolon.vaultexplorer.streaming.VaultStreamProvider
import org.junit.Assert.assertEquals
import org.junit.Test

class ProviderAuthoritiesTest {
    @Test fun `provider authorities belong to the built application package`() {
        assertEquals("${BuildConfig.APPLICATION_ID}.documents", ProviderAuthorities.DOCUMENTS)
        assertEquals("${BuildConfig.APPLICATION_ID}.shareprovider", ProviderAuthorities.SHARE)
        assertEquals("${BuildConfig.APPLICATION_ID}.stream", ProviderAuthorities.STREAM)
    }
    @Test fun `provider entrypoints use the shared authorities`() {
        assertEquals(ProviderAuthorities.DOCUMENTS, ContainerDocumentsProvider.AUTHORITY)
        assertEquals(ProviderAuthorities.SHARE, ContainerShareProvider.AUTHORITY)
        assertEquals(ProviderAuthorities.STREAM, VaultStreamProvider.AUTHORITY)
    }
}
