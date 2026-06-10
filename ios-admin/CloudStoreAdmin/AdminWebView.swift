import SwiftUI
import WebKit

struct AdminRootView: View {
    var body: some View {
        AdminWebView(url: AppConfig.adminURL)
            .ignoresSafeArea(edges: .bottom)
    }
}

struct AdminWebView: UIViewRepresentable {
    let url: URL
    private let portraitModeEnabled = UIDevice.current.userInterfaceIdiom == .phone

    func makeCoordinator() -> Coordinator {
        Coordinator(portraitModeEnabled: portraitModeEnabled)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
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

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let portraitModeEnabled: Bool

        init(portraitModeEnabled: Bool) {
            self.portraitModeEnabled = portraitModeEnabled
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard portraitModeEnabled else { return }
            webView.evaluateJavaScript(PortraitWebScripts.applyAfterLoad, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("AdminWebView navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("AdminWebView provisional navigation failed: \(error.localizedDescription)")
        }
    }
}
