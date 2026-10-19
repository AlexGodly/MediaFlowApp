package com.alexgodly.mediaflow

import android.app.Activity
import android.app.DownloadManager
import android.content.ContentValues
import java.io.OutputStream
import java.util.UUID
import android.webkit.RenderProcessGoneDetail
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ServiceWorkerControllerCompat
import androidx.webkit.ServiceWorkerClientCompat
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject

/**
 * Android host for the ACTUAL MediaFlow frontend, packaged from a pinned website release.
 * No duplicate application state and no native Supabase writes.
 */
class MediaFlowActivity : Activity() {
    private val appHost = "appassets.androidplatform.net"
    private val homeUrl = "https://appassets.androidplatform.net/assets/www/index.html"
    private val pickerRequestCode = 7101
    private var selectedFiles: android.webkit.ValueCallback<Array<Uri>>? = null
    private lateinit var webView: WebView
    private lateinit var loader: WebViewAssetLoader
    private lateinit var backupBridge: NativeBackupBridge
    private var exportSession: ExportSession? = null
    private data class ExportSession(
        val token: String,
        val uri: Uri,
        val stream: OutputStream,
        val expectedBytes: Long,
        var bytesWritten: Long = 0L
    )
    private val maxExportBytes = 750_000_000L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(9, 12, 20)
        window.navigationBarColor = Color.rgb(9, 12, 20)

