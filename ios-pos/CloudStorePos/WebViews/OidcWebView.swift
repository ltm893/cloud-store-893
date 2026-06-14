import SwiftUI
import WebKit

struct OidcWebView: UIViewRepresentable {
    let loginURL: URL
    let apiBaseURL: URL
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            apiBaseURL: apiBaseURL,
            onComplete: onComplete
        )
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
            if finishIfComplete(url: url, webView: webView) { return }

            webView.evaluateJavaScript("(document.body && document.body.innerText) || ''") { [weak self] value, _ in
                guard let self, !self.finished else { return }
                let text = (value as? String ?? "").lowercased()
                if text.contains("pending login approval") {
                    self.finished = true
                    self.onComplete(url)
                }
            }
        }

        private func finishIfComplete(url: URL, webView: WKWebView) -> Bool {
            guard !finished else { return true }
            guard OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: apiBaseURL) else {
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
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255))
                Text("Store sign-in")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            OidcWebView(
                loginURL: loginURL,
                apiBaseURL: apiBaseURL,
                onComplete: onComplete,
                onCancel: onCancel
            )
        }
    }
}
