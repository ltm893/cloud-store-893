import SwiftUI
import WebKit

struct PosAdminWebView: UIViewRepresentable {
    let apiBaseURL: URL
    let onLeaveAdmin: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(apiBaseURL: apiBaseURL, onLeaveAdmin: onLeaveAdmin)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        context.coordinator.webView = webView

        context.coordinator.loadAdmin(into: webView, cacheBust: AppConfig.appBuild)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let apiBaseURL: URL
        private let onLeaveAdmin: () -> Void
        weak var webView: WKWebView?
        private var refreshFallback: DispatchWorkItem?

        init(apiBaseURL: URL, onLeaveAdmin: @escaping () -> Void) {
            self.apiBaseURL = apiBaseURL
            self.onLeaveAdmin = onLeaveAdmin
        }

        @objc func reload(_ sender: UIRefreshControl) {
            guard let webView else {
                sender.endRefreshing()
                return
            }
            scheduleRefreshFallback(for: webView)
            let bust = String(Int(Date().timeIntervalSince1970))
            loadAdmin(into: webView, cacheBust: bust)
        }

        fileprivate func loadAdmin(into webView: WKWebView, cacheBust: String) {
            let url = AppConfigLogic.adminURL(
                base: apiBaseURL,
                embeddedIosClient: true,
                cacheBust: cacheBust
            )
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        }

        private func scheduleRefreshFallback(for webView: WKWebView) {
            refreshFallback?.cancel()
            let work = DispatchWorkItem { [weak webView] in
                webView?.scrollView.refreshControl?.endRefreshing()
            }
            refreshFallback = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        }

        private func endRefresh(for webView: WKWebView) {
            refreshFallback?.cancel()
            refreshFallback = nil
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if AdminNavigationLogic.shouldLeaveAdmin(url: url, apiBaseURL: apiBaseURL) {
                onLeaveAdmin()
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            endRefresh(for: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            endRefresh(for: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            endRefresh(for: webView)
        }
    }
}

enum AdminNavigationLogic {
    /// Web POS root — return to native register instead of loading browser POS HTML (Android parity).
    static func shouldLeaveAdmin(url: URL, apiBaseURL: URL) -> Bool {
        guard let urlHost = url.host?.lowercased(),
              let baseHost = apiBaseURL.host?.lowercased(),
              urlHost == baseHost else { return false }
        let path = url.path
        return path.isEmpty || path == "/"
    }
}
