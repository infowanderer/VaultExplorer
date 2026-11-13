package com.aeidolon.vaultexplorer

/** Provider IDs follow the installed package, including isolated preview builds. */
object ProviderAuthorities {
    val DOCUMENTS = "${BuildConfig.APPLICATION_ID}.documents"
    val SHARE = "${BuildConfig.APPLICATION_ID}.shareprovider"
    val STREAM = "${BuildConfig.APPLICATION_ID}.stream"
}
