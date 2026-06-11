import SwiftUI
import WebKit

struct AdminRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Server: \(AppConfig.apiHostLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color(.systemGray6))
            AdminWebView(apiBaseURL: AppConfig.apiBaseURL)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct AdminWebView: UIViewRepresentable {
    let apiBaseURL: URL
    private let portraitModeEnabled = UIDevice.current.userInterfaceIdiom == .phone

    func makeCoordinator() -> Coordinator {
        Coordinator(apiBaseURL: apiBaseURL, portraitModeEnabled: portraitModeEnabled)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        #if DEBUG
        config.websiteDataStore = .nonPersistent()
        #endif
        if portraitModeEnabled {
            let portraitScript = WKUserScript(
                source: PortraitWebScripts.documentStart,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(portraitScript)
        }

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
        private let portraitModeEnabled: Bool
        weak var webView: WKWebView?
        private var refreshFallback: DispatchWorkItem?

        init(apiBaseURL: URL, portraitModeEnabled: Bool) {
            self.apiBaseURL = apiBaseURL
            self.portraitModeEnabled = portraitModeEnabled
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
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            endRefresh(for: webView)
            guard portraitModeEnabled else { return }
            webView.evaluateJavaScript(PortraitWebScripts.applyAfterLoad, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("AdminWebView navigation failed: \(error.localizedDescription)")
            endRefresh(for: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("AdminWebView provisional navigation failed: \(error.localizedDescription)")
            endRefresh(for: webView)
        }
    }
}
