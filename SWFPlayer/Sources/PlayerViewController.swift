import UIKit
import WebKit

final class PlayerViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    private var item: SWFItem
    private var webView: WKWebView!

    private let topBar = UIView()
    private let bottomBar = UIView()
    private let backButton = Controls.roundButton(systemName: "chevron.left", accessibility: "")
    private let muteButton = Controls.roundButton(systemName: "speaker.slash.fill", accessibility: "")
    private let snapshotButton = Controls.roundButton(systemName: "camera.fill", accessibility: "")
    private let infoButton = Controls.roundButton(systemName: "info.circle", accessibility: "")
    private let fullscreenButton = Controls.roundButton(systemName: "viewfinder", accessibility: "")
    private let restartButton = Controls.roundButton(systemName: "arrow.counterclockwise", accessibility: "")
    private let playButton = UIButton(type: .system)
    private let volumeSlider = UISlider()
    private let statusLabel = UILabel()

    private var isPlaying = true
    private var isMuted = false
    private var chromeHidden = false
    private var didRetryWithData = false
    private var didReceiveReady = false
    private var metadata: [String: Any] = [:]

    init(item: SWFItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
        OrientationManager.allowLandscape = false
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.playerBlack
        navigationController?.setNavigationBarHidden(true, animated: false)

        webView = PlayerWebViewFactory.make(messageHandler: self)
        webView.navigationDelegate = self
        view.addSubview(webView)

        buildControls()
        applyLocalization()

        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        statusLabel.textAlignment = .center
        statusLabel.text = L("player.loading")
        view.addSubview(statusLabel)

        let request = URLRequest(url: PlayerURL.pageURL, cachePolicy: .reloadIgnoringLocalCacheData)
        webView.load(request)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        OrientationManager.allowLandscape = false
        UIApplication.shared.attemptRotationToDeviceOrientation()
    }

    // MARK: - 控件

    private func buildControls() {
        topBar.backgroundColor = .clear
        view.addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(muteButton)
        topBar.addSubview(snapshotButton)
        topBar.addSubview(infoButton)
        topBar.addSubview(fullscreenButton)

        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        snapshotButton.addTarget(self, action: #selector(takeScreenshot), for: .touchUpInside)
        infoButton.addTarget(self, action: #selector(showInfo), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(toggleFullscreen), for: .touchUpInside)

        bottomBar.backgroundColor = Theme.controlBackground
        bottomBar.layer.cornerRadius = 32
        view.addSubview(bottomBar)
        bottomBar.addSubview(restartButton)

        restartButton.backgroundColor = .clear
        restartButton.addTarget(self, action: #selector(restart), for: .touchUpInside)

        let pauseConfig = UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)
        playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: pauseConfig), for: .normal)
        playButton.tintColor = Theme.ink
        playButton.backgroundColor = .white
        playButton.layer.cornerRadius = 22
        playButton.clipsToBounds = true
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(playButton)

        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = 1
        volumeSlider.minimumTrackTintColor = Theme.red
        volumeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
        volumeSlider.thumbTintColor = .white
        volumeSlider.addTarget(self, action: #selector(volumeChanged(_:)), for: .valueChanged)
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(volumeSlider)

        // 双击画面进入/退出全屏，与原版的全屏手势保持一致。
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleFullscreen))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        webView.addGestureRecognizer(doubleTap)
    }

    private func applyLocalization() {
        backButton.accessibilityLabel = L("player.back")
        muteButton.accessibilityLabel = isMuted ? L("player.unmute") : L("player.mute")
        snapshotButton.accessibilityLabel = L("player.snapshot")
        infoButton.accessibilityLabel = L("player.info")
        fullscreenButton.accessibilityLabel = chromeHidden ? L("player.exitFullscreen") : L("player.fullscreen")
        restartButton.accessibilityLabel = L("player.restart")
        playButton.accessibilityLabel = isPlaying ? L("player.pause") : L("player.play")
        statusLabel.text = L("player.loading")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let height = view.bounds.height
        webView.frame = view.bounds

        let topInset = view.safeAreaInsets.top
        let bottomInset = view.safeAreaInsets.bottom

        topBar.frame = CGRect(x: 0, y: topInset + 10, width: width, height: 44)
        backButton.frame = CGRect(x: 18, y: 2, width: 40, height: 40)
        let rightWidth: CGFloat = 40 * 4 + 8 * 3
        var x = width - 18 - rightWidth
        for button in [muteButton, snapshotButton, infoButton, fullscreenButton] {
            button.frame = CGRect(x: x, y: 2, width: 40, height: 40)
            x += 48
        }

        let barWidth: CGFloat = min(300, width - 36)
        bottomBar.frame = CGRect(x: (width - barWidth) / 2,
                                 y: height - bottomInset - 76,
                                 width: barWidth,
                                 height: 64)
        restartButton.frame = CGRect(x: 12, y: 12, width: 40, height: 40)
        playButton.frame = CGRect(x: 62, y: 10, width: 44, height: 44)
        volumeSlider.frame = CGRect(x: 118, y: 20, width: barWidth - 138, height: 24)

        statusLabel.frame = CGRect(x: 20, y: height / 2 - 20, width: width - 40, height: 40)
    }

    // MARK: - WKWebView 载入

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 若脚本因故未发出 ready 事件，这里做一次兜底。
        // JS 侧等待 Ruffle 注入最多约 4s，兜底必须晚于该窗口，否则会抢跑。
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, !self.didReceiveReady else { return }
            self.didReceiveReady = true
            self.loadSWF()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailure(reason: error.localizedDescription)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }
        let payload = body["payload"]
        DispatchQueue.main.async { [weak self] in
            self?.handle(event: event, payload: payload)
        }
    }

    private func handle(event: String, payload: Any?) {
        switch event {
        case "ready":
            guard !didReceiveReady else { return }
            didReceiveReady = true
            loadSWF()

        case "loaded":
            statusLabel.isHidden = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.captureCover()
            }

        case "metadata":
            if let dictionary = payload as? [String: Any] { metadata = dictionary }

        case "state":
            if let dictionary = payload as? [String: Any],
               let suspended = dictionary["suspended"] as? Bool {
                isPlaying = !suspended
                updatePlayButton()
            }

        case "error":
            let reason = (payload as? String) ?? "unknown"
            if !didRetryWithData, let data = try? Data(contentsOf: LibraryStore.shared.fileURL(for: item)),
               data.count < 30_000_000 {
                didRetryWithData = true
                callJS("SWF.loadData(\(jsStringLiteral(data.base64EncodedString())), \(jsStringLiteral(item.name)))")
            } else {
                showLoadFailure(reason: reason)
            }

        default:
            break
        }
    }

    private func loadSWF() {
        let url = PlayerURL.swfURLString(for: item.fileName)
        callJS("SWF.load(\(jsStringLiteral(url)))")
    }

    private func callJS(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                NSLog("[SWFPlayer] JS error: %@", error.localizedDescription)
            }
        }
    }

    private func showLoadFailure(reason: String) {
        NSLog("[SWFPlayer] load failed: %@", reason)
        if Bundle.main.url(forResource: "ruffle", withExtension: "js") == nil,
           Bundle.main.url(forResource: "ruffle", withExtension: "js", subdirectory: "Web") == nil {
            statusLabel.text = L("player.engineMissing")
        } else {
            statusLabel.text = L("player.loadFailedTitle")
        }
        statusLabel.isHidden = false

        let alert = UIAlertController(title: L("player.loadFailedTitle"),
                                      message: L("player.loadFailedMessage"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        alert.addAction(UIAlertAction(title: L("player.retryAction"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.didRetryWithData = false
            self.statusLabel.text = L("player.loading")
            self.callJS("SWF.restart()")
        })
        present(alert, animated: true)
    }

    // MARK: - 操作

    @objc private func goBack() {
        if let navigationController = navigationController,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func togglePlay() {
        isPlaying.toggle()
        callJS(isPlaying ? "SWF.play()" : "SWF.pause()")
        updatePlayButton()
    }

    private func updatePlayButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)
        let name = isPlaying ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
        playButton.accessibilityLabel = isPlaying ? L("player.pause") : L("player.play")
    }

    @objc private func restart() {
        isPlaying = true
        updatePlayButton()
        callJS("SWF.restart()")
    }

    @objc private func toggleMute() {
        isMuted.toggle()
        volumeSlider.value = isMuted ? 0 : 1
        callJS("SWF.setVolume(\(isMuted ? "0" : "1"))")
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        muteButton.setImage(UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                    withConfiguration: config), for: .normal)
        muteButton.accessibilityLabel = isMuted ? L("player.unmute") : L("player.mute")
    }

    @objc private func volumeChanged(_ slider: UISlider) {
        isMuted = slider.value < 0.01
        callJS(String(format: "SWF.setVolume(%.3f)", Double(slider.value)))
    }

    @objc private func toggleFullscreen() {
        chromeHidden.toggle()
        OrientationManager.allowLandscape = chromeHidden
        UIApplication.shared.attemptRotationToDeviceOrientation()
        UIView.animate(withDuration: 0.22) {
            self.topBar.alpha = self.chromeHidden ? 0 : 1
            self.bottomBar.alpha = self.chromeHidden ? 0 : 1
        }
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        fullscreenButton.setImage(UIImage(systemName: chromeHidden ? "arrow.down.right.and.arrow.up.left" : "viewfinder",
                                          withConfiguration: config), for: .normal)
        fullscreenButton.accessibilityLabel = chromeHidden ? L("player.exitFullscreen") : L("player.fullscreen")
    }

    @objc private func takeScreenshot() {
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self = self else { return }
            guard let image = image else {
                self.showToast(L("player.snapshotFailed"))
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, self,
                                           #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }

    @objc private func image(_ image: UIImage,
                             didFinishSavingWithError error: NSError?,
                             contextInfo: UnsafeRawPointer?) {
        showToast(error == nil ? L("player.snapshotSaved") : L("player.snapshotFailed"))
    }

    private func captureCover() {
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self = self, let image = image else { return }
            LibraryStore.shared.setCover(for: self.item.id, image: image)
        }
    }

    @objc private func showInfo() {
        func value(_ key: String) -> String {
            if let number = metadata[key] as? NSNumber { return number.stringValue }
            if let string = metadata[key] as? String { return string }
            return L("player.infoUnknown")
        }

        let as3 = (metadata["isActionScript3"] as? NSNumber)?.boolValue == true
            ? L("player.infoAS3Value") : L("player.infoAS12Value")

        let lines = [
            item.name,
            L("player.infoDimensions", value("width"), value("height")),
            L("player.infoFrameRate", value("frameRate")),
            L("player.infoFrames", value("numFrames")),
            L("player.infoSwfVersion", value("swfVersion")),
            L("player.infoAS3", as3),
            L("player.infoFileSize", BuildInfo.humanReadableSize(item.byteCount))
        ]
        let alert = UIAlertController(title: L("player.infoTitle"),
                                      message: lines.joined(separator: "\n"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        let width = min(view.bounds.width - 60, 300)
        label.frame = CGRect(x: (view.bounds.width - width) / 2,
                             y: view.bounds.height - view.safeAreaInsets.bottom - 170,
                             width: width, height: 44)
        view.addSubview(label)
        UIView.animate(withDuration: 0.3, delay: 1.8, options: .curveEaseInOut, animations: {
            label.alpha = 0
        }, completion: { _ in label.removeFromSuperview() })
    }
}

extension PlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
