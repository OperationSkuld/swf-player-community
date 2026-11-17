import UIKit
import UniformTypeIdentifiers

// MARK: - 首页头部（品牌 + 设置入口 + 导入卡片 + 最近播放标题）

final class HomeHeaderView: UIView {
    var onImport: (() -> Void)?
    var onSettings: (() -> Void)?
    var onOpenURL: (() -> Void)?

    /// 精简后只保留：品牌行、导入卡、网址入口、最近播放标题。
    static let preferredHeight: CGFloat = 288

    private let brandIcon = RoundedIconView(symbol: "bolt.fill", size: 44,
                                            background: Theme.red, tint: .white, corner: 13)
    private let brandLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let settingsButton = Controls.chipButton(systemName: "gearshape", accessibility: "")

    private let importCard = GradientView()
    private let importIconBox = UIView()
    private let importIcon = UIImageView()
    private let importTitle = UILabel()
    private let importSubtitle = UILabel()
    private let importChevron = UIImageView()

    private let urlButton = UIButton(type: .system)
    private let recentLabel = UILabel()
    private let countBadge = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        build()
        applyLocalization()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        addSubview(brandIcon)

        brandLabel.font = UIFont.systemFont(ofSize: 17, weight: .heavy)
        brandLabel.textColor = Theme.ink
        addSubview(brandLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = Theme.secondary
        addSubview(subtitleLabel)

        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        addSubview(settingsButton)

        importCard.layer.cornerRadius = 18
        importCard.layer.shadowColor = Theme.red.cgColor
        importCard.layer.shadowOpacity = 0.28
        importCard.layer.shadowOffset = CGSize(width: 0, height: 10)
        importCard.layer.shadowRadius = 18
        importCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(importTapped)))
        addSubview(importCard)

        importIconBox.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        importIconBox.layer.cornerRadius = 15
        importCard.addSubview(importIconBox)

        importIcon.image = UIImage(systemName: "folder.fill",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        importIcon.tintColor = .white
        importIcon.contentMode = .center
        importIconBox.addSubview(importIcon)

        importTitle.font = UIFont.systemFont(ofSize: 19, weight: .bold)
        importTitle.textColor = .white
        importCard.addSubview(importTitle)

        importSubtitle.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        importSubtitle.textColor = UIColor.white.withAlphaComponent(0.85)
        importSubtitle.numberOfLines = 2
        importCard.addSubview(importSubtitle)

        importChevron.image = UIImage(systemName: "chevron.right",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        importChevron.tintColor = .white
        importChevron.contentMode = .center
        importCard.addSubview(importChevron)

        urlButton.backgroundColor = .white
        urlButton.layer.cornerRadius = 14
        urlButton.layer.borderWidth = 1
        urlButton.layer.borderColor = Theme.hairline.cgColor
        urlButton.addTarget(self, action: #selector(urlTapped), for: .touchUpInside)
        addSubview(urlButton)

        recentLabel.font = UIFont.systemFont(ofSize: 17, weight: .heavy)
        recentLabel.textColor = Theme.ink
        addSubview(recentLabel)

        countBadge.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        countBadge.textColor = Theme.red
        countBadge.backgroundColor = Theme.softRed
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 9
        countBadge.clipsToBounds = true
        addSubview(countBadge)
    }

    func applyLocalization() {
        brandLabel.attributedText = NSAttributedString(
            string: "SWF PLAYER",
            attributes: [
                .kern: NSNumber(value: 0.6),
                .font: UIFont.systemFont(ofSize: 17, weight: .heavy),
                .foregroundColor: Theme.ink
            ]
        )
        subtitleLabel.text = "\(L("home.brandSub")) v\(BuildInfo.appVersion)"
        importTitle.text = L("home.importTitle")
        importSubtitle.text = L("home.importSub")
        recentLabel.text = L("home.recent")
        settingsButton.accessibilityLabel = L("settings.title")
        applyURLButtonStyle()
        setNeedsLayout()
    }

    private func applyURLButtonStyle() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "link",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        config.imagePadding = 8
        config.baseForegroundColor = Theme.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        var title = AttributedString(L("home.openURL"))
        title.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        config.attributedTitle = title
        urlButton.configuration = config
        urlButton.accessibilityLabel = L("home.openURL")
    }

    @objc private func urlTapped() { onOpenURL?() }

    func updateCount(_ count: Int) {
        countBadge.isHidden = count == 0
        countBadge.text = count > 99 ? "99+" : "\(count)"
        setNeedsLayout()
    }

    @objc private func importTapped() {
        UIView.animate(withDuration: 0.08, animations: { self.importCard.alpha = 0.85 }) { _ in
            UIView.animate(withDuration: 0.14) { self.importCard.alpha = 1.0 }
        }
        onImport?()
    }

    @objc private func settingsTapped() { onSettings?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let pad: CGFloat = 20

        brandIcon.frame = CGRect(x: pad, y: 16, width: 44, height: 44)
        let textWidth = width - pad * 2 - 56 - 48
        brandLabel.frame = CGRect(x: pad + 56, y: 17, width: textWidth, height: 21)
        subtitleLabel.frame = CGRect(x: pad + 56, y: 39, width: textWidth, height: 16)

        let chipSize: CGFloat = 34
        settingsButton.frame = CGRect(x: width - pad - chipSize, y: 21, width: chipSize, height: chipSize)

        let cardWidth = width - pad * 2
        importCard.frame = CGRect(x: pad, y: 76, width: cardWidth, height: 104)
        importIconBox.frame = CGRect(x: 16, y: 24, width: 56, height: 56)
        importIcon.frame = importIconBox.bounds
        importTitle.frame = CGRect(x: 88, y: 30, width: cardWidth - 88 - 44, height: 24)
        importSubtitle.frame = CGRect(x: 88, y: 56, width: cardWidth - 88 - 44, height: 34)
        importChevron.frame = CGRect(x: cardWidth - 38, y: 42, width: 20, height: 20)

        urlButton.frame = CGRect(x: pad, y: 192, width: cardWidth, height: 44)

        let recentY: CGFloat = 256
        recentLabel.sizeToFit()
        recentLabel.frame = CGRect(x: pad, y: recentY, width: recentLabel.bounds.width, height: 24)
        let badgeWidth: CGFloat = max(22, countBadge.intrinsicContentSize.width + 14)
        countBadge.frame = CGRect(x: recentLabel.frame.maxX + 8, y: recentY + 3,
                                  width: badgeWidth, height: 18)
    }
}

