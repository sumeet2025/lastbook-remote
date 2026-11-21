import LastbookRemoteKit
import SwiftUI
import WebKit

enum WebViewSupport {
    /// Put the access key in the web view's cookie store as `sg_key`, the cookie Lastbook's access
    /// link sets, so pages and their images, styles and frames are all admitted.
    @MainActor
    static func installKeyCookie(_ client: LastbookClient, in store: WKHTTPCookieStore) async {
        guard let host = client.baseURL.host else { return }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "sg_key",
            .value: client.key,
            .domain: host,
            .path: "/",
            .expires: Date().addingTimeInterval(365 * 24 * 3600),
        ]
        props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        if let cookie = HTTPCookie(properties: props) {
            await store.setCookie(cookie)
        }
    }

    /// Empty the web views' caches (keeps cookies, so libraries stay connected).
    @MainActor
    static func clearCaches() {
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }
}

/// A WKWebView that opens popups and `target=_blank` links in place.
struct WebView: UIViewRepresentable {
    let request: URLRequest?
    let fileURL: URL?
    var onError: ((Error) -> Void)?
    var onLoading: ((Bool) -> Void)?

    init(request: URLRequest, onError: ((Error) -> Void)? = nil, onLoading: ((Bool) -> Void)? = nil) {
        self.request = request
        self.fileURL = nil
        self.onError = onError
        self.onLoading = onLoading
    }

    init(fileURL: URL) {
        self.request = nil
        self.fileURL = fileURL
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.isInspectable = true
        if let fileURL {
            view.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else if let request {
            view.load(request)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading?(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading?(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onLoading?(false)
            if (error as NSError).code != NSURLErrorCancelled { parent.onError?(error) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoading?(false)
            if (error as NSError).code != NSURLErrorCancelled { parent.onError?(error) }
        }
    }
}

/// The computer's own Lastbook app (`web/`), for encyclopedias, maps, guides, and Chat when the
/// host shares it. Opened with the access link, as Safari would be.
struct HostWebAppView: View {
    @EnvironmentObject var session: LibrarySession
    @State private var ready = false
    @State private var error: Error?
    @State private var reload = 0

    var body: some View {
        ZStack {
            if ready {
                WebView(request: URLRequest(url: session.client.webAppURL), onError: { e in error = e })
                    .id(reload)
            } else {
                ProgressView()
            }
            if let error {
                VStack(spacing: 12) {
                    Text(error.localizedDescription).multilineTextAlignment(.center)
                    Button("Reload") {
                        self.error = nil
                        reload += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
        .navigationTitle("Lastbook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    error = nil
                    reload += 1
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            await WebViewSupport.installKeyCookie(session.client, in: WKWebsiteDataStore.default().httpCookieStore)
            ready = true
        }
    }
}

/// A saved web page or other file the host serves, in a web view (remote), or from Downloaded.
struct WebDocumentView: View {
    let source: DocumentSource
    @State private var request: URLRequest?
    @State private var error: Error?

    var body: some View {
        Group {
            switch source {
            case .local(_, let file):
                WebView(fileURL: file)
            case .remote(let item, _, let client):
                if let request {
                    WebView(request: request, onError: { e in error = e })
                        .overlay(alignment: .bottom) {
                            if let error {
                                Text(error.localizedDescription)
                                    .padding()
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    .padding()
                            }
                        }
                } else {
                    ProgressView()
                        .task {
                            await WebViewSupport.installKeyCookie(client, in: WKWebsiteDataStore.default().httpCookieStore)
                            request = client.authorizedRequest(client.fileURL(path: item.path ?? ""))
                        }
                }
            }
        }
    }
}
