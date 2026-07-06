import SwiftUI
import WebKit

struct OidcWebView: UIViewRepresentable {
    let loginURL: URL
    let apiBaseURL: URL
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(apiBaseURL: apiBaseURL, onComplete: onComplete)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: loginURL))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let apiBaseURL: URL
        private let onComplete: (URL) -> Void
        weak var webView: WKWebView?
        private var finished = false

        init(apiBaseURL: URL, onComplete: @escaping (URL) -> Void) {
            self.apiBaseURL = apiBaseURL
            self.onComplete = onComplete
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
            if finishIfComplete(url: url, webView: webView) {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            _ = finishIfComplete(url: url, webView: webView)
        }

        private func finishIfComplete(url: URL, webView: WKWebView) -> Bool {
            guard !finished else { return true }
            guard ListerOidcRedirectLogic.isOidcComplete(completionURL: url, apiBaseURL: apiBaseURL) else {
                return false
            }
            finished = true
            webView.stopLoading()
            if let blank = URL(string: "about:blank") {
                webView.load(URLRequest(url: blank))
            }
            onComplete(url)
            return true
        }
    }
}

struct OidcSignInScreen: View {
    let loginURL: URL
    let apiBaseURL: URL
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            OidcWebView(
                loginURL: loginURL,
                apiBaseURL: apiBaseURL,
                onComplete: onComplete,
                onCancel: onCancel
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