// MARK: - 最近播放列表单元

final class SWFItemCell: UITableViewCell {
    static let reuseIdentifier = "SWFItemCell"

    private let container = UIView()
    private let thumbView = GradientView()
    private let thumbImage = UIImageView()
    private let boltImage = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let playIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        container.backgroundColor = Theme.card
        container.layer.cornerRadius = 16
        Theme.applyCardShadow(container, radius: 10, opacity: 0.06)
        contentView.addSubview(container)

        thumbView.layer.cornerRadius = 12
        thumbView.clipsToBounds = true
        container.addSubview(thumbView)

        boltImage.image = UIImage(systemName: "bolt.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold))
        boltImage.tintColor = .white
        boltImage.contentMode = .center
        thumbView.addSubview(boltImage)

        thumbImage.contentMode = .scaleAspectFill
        thumbImage.clipsToBounds = true
        thumbImage.layer.cornerRadius = 12
        container.addSubview(thumbImage)

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.ink
        titleLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(titleLabel)

        detailLabel.font = UIFont.systemFont(ofSize: 12)
        detailLabel.textColor = Theme.secondary
        container.addSubview(detailLabel)

        playIcon.image = UIImage(systemName: "play.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        playIcon.tintColor = Theme.secondary
        playIcon.contentMode = .center
        container.addSubview(playIcon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: SWFItem) {
        titleLabel.text = item.name
        if let date = item.lastPlayedAt {
            detailLabel.text = L("home.lastPlayed", Theme.dateFormatter.string(from: date))
        } else {
            detailLabel.text = L("home.neverPlayed")
        }

        if let coverURL = LibraryStore.shared.coverURL(for: item),
           let image = UIImage(contentsOfFile: coverURL.path) {
            thumbImage.image = image
            thumbImage.isHidden = false
            boltImage.isHidden = true
        } else {
            thumbImage.image = nil
            thumbImage.isHidden = true
            boltImage.isHidden = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        container.frame = CGRect(x: 20, y: 4, width: width - 40, height: bounds.height - 8)
        let cardWidth = container.bounds.width
        let thumbSide: CGFloat = 52
        thumbView.frame = CGRect(x: 12, y: (container.bounds.height - thumbSide) / 2,
                                 width: thumbSide, height: thumbSide)
        boltImage.frame = thumbView.bounds
        thumbImage.frame = thumbView.frame

        let textX: CGFloat = 12 + thumbSide + 14
        titleLabel.frame = CGRect(x: textX, y: 14, width: cardWidth - textX - 40, height: 20)
        detailLabel.frame = CGRect(x: textX, y: 35, width: cardWidth - textX - 40, height: 17)
        playIcon.frame = CGRect(x: cardWidth - 34, y: (container.bounds.height - 18) / 2, width: 18, height: 18)
    }
}

// MARK: - 首页控制器

final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = HomeHeaderView(frame: CGRect(x: 0, y: 0,
                                                          width: UIScreen.main.bounds.width,
                                                          height: HomeHeaderView.preferredHeight))
    private var languageObserver: NSObjectProtocol?

    private let loadingOverlay = UIView()
    private let loadingCard = UIView()
    private let loadingSpinner = UIActivityIndicatorView(style: .large)
    private let loadingLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SWFItemCell.self, forCellReuseIdentifier: SWFItemCell.reuseIdentifier)
        tableView.tableHeaderView = headerView
        view.addSubview(tableView)

        headerView.onImport = { [weak self] in self?.presentImporter() }
        headerView.onSettings = { [weak self] in self?.presentSettings() }
        headerView.onOpenURL = { [weak self] in self?.presentURLLoader() }

        buildLoadingOverlay()

        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.headerView.applyLocalization()
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let observer = languageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        headerView.updateCount(LibraryStore.shared.items.count)
        tableView.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
        let top = view.safeAreaInsets.top
        if abs(tableView.contentInset.top - top) > 0.5 {
            tableView.contentInset = UIEdgeInsets(top: top, left: 0, bottom: 28, right: 0)
            tableView.verticalScrollIndicatorInsets.top = top
        }
        if abs(headerView.bounds.width - view.bounds.width) > 0.5 {
            headerView.frame = CGRect(x: 0, y: 0,
                                      width: view.bounds.width,
                                      height: HomeHeaderView.preferredHeight)
            tableView.tableHeaderView = headerView
        }

        loadingOverlay.frame = view.bounds
        let cardSize = CGSize(width: 150, height: 118)
        loadingCard.frame = CGRect(x: (view.bounds.width - cardSize.width) / 2,
                                   y: (view.bounds.height - cardSize.height) / 2,
                                   width: cardSize.width, height: cardSize.height)
        loadingSpinner.frame = CGRect(x: (cardSize.width - 36) / 2, y: 22, width: 36, height: 36)
        loadingLabel.frame = CGRect(x: 10, y: 66, width: cardSize.width - 20, height: 36)
    }