        loader = WebViewAssetLoader.Builder()
            .setDomain(appHost)
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        // A service worker must see the same packaged HTTPS assets as regular WebView
        // requests. Without this, v507's PWA shell cannot install or refresh reliably.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.SERVICE_WORKER_BASIC_USAGE) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.SERVICE_WORKER_SHOULD_INTERCEPT_REQUEST)) {
            ServiceWorkerControllerCompat.getInstance().setServiceWorkerClient(
                object : ServiceWorkerClientCompat() {
                    override fun shouldInterceptRequest(request: WebResourceRequest): WebResourceResponse? =
                        loader.shouldInterceptRequest(request.url)
                }
            )
        }

        webView = WebView(this)
        webView.setBackgroundColor(Color.rgb(9, 12, 20))
        webView.isVerticalScrollBarEnabled = false
        webView.overScrollMode = WebView.OVER_SCROLL_NEVER
        webView.layoutParams = ViewGroup.LayoutParams(-1, -1)
        setContentView(webView)

        with(webView.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = false
            allowContentAccess = true
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = android.webkit.WebSettings.LOAD_DEFAULT
            loadsImagesAutomatically = true
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
        }

        backupBridge = NativeBackupBridge(this)

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)

        // Only the first-party main document may export to Android Downloads.
        // There is no addJavascriptInterface exposed to third-party frames.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(
                webView, "MediaFlowNativeFiles", setOf("https://$appHost")
            ) { _, message, origin, isMainFrame, reply ->
                if (isMainFrame && origin.scheme == "https" && origin.host == appHost) {
                    try {
                        handleExportMessage(JSONObject(message.data ?: "{}"), reply)
                    } catch (_: Exception) {
                        discardExport()
                    }
                }
            }
        }

        // SAF folder access is available only to the first-party main-frame document.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(
                webView, "MediaFlowNativeBackup", setOf("https://$appHost")
            ) { _, message, origin, isMainFrame, reply ->
                if (isMainFrame && origin.scheme == "https" && origin.host == appHost) {
                    try { backupBridge.handle(JSONObject(message.data ?: "{}"), reply) }
                    catch (_: Exception) { toast("Android backup operation failed") }
                }
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean {
                // Recover the shell after WebView renderer memory pressure without
                // deleting Android storage or overwriting the Supabase account.
                try { (view?.parent as? ViewGroup)?.removeView(view) } catch (_: Exception) {}
                discardExport()
                recreate()
                return true
            }

            override fun shouldInterceptRequest(
                view: WebView?, request: WebResourceRequest?
            ): WebResourceResponse? =
                request?.let { loader.shouldInterceptRequest(it.url) }

            override fun shouldOverrideUrlLoading(
                view: WebView?, request: WebResourceRequest?
            ): Boolean {
                val url = request?.url ?: return false
                if (url.scheme == "https" && url.host == appHost &&
                    url.path?.startsWith("/assets/www/") == true) return false
                if (url.scheme == "about" || url.scheme == "blob") return false
                // Do not embed remote websites in the privileged app WebView.
                if (url.scheme == "https" || url.scheme == "http" ||
                    url.scheme == "mailto" || url.scheme == "tel") {
                    try { startActivity(Intent(Intent.ACTION_VIEW, url)) }
                    catch (_: Exception) { toast("No app to open this link") }
                    return true
                }
                return true
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: android.webkit.ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                selectedFiles?.onReceiveValue(null)
                selectedFiles = filePathCallback
                return try {
                    val intent = fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "*/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    startActivityForResult(intent, pickerRequestCode)
                    true
                } catch (_: Exception) {
                    selectedFiles?.onReceiveValue(null)
                    selectedFiles = null
                    false
                }
            }
        }

        webView.setDownloadListener(DownloadListener { url, userAgent, disposition, mime, _ ->
            val name = URLUtil.guessFileName(url, disposition, mime).replace(Regex("[^\\w.() -]"), "_").take(120)
            if (url.startsWith("blob:")) {
                // Stream a Blob in bounded chunks; never allocate an entire large
                // cloud backup twice as a Base64 string in Android memory.
                try {
                    val script = assets.open("export-bridge.js").bufferedReader().use { it.readText() }
                        .replace("__BLOB_URL__", JSONObject.quote(url))
                        .replace("__SUGGESTED_NAME__", JSONObject.quote(name))
                    webView.evaluateJavascript(script, null)
                } catch (_: Exception) { toast("MediaFlow export could not start") }
            } else if (url.startsWith("https://")) {
                try {
                    val req = DownloadManager.Request(Uri.parse(url))
                        .setTitle(name)
                        .setMimeType(mime ?: "application/octet-stream")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
                    val cookie = CookieManager.getInstance().getCookie(url)
                    if (!cookie.isNullOrBlank()) req.addRequestHeader("Cookie", cookie)
                    if (!userAgent.isNullOrBlank()) req.addRequestHeader("User-Agent", userAgent)
                    (getSystemService(DOWNLOAD_SERVICE) as DownloadManager).enqueue(req)
                    toast("Download started")
                } catch (_: Exception) { toast("Download failed") }
            }
        })

        if (savedInstanceState != null) {
            if (webView.restoreState(savedInstanceState) == null) webView.loadUrl(homeUrl)
        } else webView.loadUrl(homeUrl)
    }

    private fun handleExportMessage(req: JSONObject, reply: JavaScriptReplyProxy) {
        val requestId = req.optInt("id", -1)
        val ack = JSONObject().put("id", requestId)
        try {
            when (req.optString("kind")) {
                "start" -> {
                    if (exportSession != null) throw IllegalStateException("Another export is active")
                    val size = req.optLong("size", -1L)
                    if (size < 0 || size > maxExportBytes) {
                        throw IllegalArgumentException("This backup exceeds the supported export size")
                    }
                    val mime = req.optString("mime", "application/octet-stream").take(120)
                    val fileName = req.optString("name", "MediaFlow-export.json")
                        .replace(Regex("[^\\w.() -]"), "_").take(120)
                        .ifEmpty { "MediaFlow-export.json" }
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                        put(MediaStore.Downloads.MIME_TYPE, mime)
                        put(MediaStore.Downloads.IS_PENDING, 1)
                        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/")
                    }
                    val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Could not create Download entry")
                    val stream = try {
                        contentResolver.openOutputStream(uri)
                            ?: throw IllegalStateException("Could not open Download output")
                    } catch (error: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw error
                    }
                    val token = UUID.randomUUID().toString()
                    exportSession = ExportSession(token, uri, stream, size)
                    ack.put("token", token)
                }
                "chunk" -> {
                    val session = exportSession ?: throw IllegalStateException("No active export")
                    if (req.optString("token") != session.token) throw SecurityException("Invalid export token")
                    val encoded = req.optString("data")
                    if (encoded.length > 500_000) throw IllegalArgumentException("Oversized export chunk")
                    val bytes = Base64.decode(encoded, Base64.DEFAULT)
                    if (session.bytesWritten + bytes.size > session.expectedBytes) {
                        throw IllegalArgumentException("Export exceeds declared size")
                    }
                    session.stream.write(bytes)
                    session.bytesWritten += bytes.size
                }
                "finish" -> {
                    val session = exportSession ?: throw IllegalStateException("No active export")
                    if (req.optString("token") != session.token) throw SecurityException("Invalid export token")
                    if (session.bytesWritten != session.expectedBytes) {
                        throw IllegalStateException("Incomplete export")
                    }
                    session.stream.flush()
                    session.stream.close()
                    contentResolver.update(session.uri,
                        ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                    exportSession = null
                    toast("MediaFlow export saved to Downloads")
                }
                "abort" -> {
                    if (req.optString("token") == exportSession?.token) discardExport()
                }
                else -> throw IllegalArgumentException("Unknown export request")
            }
            ack.put("ok", true)
        } catch (error: Exception) {
            if (req.optString("kind") != "start" || exportSession != null) discardExport()
            ack.put("ok", false)
            ack.put("error", error.message ?: "Export failed")
        }
        reply.postMessage(ack.toString())
    }

    private fun discardExport() {
        val session = exportSession ?: return
        exportSession = null
        try { session.stream.close() } catch (_: Exception) {}
        try { contentResolver.delete(session.uri, null, null) } catch (_: Exception) {}
    }

    private fun toast(text: String) {
        runOnUiThread { Toast.makeText(this, text, Toast.LENGTH_SHORT).show() }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == NativeBackupBridge.PICK_DIRECTORY) {
            backupBridge.onFolderPickerResult(resultCode, data)
            return
        }
        if (requestCode == pickerRequestCode) {
            val result = WebChromeClient.FileChooserParams.parseResult(resultCode, data)
            selectedFiles?.onReceiveValue(result)
            selectedFiles = null
        }
    }

    @Deprecated("Compatibility with Android back navigation")
    override fun onBackPressed() {
        if (!::webView.isInitialized) { super.onBackPressed(); return }
        // v507 uses in-memory S.view rather than URL history. First close genuine
        // MediaFlow dialogs, then return to Dashboard; only then leave the app.
        val action = """
            (function() {
              try {
                if (typeof S !== 'undefined' && window.App) {
                  if (S.modal && typeof App.closeModal === 'function') {
                    App.closeModal(); return true;
                  }
                  if (S.view && S.view !== 'dashboard' && typeof App.setView === 'function') {
                    App.setView('dashboard'); return true;
                  }
                }
              } catch (_) {}
              return false;
            })();
        """.trimIndent()
        webView.evaluateJavascript(action) { consumed ->
            if (consumed != "true") {
                if (webView.canGoBack()) webView.goBack()
                else super.onBackPressed()
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        if (::backupBridge.isInitialized) backupBridge.close()
        discardExport()
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }
}
