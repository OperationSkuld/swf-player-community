import UIKit
import WebKit

/// 内置网页浏览器：直接访问用户输入的网址，并嗅探页面中的 Flash(SWF) 资源。
///
/// 设计取舍：
///  - 任意网页内部直接注入 Ruffle 并不可靠（跨域、CSP、WASM publicPath 都会失败），
///    因此采用更稳的路径：网页照常展示，检测到 .swf 资源后提示下载到本地，
///    再用功能完整的 PlayerViewController 播放。
///  - 若输入的链接本身就是 .swf（直链），直接询问是否下载并用内置播放器打开。
final class WebBrowserViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, UITextFieldDelegate {

    private let targetURL: URL
    private var webView: WKWebView!
    private var detectedSWFs: [String] = []

    private let closeButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let addressField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let swfButton = UIButton(type: .system)

    private let activity = UIActivityIndicatorView(style: .medium)
    private let busyOverlay = UIView()
    private let busyCard = UIView()
    private let busySpinner = UIActivityIndicatorView(style: .large)
    private let busyLabel = UILabel()

    init(url: URL) {
        self.targetURL = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "swfSniff")
    }

    override var prefersStatusBarHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationController?.setNavigationBarHidden(true, animated: false)
        title = L("browser.title")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.sniffScript,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: false)
        )
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: "swfSniff"
        )
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = Theme.background
        view.addSubview(webView)

        buildToolbar()
        buildBusyOverlay()
        applyLocalization()
        updateNavButtons()
        updateSWFBadge()

        webView.load(URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showToast(L("browser.sniffHint"))
    }

    // MARK: - 工具栏

    private func buildToolbar() {
        [closeButton, backButton, forwardButton, reloadButton, swfButton].forEach {
            $0.tintColor = Theme.ink
            view.addSubview($0)
        }
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        swfButton.addTarget(self, action: #selector(showDetectedSWFs), for: .touchUpInside)

        addressField.borderStyle = .roundedRect
        addressField.returnKeyType = .go
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.font = UIFont.systemFont(ofSize: 13)
        addressField.textColor = Theme.ink
        addressField.backgroundColor = Theme.groupedBackground
        addressField.delegate = self
        view.addSubview(addressField)

        activity.hidesWhenStopped = true
        activity.color = Theme.secondary
        view.addSubview(activity)
    }

    private func applyLocalization() {
        closeButton.accessibilityLabel = L("browser.close")
        backButton.accessibilityLabel = L("browser.back")
        forwardButton.accessibilityLabel = L("browser.forward")
        reloadButton.accessibilityLabel = L("browser.reload")
        swfButton.accessibilityLabel = L("browser.swfListTitle")
        addressField.placeholder = L("browser.addressPlaceholder")
        busyLabel.text = L("browser.downloading")
    }

    private func setButton(_ button: UIButton, symbol: String, pointSize: CGFloat = 15) {
        let image = UIImage(systemName: symbol,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        button.setImage(image, for: .normal)
    }

    // MARK: - 布局

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let insets = view.safeAreaInsets
        let top = insets.top + 8
        let barHeight: CGFloat = 40
        let pad: CGFloat = 8
        let side: CGFloat = 34

        setButton(closeButton, symbol: "xmark", pointSize: 14)
        setButton(backButton, symbol: "chevron.left", pointSize: 16)
        setButton(forwardButton, symbol: "chevron.right", pointSize: 16)
        setButton(reloadButton, symbol: "arrow.clockwise", pointSize: 15)

        closeButton.frame = CGRect(x: pad, y: top, width: side, height: barHeight)
        backButton.frame = CGRect(x: closeButton.frame.maxX + 2, y: top, width: side, height: barHeight)
        forwardButton.frame = CGRect(x: backButton.frame.maxX + 2, y: top, width: side, height: barHeight)
        reloadButton.frame = CGRect(x: width - pad - side, y: top, width: side, height: barHeight)

        let badgeWidth: CGFloat = 96
        swfButton.frame = CGRect(x: reloadButton.frame.minX - badgeWidth - 2,
                                 y: top, width: badgeWidth, height: barHeight)

        let fieldX = forwardButton.frame.maxX + 4
        addressField.frame = CGRect(x: fieldX,
                                    y: top,
                                    width: max(60, swfButton.frame.minX - 4 - fieldX),
                                    height: barHeight)
        activity.frame = CGRect(x: addressField.frame.maxX - 28,
                                y: top + (barHeight - 20) / 2,
                                width: 20, height: 20)

        let webTop = top + barHeight + 8
        webView.frame = CGRect(x: 0, y: webTop, width: width,
                               height: view.bounds.height - webTop)

        busyOverlay.frame = view.bounds
        let cardSize = CGSize(width: 168, height: 116)
        busyCard.frame = CGRect(x: (width - cardSize.width) / 2,
                                y: (view.bounds.height - cardSize.height) / 2,
                                width: cardSize.width, height: cardSize.height)
        busySpinner.frame = CGRect(x: (cardSize.width - 34) / 2, y: 20, width: 34, height: 34)
        busyLabel.frame = CGRect(x: 10, y: 64, width: cardSize.width - 20, height: 34)
    }

    // MARK: - 浏览器动作

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func backTapped() {
        if webView.canGoBack { webView.goBack() } else { closeTapped() }
    }

    @objc private func forwardTapped() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func reloadTapped() {
        webView.reload()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let raw = textField.text ?? ""
        guard let url = normalizedURL(raw) else {
            showError(L("home.urlInvalid"))
            return false
        }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return true
    }

    private func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private func updateNavButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        backButton.alpha = webView.canGoBack ? 1 : 0.4
        forwardButton.alpha = webView.canGoForward ? 1 : 0.4
    }

    private func updateSWFBadge() {
        let count = detectedSWFs.count
        swfButton.isEnabled = count > 0
        swfButton.alpha = count > 0 ? 1 : 0.45
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bolt.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        config.imagePadding = 4
        config.baseForegroundColor = count > 0 ? Theme.red : Theme.secondary
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        var title = AttributedString(count > 0 ? L("browser.swfCount", String(count)) : L("browser.swfNoneShort"))
        title.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        config.attributedTitle = title
        swfButton.configuration = config
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activity.startAnimating()
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activity.stopAnimating()
        if let url = webView.url { addressField.text = url.absoluteString }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
        updateNavButtons()
    }

    /// 地址栏本身就是 .swf 直链时，不让 WKWebView 渲染，直接走下载播放流程。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, Self.isDirectSWF(url) {
            decisionHandler(.cancel)
            confirmDownload(url)
            return
        }
        decisionHandler(.allow)
    }

    /// 服务器以 Flash 的 MIME 类型返回时同样拦截（有些直链不带 .swf 后缀）。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           let mime = response.mimeType?.lowercased(),
           mime.contains("shockwave-flash") {
            decisionHandler(.cancel)
            confirmDownload(response.url ?? webView.url)
            return
        }
        decisionHandler(.allow)
    }

    private static func isDirectSWF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "swf"
    }

    // MARK: - SWF 嗅探

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "swfSniff",
              let body = message.body as? [String: Any],
              let urls = body["urls"] as? [String] else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var merged = self.detectedSWFs
            for url in urls where !merged.contains(url) { merged.append(url) }
            self.detectedSWFs = Array(merged.prefix(24))
            self.updateSWFBadge()
        }
    }

    @objc private func showDetectedSWFs() {
        guard !detectedSWFs.isEmpty else {
            showError(L("browser.swfNone"))
            return
        }
        let sheet = UIAlertController(title: L("browser.swfListTitle"),
                                      message: L("browser.swfListMessage", String(detectedSWFs.count)),
                                      preferredStyle: .actionSheet)
        for (index, value) in detectedSWFs.enumerated() {
            let label = "\(index + 1). \((value as NSString).lastPathComponent)"
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self = self, let url = URL(string: value) else { return }
                self.confirmDownload(url)
            })
        }
        sheet.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = swfButton
            popover.sourceRect = swfButton.bounds
        }
        present(sheet, animated: true)
    }

    private func confirmDownload(_ url: URL?) {
        guard let url = url else { return }
        let alert = UIAlertController(title: L("browser.directSWFTitle"),
                                      message: L("browser.directSWFMessage", url.absoluteString),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("browser.downloadAction"), style: .default) { [weak self] _ in
            self?.downloadAndPlay(url)
        })
        present(alert, animated: true)
    }

    // MARK: - 下载并用本地播放器打开

    private func buildBusyOverlay() {
        busyOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        busyOverlay.isHidden = true
        view.addSubview(busyOverlay)

        busyCard.backgroundColor = UIColor(hex: 0x1C1C1E)
        busyCard.layer.cornerRadius = 16
        busyOverlay.addSubview(busyCard)

        busySpinner.color = .white
        busyCard.addSubview(busySpinner)

        busyLabel.textColor = .white
        busyLabel.font = UIFont.systemFont(ofSize: 12.5)
        busyLabel.textAlignment = .center
        busyLabel.numberOfLines = 2
        busyCard.addSubview(busyLabel)
    }

    private func setBusy(_ busy: Bool) {
        busyOverlay.isHidden = !busy
        if busy {
            busySpinner.startAnimating()
            view.bringSubviewToFront(busyOverlay)
        } else {
            busySpinner.stopAnimating()
        }
    }

    private func downloadAndPlay(_ url: URL) {
        setBusy(true)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
                         + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let referer = webView.url.flatMap { "\($0.scheme ?? "https")://\($0.host ?? "")/" }
            ?? "\(url.scheme ?? "https")://\(url.host ?? "")/"
        request.setValue(referer, forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false)

                if let error = error {
                    self.showError(error.localizedDescription)
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    self.showError(L("browser.httpError", String(http.statusCode)))
                    return
                }
                guard let data = data, !data.isEmpty else {
                    self.showError(L("browser.invalidSWF"))
                    return
                }
                guard data.count <= 60 * 1024 * 1024 else {
                    self.showError(L("browser.tooLarge"))
                    return
                }
                let signature = String(decoding: data.prefix(3), as: UTF8.self)
                guard ["FWS", "CWS", "ZWS"].contains(signature) else {
                    self.showError(L("browser.invalidSWF"))
                    return
                }

                let rawName = url.lastPathComponent.removingPercentEncoding ?? ""
                let name = rawName.isEmpty ? "flash.swf" : rawName
                do {
                    let item = try LibraryStore.shared.importRemote(data: data, fileName: name)
                    LibraryStore.shared.touch(item.id)
                    self.navigationController?.pushViewController(PlayerViewController(item: item), animated: true)
                } catch {
                    self.showError(L("browser.invalidSWF"))
                }
            }
        }.resume()
    }

    // MARK: - 提示

    private func showError(_ message: String) {
        let alert = UIAlertController(title: L("browser.loadFailedTitle"),
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.font = UIFont.systemFont(ofSize: 12.5)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        let width = min(view.bounds.width - 48, 340)
        label.frame = CGRect(x: (view.bounds.width - width) / 2,
                             y: view.safeAreaInsets.top + 62,
                             width: width, height: 46)
        view.addSubview(label)
        UIView.animate(withDuration: 0.3, delay: 3.2, options: .curveEaseInOut, animations: {
            label.alpha = 0
        }, completion: { _ in label.removeFromSuperview() })
    }

    // MARK: - 嗅探脚本

    /// 扫描 embed/object/param、链接、iframe 以及内联属性中的 .swf 地址，
    /// 以 document.baseURI 解析成绝对 URL 后回传，并用 MutationObserver 跟踪动态内容。
    private static let sniffScript = #"""
    (function () {
      function abs(u) {
        try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
      }
      function collect() {
        var found = [];
        function add(u) {
          if (!u) { return; }
          var full = abs(u);
          if (!full || !/^https?:\/\//i.test(full)) { return; }
          if (!/\.swf(\?|#|$)/i.test(full)) { return; }
          found.push(full);
        }
        var nodes = document.querySelectorAll(
          'embed[src],object[data],object[codebase],param[name],a[href],area[href],iframe[src],input[value]'
        );
        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];
          var tag = n.tagName.toLowerCase();
          if (tag === 'embed' || tag === 'iframe') { add(n.getAttribute('src')); }
          else if (tag === 'object') { add(n.getAttribute('data')); add(n.getAttribute('codebase')); }
          else if (tag === 'param') {
            var name = (n.getAttribute('name') || '').toLowerCase();
            if (name === 'movie' || name === 'src' || name === 'data') { add(n.getAttribute('value')); }
          } else if (tag === 'a' || tag === 'area') { add(n.getAttribute('href')); }
          else if (tag === 'input') { add(n.getAttribute('value')); }
        }
        try {
          var html = document.documentElement.outerHTML;
          var re = /(?:src|data|value|href|movie)\s*=\s*["']([^"']+\.swf(?:\?[^"']*)?)["']/gi;
          var m;
          while ((m = re.exec(html)) !== null) { add(m[1]); }
        } catch (e) {}
        var seen = {}, out = [];
        for (var j = 0; j < found.length; j++) {
          var clean = found[j].split('#')[0];
          if (!seen[clean]) { seen[clean] = 1; out.push(clean); }
        }
        return out.slice(0, 24);
      }
      function report() {
        try {
          window.webkit.messageHandlers.swfSniff.postMessage({ urls: collect() });
        } catch (e) {}
      }
      window.__swfSniff = report;
      if (document.readyState === 'complete' || document.readyState === 'interactive') {
        setTimeout(report, 300);
      } else {
        document.addEventListener('DOMContentLoaded', function () { setTimeout(report, 300); });
      }
      window.addEventListener('load', function () { setTimeout(report, 500); });
      if (window.MutationObserver) {
        var timer = null;
        var observer = new MutationObserver(function () {
          if (timer) { return; }
          timer = setTimeout(function () { timer = null; report(); }, 700);
        });
        observer.observe(document.documentElement || document,
                         { childList: true, subtree: true, attributes: true });
      }
    })();
    """#
}