    // MARK: 从网址加载

    private func buildLoadingOverlay() {
        loadingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        loadingOverlay.isHidden = true
        view.addSubview(loadingOverlay)

        loadingCard.backgroundColor = UIColor(hex: 0x1C1C1E)
        loadingCard.layer.cornerRadius = 16
        loadingOverlay.addSubview(loadingCard)

        loadingSpinner.color = .white
        loadingCard.addSubview(loadingSpinner)

        loadingLabel.text = L("home.urlLoading")
        loadingLabel.textColor = .white
        loadingLabel.font = UIFont.systemFont(ofSize: 12.5)
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 2
        loadingCard.addSubview(loadingLabel)
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        if loading {
            loadingSpinner.startAnimating()
            view.bringSubviewToFront(loadingOverlay)
        } else {
            loadingSpinner.stopAnimating()
        }
    }

    private func presentURLLoader() {
        let alert = UIAlertController(title: L("home.urlTitle"),
                                      message: L("home.urlMessage"),
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = L("home.urlPlaceholder")
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("home.urlLoad"), style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let text = alert?.textFields?.first?.text ?? ""
            self.startRemoteLoad(text)
        })
        present(alert, animated: true)
    }

    private func normalizedRemoteURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              (url.host?.isEmpty == false) else { return nil }
        return url
    }

    private func startRemoteLoad(_ raw: String) {
        guard let url = normalizedRemoteURL(raw) else {
            showSimpleAlert(title: L("home.urlFailedTitle"), message: L("home.urlInvalid"))
            return
        }

        setLoading(true)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
                         + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        // 不少老 Flash 站点会校验 Referer，这里补上同源值。
        if let scheme = url.scheme, let host = url.host {
            request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setLoading(false)

                if let error = error {
                    self.showSimpleAlert(title: L("home.urlFailedTitle"),
                                         message: error.localizedDescription)
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    self.showSimpleAlert(title: L("home.urlFailedTitle"),
                                         message: L("home.urlHTTPError", String(http.statusCode)))
                    return
                }
                guard let data = data, !data.isEmpty else {
                    self.showSimpleAlert(title: L("home.urlFailedTitle"),
                                         message: L("home.urlInvalid"))
                    return
                }
                guard data.count <= 60 * 1024 * 1024 else {
                    self.showSimpleAlert(title: L("home.urlFailedTitle"),
                                         message: L("home.urlTooLarge"))
                    return
                }

                let signature = String(decoding: data.prefix(3), as: UTF8.self)
                guard ["FWS", "CWS", "ZWS"].contains(signature) else {
                    self.showSimpleAlert(title: L("home.urlFailedTitle"),
                                         message: L("home.urlNotSWF"))
                    return
                }

                let decodedName = url.lastPathComponent.removingPercentEncoding ?? ""
                let name = decodedName.isEmpty ? "remote.swf" : decodedName
                do {
                    let item = try LibraryStore.shared.importRemote(data: data, fileName: name)
                    self.headerView.updateCount(LibraryStore.shared.items.count)
                    self.tableView.reloadData()
                    self.open(item: item)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription
                        ?? L("home.importErrorGeneric")
                    self.showSimpleAlert(title: L("home.importErrorTitle"), message: message)
                }
            }
        }.resume()
    }

    private func showSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    // MARK: 导入

    private func presentImporter() {
        let swfType = UTType(filenameExtension: "swf") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [swfType, .data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var firstItem: SWFItem?
        for url in urls {
            do {
                let item = try LibraryStore.shared.importFile(from: url)
                if firstItem == nil { firstItem = item }
            } catch {
                presentImportError(error)
                return
            }
        }
        headerView.updateCount(LibraryStore.shared.items.count)
        tableView.reloadData()
        if let item = firstItem { open(item: item) }
    }

    private func presentImportError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? L("home.importErrorGeneric")
        let alert = UIAlertController(title: L("home.importErrorTitle"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    // MARK: 导航

    func open(item: SWFItem) {
        LibraryStore.shared.touch(item.id)
        headerView.updateCount(LibraryStore.shared.items.count)
        tableView.reloadData()
        let player = PlayerViewController(item: item)
        navigationController?.pushViewController(player, animated: true)
    }

    private func presentSettings() {
        let settings = SettingsViewController(style: .plain)
        let navigation = UINavigationController(rootViewController: settings)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    // MARK: UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(LibraryStore.shared.items.count, 1)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        LibraryStore.shared.items.isEmpty ? 110 : 80
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !LibraryStore.shared.items.isEmpty else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: "EmptyCell")
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 6
            label.attributedText = NSAttributedString(
                string: "\(L("home.emptyTitle"))\n\(L("home.emptyHint"))",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: Theme.secondary,
                    .paragraphStyle: paragraph
                ]
            )
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 36),
                label.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -36),
                label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 20)
            ])
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: SWFItemCell.reuseIdentifier, for: indexPath) as? SWFItemCell else {
            return UITableViewCell()
        }
        cell.configure(with: LibraryStore.shared.items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !LibraryStore.shared.items.isEmpty else { return }
        open(item: LibraryStore.shared.items[indexPath.row])
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !LibraryStore.shared.items.isEmpty else { return nil }
        let item = LibraryStore.shared.items[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: L("home.deleteAction")) { [weak self] _, _, completion in
            self?.confirmDelete(item)
            completion(true)
        }
        delete.backgroundColor = Theme.red

        let share = UIContextualAction(style: .normal, title: L("home.shareAction")) { [weak self] _, _, completion in
            guard let self = self else { completion(true); return }
            let url = LibraryStore.shared.fileURL(for: item)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self.present(activity, animated: true)
            completion(true)
        }
        share.backgroundColor = UIColor(hex: 0x3A3A3C)
        return UISwipeActionsConfiguration(actions: [delete, share])
    }

    private func confirmDelete(_ item: SWFItem) {
        let alert = UIAlertController(title: L("home.deleteConfirmTitle"),
                                      message: L("home.deleteConfirmMessage"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("common.delete"), style: .destructive) { [weak self] _ in
            LibraryStore.shared.remove(item.id)
            self?.headerView.updateCount(LibraryStore.shared.items.count)
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
