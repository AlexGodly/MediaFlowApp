import UIKit
import WebKit

/// Hosts the packaged MediaFlow website: native alert/confirm/prompt dialogs,
/// external links in Safari, and file exports through the iOS save sheet.
final class MediaFlowViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private var webView: WKWebView!
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private let background = UIColor(red: 9 / 255, green: 12 / 255, blue: 20 / 255, alpha: 1)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = background

        guard let www = Bundle.main.url(forResource: "www", withExtension: nil) else {
            showFatal("The packaged MediaFlow website is missing from this build.")
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(AppSchemeHandler(root: www), forURLScheme: AppSchemeHandler.scheme)
        configuration.websiteDataStore = .default()          // persistent account storage
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.applicationNameForUserAgent = "MediaFlowApp-iOS/1.0"

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        // index.html uses viewport-fit=cover and env(safe-area-inset-*) itself.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }   // Safari Web Inspector for beta testing
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView.load(URLRequest(url: AppSchemeHandler.startURL))
    }

    // MARK: Navigation

    private func isAppURL(_ url: URL) -> Bool {
        url.scheme == AppSchemeHandler.scheme && url.host == AppSchemeHandler.host
    }

    private func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if isAppURL(url) || ["blob", "data", "about"].contains(scheme) { decisionHandler(.allow); return }
        // Embedded provider frames may load inside the page; top-level links leave the app.
        if navigationAction.targetFrame?.isMainFrame == false, scheme == "https" { decisionHandler(.allow); return }
        openExternally(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Reload after a WebKit crash; account data in website storage is untouched.
        webView.load(URLRequest(url: AppSchemeHandler.startURL))
    }

    // window.open / target=_blank
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !isAppURL(url) { openExternally(url) }
        return nil
    }

    // MARK: Downloads (backups, exports)

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaFlowExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = suggestedFilename.isEmpty ? "mediaflow-export" : suggestedFilename
        let destination = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        present(picker, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        presentDialog(title: "Export failed", message: error.localizedDescription,
                      actions: [UIAlertAction(title: "OK", style: .default)], onUnavailable: {})
    }

    // MARK: JavaScript dialogs (the website uses alert/confirm/prompt)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        presentDialog(title: nil, message: message,
                      actions: [UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }],
                      onUnavailable: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        presentDialog(title: nil, message: message, actions: [
            UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) },
            UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) }
        ], onUnavailable: { completionHandler(false) })
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text ?? "") })
        guard let host = topPresenter() else { completionHandler(nil); return }
        host.present(alert, animated: true)
    }

    private func presentDialog(title: String?, message: String, actions: [UIAlertAction], onUnavailable: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach(alert.addAction)
        guard let host = topPresenter() else { onUnavailable(); return }
        host.present(alert, animated: true)
    }

    private func topPresenter() -> UIViewController? {
        guard isViewLoaded, view.window != nil else { return nil }
        var top: UIViewController = self
        while let next = top.presentedViewController {
            if next.isBeingDismissed { break }
            top = next
        }
        return top is UIAlertController ? nil : top
    }

    private func showFatal(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24)
        ])
    }
}
