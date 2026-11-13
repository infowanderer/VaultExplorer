package com.aeidolon.vaultexplorer.organizer

import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.handlers.SecureStorageHandlers
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class OrganizerHandlers(private val activity: MainActivity, private val secure: SecureStorageHandlers) {
    companion object {
        private val generation = AtomicLong(0)
        private val workerGeneration = ThreadLocal<Long>()
        fun currentWorkerIsValid(): Boolean = workerGeneration.get() == generation.get()
        fun cancelAll() { cancelled.values.forEach { it.set(true) } }
        fun invalidateSessions() { generation.incrementAndGet(); cancelAll() }
        private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "organizer-transfers").apply { isDaemon = true } }
        private val cancelled = ConcurrentHashMap<String, AtomicBoolean>()
        private val progress = ConcurrentHashMap<String, List<Long>>()
    }
    private fun location(value: Map<*, *>) = MediaLocation(value["root"] as String, value["path"] as String? ?: "", value["uri"] as String?)
    private fun location(value: JSONObject) = MediaLocation(value.getString("root"), value.getString("path"), value.optString("uri").takeIf { it.isNotEmpty() && it != "null" })
    private fun map(value: MediaLocation) = mapOf("root" to value.root, "path" to value.path, "uri" to value.uri)
    private fun map(job: OrganizerJob): Map<String, Any?> = mapOf(
        "version" to 1, "id" to job.id, "source" to map(job.source), "destination" to map(job.destination), "move" to job.move,
        "identity" to job.sourceVersion.identity, "size" to job.sourceVersion.size, "modified" to job.sourceVersion.modified,
        "sha256" to job.sha256, "state" to job.state, "created" to job.created?.let(::map),
        "createdIdentity" to job.createdIdentity, "trash" to job.trash?.let(::map), "message" to job.message,
        "createdAt" to job.createdAt, "annotation" to job.annotation,
        "undoSupported" to (job.created?.root?.startsWith("content://") == false))
    private fun parse(value: String): OrganizerJob {
        val j = JSONObject(value)
        check(j.optInt("version", 1) == 1) { "Unsupported journal version" }
        return OrganizerJob(j.getString("id"), location(j.getJSONObject("source")), location(j.getJSONObject("destination")), j.getBoolean("move"),
            MediaVersion(j.getString("identity"), j.getLong("size"), j.getLong("modified")), j.getString("sha256"), j.getString("state"),
            j.optJSONObject("created")?.let(::location), j.optString("createdIdentity").takeIf { it.isNotEmpty() && it != "null" },
            j.optJSONObject("trash")?.let(::location), j.optString("message").takeIf { it.isNotEmpty() && it != "null" }, j.optLong("createdAt", 0), j.optString("annotation").takeIf { it.isNotEmpty() && it != "null" })
    }
    private val journal = object : OrganizerJournal {
        override fun read(id: String): OrganizerJob {
            require(id.matches(Regex("[a-zA-Z0-9-]{1,64}")))
            return parse(checkNotNull(secure.readOrganizerRecord("organizer_job_" + id))).also { check(it.id == id) { "Journal identity mismatch" } }
        }
        override fun write(job: OrganizerJob) = secure.writeOrganizerRecord("organizer_job_" + job.id, JSONObject(map(job)).toString())
    }
    private val engine by lazy { OrganizerTransfer(AndroidOrganizerFiles(activity, activity.safStorageManager), journal) }
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "organizerCancel") {
            val id = call.argument<String>("id")
            if (id != null) cancelled[id]?.set(true) else cancelAll()
            result.success(true); return
        }
        if (call.method == "organizerProgress") { result.success(progress[call.argument<String>("id")]); return }
        val activeId = when (call.method) {
            "organizerExecute", "organizerUndo", "organizerReconcile" -> call.argument<String>("id")
            "organizerPrepare", "organizerFingerprint" -> java.util.UUID.randomUUID().toString()
            else -> null
        }
        val token = if (activeId != null) AtomicBoolean(false) else null
        if (activeId != null && cancelled.putIfAbsent(activeId, token!!) != null) {
            result.error("ORGANIZER_BUSY", "This operation is already active", null); return
        }
        val requestGeneration = generation.get()
        worker.execute {
            workerGeneration.set(requestGeneration)
            try {
                check(currentWorkerIsValid()) { "Organizer session expired" }
                val value: Any? = when (call.method) {
                    "organizerFingerprint" -> {
                        val (version, hash) = engine.fingerprint(location(checkNotNull(call.argument<Map<*, *>>("source"))), { token!!.get() })
                        mapOf("identity" to version.identity, "size" to version.size, "modified" to version.modified, "sha256" to hash)
                    }
                    "organizerChooseFolder" -> {
                        val rawPath = call.argument<String>("path")
                        val tree = call.argument<String>("treeUri")
                        val rawOkay = rawPath != null && try {
                            val path = java.nio.file.Paths.get(rawPath).toRealPath()
                            java.nio.file.Files.isDirectory(path) && java.nio.file.Files.isReadable(path) && java.nio.file.Files.isWritable(path)
                        } catch (_: Exception) { false }
                        val root = if (rawOkay) checkNotNull(rawPath) else checkNotNull(tree)
                        AndroidOrganizerFiles(activity, activity.safStorageManager).names(MediaLocation(root, ""))
                        root
                    }
                    "organizerInspect" -> {
                        val files = AndroidOrganizerFiles(activity, activity.safStorageManager)
                        val source = location(checkNotNull(call.argument<Map<*, *>>("source")))
                        val value = files.stat(source)
                        mapOf("identity" to value.identity, "size" to value.size, "modified" to value.modified, "canMove" to files.supportsTrash(source))
                    }
                    "organizerPrepare" -> {
                        check(secure.organizerRecordKeys().size < 2000) { "Operation history limit reached; archive history before adding more" }
                        val expected = call.argument<Map<*, *>>("expected")?.let {
                            MediaVersion(it["identity"] as String, (it["size"] as Number).toLong(), (it["modified"] as Number).toLong())
                        }
                        map(engine.prepare(location(checkNotNull(call.argument<Map<*, *>>("source"))),
                            location(checkNotNull(call.argument<Map<*, *>>("directory"))), checkNotNull(call.argument<String>("name")), call.argument<Boolean>("move") == true, expected, call.argument<Map<*, *>>("annotation")?.let { JSONObject(it).toString() }, call.argument<String>("annotationHash"), { token!!.get() }))
                    }
                    "organizerList" -> secure.organizerRecordKeys().sorted().map { key ->
                        val record = parse(checkNotNull(secure.readOrganizerRecord(key)))
                        check(key == "organizer_job_" + record.id) { "Journal identity mismatch" }
                        map(record)
                    }
                    "organizerExecute" -> {
                        val id = checkNotNull(activeId)
                        map(engine.execute(id, { token!!.get() }) { done, total -> progress[id] = listOf(done, total) })
                    }
                    "organizerReconcile" -> map(engine.reconcile(checkNotNull(activeId), { token!!.get() }))
                    "organizerUndo" -> map(engine.undo(checkNotNull(activeId), { token!!.get() }))
                    else -> error("Unknown organizer operation")
                }
                activity.runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                if (error !is Exception && error !is LinkageError) throw error
                // No exception text or media paths enter logs/platform error reports.
                activity.runOnUiThread { result.error("ORGANIZER_REFUSED", "Storage changed, a name is occupied, protected storage is unavailable, or this provider cannot safely perform the operation. Originals and recorded partial outputs are retained.", null) }
            } finally {
                if (activeId != null) { cancelled.remove(activeId, token); progress.remove(activeId) }
                workerGeneration.remove()
            }
        }
    }
}
