package com.alexgodly.mediaflow

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import androidx.webkit.JavaScriptReplyProxy
import org.json.JSONObject
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Android Storage Access Framework bridge for v507's automatic folder backups.
 * This NEVER reads/writes Supabase. The website supplies its canonical full JSON backup.
 * All write messages are scoped to the main MediaFlow appassets HTTPS origin by the host.
 */
internal class NativeBackupBridge(private val activity: Activity) {
    companion object { const val PICK_DIRECTORY = 7102 }
    private val prefs = activity.getSharedPreferences("mediaflow_android_backup_destination", Activity.MODE_PRIVATE)
    private val executor = Executors.newSingleThreadExecutor()
    private val maxBytes = 750_000_000L
    @Volatile private var waitingPicker: Pair<Int, JavaScriptReplyProxy>? = null

    private data class Session(
        val token: String,
        val folder: DocumentFile,
        val staged: DocumentFile,
        val name: String,
        val output: OutputStream,
        var size: Long = 0
    )

    // Owned only by the single-thread executor.
    private var session: Session? = null

    fun handle(message: JSONObject, reply: JavaScriptReplyProxy) {
        val id = message.optInt("id", -1)
        when (message.optString("kind")) {
            "choose" -> {
                activity.runOnUiThread {
                    if (waitingPicker != null) {
                        response(reply, id, false, "Folder picker already open")
                        return@runOnUiThread
                    }
                    waitingPicker = id to reply
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                        }
                        activity.startActivityForResult(intent, PICK_DIRECTORY)
                    } catch (error: Exception) {
                        waitingPicker = null
                        response(reply, id, false, error.message ?: "Cannot open folder picker")
                    }
                }
            }
            "status", "begin", "chunk", "finish", "abort" -> executor.execute {
                try {
                    val result = when (message.optString("kind")) {
                        "status" -> status()
                        "begin" -> begin(message)
                        "chunk" -> chunk(message)
                        "finish" -> finish(message)
                        "abort" -> { abort(message); JSONObject() }
                        else -> JSONObject()
                    }
                    respond(reply, JSONObject().put("id", id).put("ok", true).put("result", result))
                } catch (error: Exception) {
                    if (message.optString("kind") != "status") discard()
                    response(reply, id, false, error.message ?: "Backup write failed")
                }
            }
            else -> response(reply, id, false, "Unsupported backup operation")
        }
    }

    fun onFolderPickerResult(resultCode: Int, data: Intent?) {
        val waiting = waitingPicker ?: return
        waitingPicker = null
        val (id, reply) = waiting
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            response(reply, id, false, "Folder selection cancelled", "cancelled")
            return
        }
        try {
            val uri = data.data!!
            val take = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.takePersistableUriPermission(uri, take)
            val folder = DocumentFile.fromTreeUri(activity, uri)
            if (folder == null || !folder.isDirectory || !folder.canWrite()) {
                throw IllegalStateException("The selected folder is not writable")
            }
            prefs.edit().putString("treeUri", uri.toString()).apply()
            respond(reply, JSONObject().put("id", id).put("ok", true).put("result", status()))
        } catch (error: Exception) {
            response(reply, id, false, error.message ?: "Cannot access selected folder")
        }
    }

    private fun folder(): DocumentFile? {
        val saved = prefs.getString("treeUri", null) ?: return null
        val uri = try { Uri.parse(saved) } catch (_: Exception) { return null }
        val hasGrant = activity.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
        if (!hasGrant) return null
        val document = DocumentFile.fromTreeUri(activity, uri)
        return document?.takeIf { it.isDirectory && it.canWrite() }
    }

    private fun status(): JSONObject {
        val folder = folder()
        return JSONObject().put("selected", folder != null)
            .put("name", folder?.name ?: "")
    }

    private fun sanitizedName(raw: String): String {
        val name = raw.trim().replace(Regex("[^a-zA-Z0-9._ -]"), "_")
            .take(120).trim('.', ' ').ifBlank { "mediaflow-backup" }
        return if (name.endsWith(".json", true)) name else "$name.json"
    }

    private fun begin(request: JSONObject): JSONObject {
        if (session != null) throw IllegalStateException("Another backup is still being written")
        val dir = folder() ?: throw IllegalStateException("Choose a writable backup folder first")
        val name = sanitizedName(request.optString("name"))
        val token = UUID.randomUUID().toString()
        val staged = dir.createFile("application/octet-stream", ".mediaflow-$token.partial")
            ?: throw IllegalStateException("Could not create temporary backup in this folder")
        try {
            val stream = activity.contentResolver.openOutputStream(staged.uri, "wt")
                ?: throw IllegalStateException("Could not open temporary backup")
            session = Session(token, dir, staged, name, stream)
        } catch (error: Exception) {
            staged.delete()
            throw error
        }
        return JSONObject().put("token", token)
    }

    private fun sessionFor(request: JSONObject): Session {
        val active = session ?: throw IllegalStateException("No backup write is active")
        if (request.optString("token") != active.token) throw SecurityException("Invalid backup token")
        return active
    }

    private fun chunk(request: JSONObject): JSONObject {
        val active = sessionFor(request)
        val encoded = request.optString("data")
        if (encoded.length > 100_000) throw IllegalArgumentException("Backup chunk exceeds safe size")
        val bytes = Base64.decode(encoded, Base64.DEFAULT)
        if (active.size + bytes.size > maxBytes) throw IllegalArgumentException("Backup exceeds 750 MB limit")
        active.output.write(bytes)
        active.size += bytes.size
        return JSONObject().put("bytes", active.size)
    }

    private fun finish(request: JSONObject): JSONObject {
        val active = sessionFor(request)
        val expected = request.optLong("bytes", -1)
        if (expected != active.size || expected <= 0L) throw IllegalStateException("Incomplete backup transfer")
        active.output.flush()
        active.output.close()

        // Stage to a second file first, so an existing backup isn't lost by a
        // failed or interrupted JSON write. SAF providers vary in rename support.
        val old = active.folder.findFile(active.name)
        val oldOldName = active.name + ".previous-" + active.token
        if (old != null && !old.renameTo(oldOldName)) {
            throw IllegalStateException("Storage provider cannot safely replace existing backup")
        }
        if (!active.staged.renameTo(active.name)) {
            if (old != null) old.renameTo(active.name)
            throw IllegalStateException("Storage provider cannot finalize backup filename")
        }
        if (old != null && old.uri != active.staged.uri) old.delete()
        session = null
        return JSONObject().put("bytes", active.size).put("name", active.name)
    }

    private fun abort(request: JSONObject) {
        sessionFor(request)
        discard()
    }

    private fun discard() {
        val active = session ?: return
        session = null
        try { active.output.close() } catch (_: Exception) {}
        try { active.staged.delete() } catch (_: Exception) {}
    }

    private fun response(reply: JavaScriptReplyProxy, id: Int, ok: Boolean, error: String, code: String = "") {
        respond(reply, JSONObject().put("id", id).put("ok", ok).put("error", error).put("code", code))
    }

    private fun respond(reply: JavaScriptReplyProxy, message: JSONObject) {
        activity.runOnUiThread { reply.postMessage(message.toString()) }
    }

    fun close() {
        executor.execute { discard() }
        executor.shutdown()
    }
}
