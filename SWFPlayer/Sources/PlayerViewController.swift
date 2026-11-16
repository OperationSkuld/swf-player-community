import UIKit
import WebKit

final class PlayerViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    private var item: SWFItem
    private var webView: WKWebView!

    private let topBar = UIView()
    private let bottomBar = UIView()

    // 顶部：返回 / 重播 / 截图 / 信息 / 全屏
    private let backButton = Controls.roundButton(systemName: "chevron.left", accessibility: "")
    private let restartButton = Controls.roundButton(systemName: "arrow.counterclockwise", accessibility: "")
    private let snapshotButton = Controls.roundButton(systemName: "camera.fill", accessibility: "")
    private let infoButton = Controls.roundButton(systemName: "info", accessibility: "")
    private let fullscreenButton = Controls.roundButton(systemName: "arrow.up.left.and.arrow.down.right", accessibility: "")

    // 底部：播放 / 设置 / 音量 / 静音
    private let playButton = UIButton(type: .system)
    private let settingsButton = Controls.roundButton(systemName: "gearshape.fill", accessibility: "")
    private let volumeSlider = UISlider()
    private let speakerButton = Controls.roundButton(systemName: "speaker.wave.2.fill", accessibility: "")

    private let statusLabel = UILabel()

    private let errorOverlay = UIView()
    private let errorCard = UIView()
    private let errorTitleLabel = UILabel()
    private let errorBodyLabel = UILabel()
    private let errorRetryButton = UIButton(type: .system)
    private let errorBackButton = UIButton(type: .system)

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

        isMuted = PlaybackPreferences.startMuted
        isPlaying = PlaybackPreferences.autoPlay

        webView = PlayerWebViewFactory.make(messageHandler: self)
        webView.navigationDelegate = self
        view.addSubview(webView)

        buildControls()
        buildErrorOverlay()
        updatePlayButton()
        updateSpeaker()
        applyLocalization()

        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        statusLabel.textAlignment = .center
        statusLabel.text = L("player.loading")
        view.addSubview(statusLabel)

        let page = PlayerURL.pageURL(autoplay: PlaybackPreferences.autoPlay,
                                     muted: PlaybackPreferences.startMuted)
        webView.load(URLRequest(url: page, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        OrientationManager.allowLandscape = false
        requestOrientationUpdate()
    }

    private func requestOrientationUpdate() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    // MARK: - 控件

    private func buildControls() {
        topBar.backgroundColor = .clear
        view.addSubview(topBar)
        [backButton, restartButton, snapshotButton, infoButton, fullscreenButton].forEach(topBar.addSubview)

        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        restartButton.addTarget(self, action: #selector(restart), for: .touchUpInside)
        snapshotButton.addTarget(self, action: #selector(takeScreenshot), for: .touchUpInside)
        infoButton.addTarget(self, action: #selector(showInfo), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(toggleFullscreen), for: .touchUpInside)

        bottomBar.backgroundColor = Theme.playerBar
        bottomBar.layer.cornerRadius = 36
        view.addSubview(bottomBar)
        bottomBar.addSubview(playButton)
        bottomBar.addSubview(settingsButton)
        bottomBar.addSubview(volumeSlider)
        bottomBar.addSubview(speakerButton)

        let playConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: playConfig), for: .normal)
        playButton.tintColor = Theme.ink
        playButton.backgroundColor = .white
        playButton.layer.cornerRadius = 26
        playButton.clipsToBounds = true
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)

        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        speakerButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)

        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = isMuted ? 0 : 1
        volumeSlider.minimumTrackTintColor = .white
        volumeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        volumeSlider.thumbTintColor = .white
        volumeSlider.addTarget(self, action: #selector(volumeChanged(_:)), for: .valueChanged)

        // 双击进入/退出全屏，与原版手势一致。
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleFullscreen))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        webView.addGestureRecognizer(doubleTap)
    }

    private func buildErrorOverlay() {
        errorOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        errorOverlay.isHidden = true
        errorOverlay.alpha = 0
        view.addSubview(errorOverlay)

        errorCard.backgroundColor = Theme.playerBar
        errorCard.layer.cornerRadius = 22
        errorOverlay.addSubview(errorCard)

        errorTitleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        errorTitleLabel.textColor = .white
        errorTitleLabel.textAlignment = .center
        errorTitleLabel.numberOfLines = 0
        errorCard.addSubview(errorTitleLabel)

        errorBodyLabel.font = UIFont.systemFont(ofSize: 13)
        errorBodyLabel.textColor = UIColor.white.withAlphaComponent(0.66)
        errorBodyLabel.textAlignment = .center
        errorBodyLabel.numberOfLines = 0
        errorCard.addSubview(errorBodyLabel)

        style(errorButton: errorRetryButton, background: Theme.red, foreground: .white)
        errorRetryButton.addTarget(self, action: #selector(retryPlayback), for: .touchUpInside)
        errorCard.addSubview(errorRetryButton)

        style(errorButton: errorBackButton,
              background: UIColor.white.withAlphaComponent(0.14),
              foreground: .white)
        errorBackButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        errorCard.addSubview(errorBackButton)
    }

    private func style(errorButton button: UIButton, background: UIColor, foreground: UIColor) {
        button.backgroundColor = background
        button.setTitleColor(foreground, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 13
        button.clipsToBounds = true
    }

    private func applyLocalization() {
        backButton.accessibilityLabel = L("player.back")
        restartButton.accessibilityLabel = L("player.restart")
        snapshotButton.accessibilityLabel = L("player.snapshot")
        infoButton.accessibilityLabel = L("player.info")
        fullscreenButton.accessibilityLabel = chromeHidden ? L("player.exitFullscreen") : L("player.fullscreen")
        settingsButton.accessibilityLabel = L("settings.title")
        playButton.accessibilityLabel = isPlaying ? L("player.pause") : L("player.play")
        statusLabel.text = L("player.loading")
        errorTitleLabel.text = L("player.loadFailedTitle")
        errorBodyLabel.text = L("player.runtimeHint")
        errorRetryButton.setTitle(L("player.retryAction"), for: .normal)
        errorBackButton.setTitle(L("player.back"), for: .normal)
    }

    private func updatePlayButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let name = isPlaying ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
        playButton.accessibilityLabel = isPlaying ? L("player.pause") : L("player.play")
    }

    private func updateSpeaker() {
        let name = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        speakerButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
        speakerButton.accessibilityLabel = isMuted ? L("player.unmute") : L("player.mute")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let height = view.bounds.height
        webView.frame = view.bounds

        let topInset = view.safeAreaInsets.top
        let bottomInset = view.safeAreaInsets.bottom

        topBar.frame = CGRect(x: 0, y: topInset + 8, width: width, height: 44)
        var x: CGFloat = 16
        for button in [backButton, restartButton, snapshotButton, infoButton, fullscreenButton] {
            button.frame = CGRect(x: x, y: 0, width: 44, height: 44)
            x += 54
        }

        let barWidth = min(340, width - 32)
        bottomBar.frame = CGRect(x: (width - barWidth) / 2,
                                 y: height - bottomInset - 84,
                                 width: barWidth,
                                 height: 72)
        playButton.frame = CGRect(x: 14, y: 10, width: 52, height: 52)
        settingsButton.frame = CGRect(x: 78, y: 14, width: 44, height: 44)
        volumeSlider.frame = CGRect(x: 134, y: 24, width: barWidth - 134 - 56, height: 24)
        speakerButton.frame = CGRect(x: barWidth - 58, y: 14, width: 44, height: 44)

        statusLabel.frame = CGRect(x: 24, y: height / 2 - 20, width: width - 48, height: 40)

        errorOverlay.frame = view.bounds
        let cardWidth = min(width - 56, 340)
        let cardHeight: CGFloat = 286
        errorCard.frame = CGRect(x: (width - cardWidth) / 2,
                                 y: (height - cardHeight) / 2,
                                 width: cardWidth,
                                 height: cardHeight)
        let inner = cardWidth - 48
        errorTitleLabel.frame = CGRect(x: 24, y: 34, width: inner, height: 26)
        errorBodyLabel.frame = CGRect(x: 24, y: 70, width: inner, height: 96)
        errorRetryButton.frame = CGRect(x: 24, y: 186, width: inner, height: 46)
        errorBackButton.frame = CGRect(x: 24, y: 238, width: inner, height: 34)
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
        showErrorOverlay(reason: error.localizedDescription)
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

        case "panic":
            let reason = (payload as? String) ?? "renderer panic"
            showErrorOverlay(reason: reason)

        case "error":
            let reason = (payload as? String) ?? "unknown"
            if reason == "ruffle-missing" {
                showErrorOverlay(reason: reason)
                return
            }
            if !didRetryWithData, let data = try? Data(contentsOf: LibraryStore.shared.fileURL(for: item)),
               data.count < 30_000_000 {
                didRetryWithData = true
                callJS("SWF.loadData(\(jsStringLiteral(data.base64EncodedString())), \(jsStringLiteral(item.name)))")
            } else {
                showErrorOverlay(reason: reason)
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

    private func showErrorOverlay(reason: String) {
        NSLog("[SWFPlayer] playback failed: %@", reason)
        statusLabel.isHidden = true
        errorTitleLabel.text = L("player.loadFailedTitle")
        errorBodyLabel.text = L("player.runtimeHint")
        errorOverlay.isHidden = false
        UIView.animate(withDuration: 0.2) { self.errorOverlay.alpha = 1 }
    }

    private func hideErrorOverlay() {
        UIView.animate(withDuration: 0.18, animations: {
            self.errorOverlay.alpha = 0
        }, completion: { _ in
            self.errorOverlay.isHidden = true
        })
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

    @objc private func restart() {
        isPlaying = true
        updatePlayButton()
        hideErrorOverlay()
        statusLabel.text = L("player.loading")
        statusLabel.isHidden = false
        callJS("SWF.restart()")
    }

    @objc private func retryPlayback() {
        didRetryWithData = false
        restart()
    }

    @objc private func toggleMute() {
        isMuted.toggle()
        volumeSlider.value = isMuted ? 0 : 1
        callJS("SWF.setVolume(\(isMuted ? "0" : "1"))")
        updateSpeaker()
    }

    @objc private func volumeChanged(_ slider: UISlider) {
        isMuted = slider.value < 0.01
        callJS(String(format: "SWF.setVolume(%.3f)", Double(slider.value)))
        updateSpeaker()
    }

    @objc private func openSettings() {
        if isPlaying {
            isPlaying = false
            callJS("SWF.pause()")
            updatePlayButton()
        }
        let settings = SettingsViewController(style: .insetGrouped)
        let navigation = UINavigationController(rootViewController: settings)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func toggleFullscreen() {
        chromeHidden.toggle()
        OrientationManager.allowLandscape = chromeHidden
        requestOrientationUpdate()
        UIView.animate(withDuration: 0.22) {
            self.topBar.alpha = self.chromeHidden ? 0 : 1
            self.bottomBar.alpha = self.chromeHidden ? 0 : 1
        }
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        fullscreenButton.setImage(UIImage(systemName: chromeHidden ? "arrow.down.right.and.arrow.up.left"
                                                                  : "arrow.up.left.and.arrow.down.right",
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
                             y: view.bounds.height - view.safeAreaInsets.bottom - 176,
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
