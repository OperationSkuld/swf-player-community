import Foundation
import WebKit

/// 自定义 scheme：让 WKWebView 在一个稳定的 origin 下加载本地 Ruffle WASM 与 SWF 文件。
/// 直接用 file:// 会因为 opaque origin 导致 fetch() / WebAssembly.instantiateStreaming 失败，
/// 这里采用与 Capacitor( capacitor://localhost ) 相同的做法。
enum PlayerURL {
    static let scheme = "swfapp"
    static let host = "localhost"
    static let webDirectory = "Web"

    /// 首页/播放器启动时把自动播放与初始静音偏好传给 JS。
    static func pageURL(autoplay: Bool, muted: Bool) -> URL {
        let query = "?autoplay=\(autoplay ? "1" : "0")&muted=\(muted ? "1" : "0")"
        return URL(string: "\(scheme)://\(host)/\(webDirectory)/player.html\(query)")!
    }

    static var publicPath: String {
        "\(scheme)://\(host)/\(webDirectory)/"
    }

    static func swfURLString(for fileName: String) -> String {
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return "\(scheme)://\(host)/swf/\(encoded)"
    }
}

/// 把 Swift 字符串安全地变成 JS 字符串字面量内容（含引号处理）。
func jsStringLiteral(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
          let encoded = String(data: data, encoding: .utf8),
          encoded.count >= 2 else {
        return "\"\""
    }
    // encoded 形如 ["...."]，去掉外层方括号即得到带引号的 JSON/JS 字符串。
    return String(encoded.dropFirst().dropLast())
}

/// 为 WKWebView 提供 /Web/*（应用内资源）与 /swf/*（用户导入文件）两类响应。
final class SWFSchemeHandler: NSObject, WKURLSchemeHandler {
    private let stoppedTasks = NSHashTable<AnyObject>.weakObjects()
    private let fileManager = FileManager.default

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard !stoppedTasks.contains(urlSchemeTask as AnyObject),
              let url = urlSchemeTask.request.url else { return }

        let path = url.path
        let fileURL: URL?
        let mime: String

        if path.hasPrefix("/swf/") {
            let fileName = (path as NSString).lastPathComponent
            fileURL = LibraryStore.shared.swfDirectoryURL.appendingPathComponent(fileName)
            mime = "application/x-shockwave-flash"
        } else {
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            fileURL = bundledURL(for: relative)
            mime = Self.mimeType(for: (relative as NSString).pathExtension)
        }

        guard let resolvedURL = fileURL,
              let data = try? Data(contentsOf: resolvedURL, options: .mappedIfSafe) else {
            respond(urlSchemeTask, url: url, status: 404, mime: "text/plain", data: Data("not found".utf8))
            return
        }

        respond(urlSchemeTask, url: url, status: 200, mime: mime, data: data)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        stoppedTasks.add(urlSchemeTask as AnyObject)
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, data: Data) {
        guard !stoppedTasks.contains(task as AnyObject) else { return }
        let headers: [String: String] = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store"
        ]
        // HTTPURLResponse 让自定义 scheme 也能带上 CORS 头（Capacitor 同款做法）；
        // 若系统拒绝为非 http(s) scheme 构造它，则退化为普通 URLResponse。
        let response: URLResponse = HTTPURLResponse(url: url,
                                                    statusCode: status,
                                                    httpVersion: "HTTP/1.1",
                                                    headerFields: headers)
            ?? URLResponse(url: url,
                           mimeType: mime,
                           expectedContentLength: data.count,
                           textEncodingName: nil)
        task.didReceive(response)
        guard !stoppedTasks.contains(task as AnyObject) else { return }
        task.didReceive(data)
        guard !stoppedTasks.contains(task as AnyObject) else { return }
        task.didFinish()
    }

    /// 兼容两种资源布局：蓝folder引用（Web/xxx）与直接平铺到 bundle 根目录。
    private func bundledURL(for relative: String) -> URL? {
        let direct = Bundle.main.bundleURL.appendingPathComponent(relative)
        if fileManager.fileExists(atPath: direct.path) { return direct }

        let name = (relative as NSString).lastPathComponent as NSString
        if name.pathExtension.isEmpty {
            return Bundle.main.url(forResource: name.lastPathComponent, withExtension: nil)
        }
        return Bundle.main.url(forResource: name.deletingPathExtension, withExtension: name.pathExtension)
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "wasm": return "application/wasm"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "swf": return "application/x-shockwave-flash"
        case "txt", "": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

/// 弱引用代理，避免 userContentController 强持有 VC 造成循环引用。
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

enum PlayerWebViewFactory {
    static func make(messageHandler: WKScriptMessageHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(SWFSchemeHandler(), forURLScheme: PlayerURL.scheme)
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: messageHandler),
            name: "bridge"
        )
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = Theme.playerBlack
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.backgroundColor = Theme.playerBlack
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }
}
