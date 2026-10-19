package com.alexgodly.mediaflow

import android.app.Activity
import android.app.DownloadManager
import android.content.ContentValues
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(9, 12, 20)
        window.navigationBarColor = Color.rgb(9, 12, 20)

        loader = WebViewAssetLoader.Builder()
            .setDomain(appHost)
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

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

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)

        // The listener is restricted to the locally packaged MediaFlow origin AND its main frame.
        // Unlike addJavascriptInterface, third-party iframes cannot send arbitrary exports.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(
                webView, "MediaFlowNativeFiles", setOf("https://$appHost")
            ) { _, message, origin, isMainFrame, _ ->
                if (isMainFrame && origin.host == appHost) {
                    try {
                        val payload = JSONObject(message.data ?: "")
                        if (payload.optString("kind") == "export") {
                            saveExport(payload.optString("name"), payload.optString("dataUrl"))
                        }
                    } catch (_: Exception) {
                        runOnUiThread { toast("Unable to save MediaFlow export") }
                    }
                }
            }
        }

        webView.webViewClient = object : WebViewClient() {
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
                // Website JSON/CSV exports use object URLs; write them through the scoped Storage API.
                val js = """
                    (async function() {
                      try {
                        const response = await fetch(${JSONObject.quote(url)});
                        const blob = await response.blob();
                        const reader = new FileReader();
                        reader.onload = () => window.MediaFlowNativeFiles?.postMessage(JSON.stringify({
                          kind: 'export', name: ${JSONObject.quote(name)},
                          dataUrl: reader.result
                        }));
                        reader.readAsDataURL(blob);
                      } catch (error) { console.error('MediaFlow Android export', error); }
                    })();
                """.trimIndent()
                webView.evaluateJavascript(js, null)
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

    private fun saveExport(name: String, dataUrl: String) {
        try {
            // Bound the base64 bridge to avoid catastrophic memory pressure on low-RAM phones.
            if (!dataUrl.startsWith("data:") || dataUrl.length > 140_000_000) {
                toast("Export is too large for Android share bridge"); return
            }
            val pos = dataUrl.indexOf(',')
            if (pos < 5) return
            val mime = dataUrl.substring(5, pos).substringBefore(';').ifBlank { "application/octet-stream" }
            val bytes = Base64.decode(dataUrl.substring(pos + 1), Base64.DEFAULT)
            val safeName = name.replace(Regex("[^\\w.() -]"), "_").take(120).ifEmpty { "MediaFlow-export.json" }
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/")
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Cannot create download")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Cannot write download")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                toast("Saved to Downloads: $safeName")
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                throw error
            }
        } catch (_: Exception) { toast("MediaFlow export failed") }
    }

    private fun toast(text: String) {
        runOnUiThread { Toast.makeText(this, text, Toast.LENGTH_SHORT).show() }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickerRequestCode) {
            val result = WebChromeClient.FileChooserParams.parseResult(resultCode, data)
            selectedFiles?.onReceiveValue(result)
            selectedFiles = null
        }
    }

    @Deprecated("Deprecated in Android Activity but needed for WebView back navigation")
    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) webView.goBack()
        else super.onBackPressed()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }
}
