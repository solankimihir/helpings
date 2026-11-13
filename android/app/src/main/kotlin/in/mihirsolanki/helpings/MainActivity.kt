// `in` is a Kotlin keyword, so the package segment is escaped.
package `in`.mihirsolanki.helpings

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var backupFolder: BackupFolderChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupFolder = BackupFolderChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "helpings/backup_folder")
            .setMethodCallHandler(backupFolder::onMethodCall)
    }

    @Deprecated("Needed by FlutterActivity, which isn't a ComponentActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!backupFolder.onActivityResult(requestCode, resultCode, data)) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}

/**
 * A folder the user picks once (ACTION_OPEN_DOCUMENT_TREE) and the app keeps
 * write access to across restarts via a persisted URI permission. The token
 * handed to Dart is the tree URI. See lib/data/backup_folder.dart.
 */
class BackupFolderChannel(private val activity: Activity) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    private val resolver get() = activity.contentResolver

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pick") return pick(result)
        // Android/data/<package>/files/backups: needs no permission.
        if (call.method == "appFolder") {
            return result.success(activity.getExternalFilesDir("backups")?.absolutePath)
        }
        val token = call.argument<String>("token")
            ?: return result.error("bad_args", "token is required", null)
        val tree = Uri.parse(token)
        io.execute {
            try {
                val value: Any? = when (call.method) {
                    "name" -> displayName(tree)
                    "list" -> children(tree).keys.toList()
                    "write" -> write(
                        tree,
                        call.argument<String>("name")!!,
                        call.argument<ByteArray>("bytes")!!,
                    )
                    "delete" -> delete(tree, call.argument<String>("name")!!)
                    "release" -> release(tree)
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (e: NoAccess) {
                main.post { result.error("no_access", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("io_error", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            return result.error("busy", "A folder picker is already open", null)
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST_PICK)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        io.execute {
            try {
                resolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                val name = displayName(tree)
                main.post { result.success(mapOf("token" to tree.toString(), "name" to name)) }
            } catch (e: Exception) {
                main.post { result.error("io_error", e.message ?: e.toString(), null) }
            }
        }
        return true
    }

    private class NoAccess(message: String) : Exception(message)

    private fun requireAccess(tree: Uri) {
        val granted = resolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }
        if (!granted) {
            throw NoAccess("Helpings no longer has access to the backup folder. Choose it again.")
        }
    }

    private fun folderDoc(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )

    private fun displayName(tree: Uri): String {
        requireAccess(tree)
        resolver.query(folderDoc(tree), arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) return c.getString(0) }
        throw NoAccess("The backup folder can't be found. It may have been deleted.")
    }

    /** Display name -> document URI for files directly in the folder. */
    private fun children(tree: Uri): Map<String, Uri> {
        requireAccess(tree)
        val list = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        val out = linkedMapOf<String, Uri>()
        val cols = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
        )
        val cursor = resolver.query(list, cols, null, null, null)
            ?: throw NoAccess("The backup folder can't be found. It may have been deleted.")
        cursor.use { c ->
            while (c.moveToNext()) {
                if (c.getString(2) == Document.MIME_TYPE_DIR) continue
                out[c.getString(1)] = DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0))
            }
        }
        return out
    }

    private fun write(tree: Uri, name: String, bytes: ByteArray): Any? {
        // Overwrite in place: createDocument would add " (1)" to a duplicate name.
        val existing = children(tree)[name]
        if (existing != null) {
            val out = try {
                resolver.openOutputStream(existing, "wt")
            } catch (_: Exception) {
                null // Some providers (e.g. Drive) don't support truncate.
            }
            if (out != null) {
                out.use { it.write(bytes) }
                return null
            }
            DocumentsContract.deleteDocument(resolver, existing)
        }
        val doc = DocumentsContract.createDocument(
            resolver, folderDoc(tree), "application/octet-stream", name,
        ) ?: throw java.io.IOException("Couldn't create $name")
        (resolver.openOutputStream(doc, "w") ?: throw java.io.IOException("Couldn't open $name"))
            .use { it.write(bytes) }
        return null
    }

    private fun delete(tree: Uri, name: String): Any? {
        children(tree)[name]?.let { DocumentsContract.deleteDocument(resolver, it) }
        return null
    }

    private fun release(tree: Uri): Any? {
        try {
            resolver.releasePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Already gone.
        }
        return null
    }

    companion object {
        private const val REQUEST_PICK = 0x4B55
    }
}
