import UIKit

/// 设置行：独立白色卡片 + 图标 + 标题/副标题 + 右侧配件。
final class SettingCell: UITableViewCell {
    enum Accessory {
        case none
        case chevron
        case toggle
        case value
    }

    private let container = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView()
    private let valueLabel = UILabel()
    private var toggleSwitch: UISwitch?

    var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        container.backgroundColor = Theme.card
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = Theme.hairline.cgColor
        Theme.applyCardShadow(container, radius: 8, opacity: 0.035)
        contentView.addSubview(container)

        iconView.contentMode = .center
        container.addSubview(iconView)

        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Theme.ink
        container.addSubview(titleLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = Theme.secondary
        subtitleLabel.numberOfLines = 2
        container.addSubview(subtitleLabel)

        chevron.image = UIImage(systemName: "chevron.right",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        chevron.tintColor = Theme.secondary
        chevron.contentMode = .center
        container.addSubview(chevron)

        valueLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = Theme.secondary
        valueLabel.textAlignment = .right
        container.addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(icon: String?,
                   iconColor: UIColor = Theme.ink,
                   title: String,
                   titleColor: UIColor = Theme.ink,
                   subtitle: String?,
                   accessory: Accessory,
                   value: String? = nil,
                   toggleOn: Bool = false) {
        toggleSwitch?.removeFromSuperview()
        toggleSwitch = nil
        onToggle = nil

        if let icon = icon {
            iconView.isHidden = false
            iconView.image = UIImage(systemName: icon,
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            iconView.tintColor = iconColor
        } else {
            iconView.isHidden = true
            iconView.image = nil
        }

        titleLabel.text = title
        titleLabel.textColor = titleColor

        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle == nil)

        chevron.isHidden = true
        valueLabel.isHidden = true
        valueLabel.text = nil

        switch accessory {
        case .none:
            break
        case .chevron:
            chevron.isHidden = false
        case .value:
            valueLabel.isHidden = false
            valueLabel.text = value
        case .toggle:
            let control = UISwitch()
            control.isOn = toggleOn
            control.onTintColor = Theme.red
            control.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            container.addSubview(control)
            toggleSwitch = control
        }
        setNeedsLayout()
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        onToggle?(sender.isOn)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.frame = CGRect(x: 20, y: 3, width: bounds.width - 40, height: bounds.height - 6)
        let width = container.bounds.width
        let height = container.bounds.height
        let textX: CGFloat = iconView.isHidden ? 18 : 54

        iconView.frame = CGRect(x: 16, y: (height - 26) / 2, width: 26, height: 26)

        if subtitleLabel.isHidden {
            titleLabel.frame = CGRect(x: textX, y: (height - 21) / 2, width: width - textX - 64, height: 21)
        } else {
            titleLabel.frame = CGRect(x: textX, y: 13, width: width - textX - 64, height: 21)
            subtitleLabel.frame = CGRect(x: textX, y: 35, width: width - textX - 64, height: 17)
        }

        chevron.frame = CGRect(x: width - 32, y: (height - 16) / 2, width: 16, height: 16)
        valueLabel.sizeToFit()
        valueLabel.frame = CGRect(x: width - 20 - valueLabel.bounds.width,
                                  y: (height - 20) / 2,
                                  width: valueLabel.bounds.width,
                                  height: 20)
        toggleSwitch?.frame = CGRect(x: width - 20 - 51, y: (height - 31) / 2, width: 51, height: 31)
    }
}

final class SettingsViewController: UITableViewController {

    private enum Row {
        case autoPlay
        case startMuted
        case clearHistory
        case feedback
        case rate
        case language
        case version
        case engine
    }

    private struct Section {
        let title: String
        let rows: [Row]
    }

    private var languageObserver: NSObjectProtocol?

    // 统一用 plain + 自绘卡片，才能做到每个设置项独立圆角卡片（与参考图一致）。
    override init(style: UITableView.Style) {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var sections: [Section] {
        [
            Section(title: L("settings.sectionPlayer"), rows: [.autoPlay, .startMuted]),
            Section(title: L("settings.sectionData"), rows: [.clearHistory]),
            Section(title: L("settings.sectionSupport"), rows: [.feedback, .rate]),
            Section(title: L("settings.sectionAbout"), rows: [.language, .version, .engine])
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false

        let navigationBar = navigationController?.navigationBar
        navigationBar?.tintColor = Theme.red
        navigationBar?.shadowImage = UIImage()
        navigationBar?.setBackgroundImage(UIImage(), for: .default)
        navigationBar?.isTranslucent = false
        navigationBar?.barTintColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.left",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            style: .plain,
            target: self,
            action: #selector(close)
        )
        navigationItem.leftBarButtonItem?.tintColor = Theme.red

        let titleLabel = UILabel()
        titleLabel.text = "SETTINGS"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .heavy)
        titleLabel.textColor = Theme.red
        titleLabel.attributedText = NSAttributedString(
            string: "SETTINGS",
            attributes: [
                .kern: NSNumber(value: 3.0),
                .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                .foregroundColor: Theme.red
            ]
        )
        titleLabel.accessibilityLabel = L("settings.title")
        navigationItem.titleView = titleLabel

        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let observer = languageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func close() { dismiss(animated: true) }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .autoPlay, .startMuted, .clearHistory, .feedback, .rate:
            return 72
        case .language, .version, .engine:
            return 62
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        let label = UILabel()
        label.text = sections[section].title.uppercased()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.secondary
        label.frame = CGRect(x: 24, y: 18, width: tableView.bounds.width - 48, height: 16)
        container.addSubview(label)
        return container
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? 34 : 46
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        4
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = (tableView.dequeueReusableCell(withIdentifier: "SettingCell") as? SettingCell)
            ?? SettingCell(style: .default, reuseIdentifier: "SettingCell")
        let row = sections[indexPath.section].rows[indexPath.row]

        switch row {
        case .autoPlay:
            cell.configure(icon: "play.circle.fill",
                           iconColor: Theme.red,
                           title: L("settings.autoPlay"),
                           subtitle: L("settings.autoPlaySub"),
                           accessory: .toggle,
                           toggleOn: PlaybackPreferences.autoPlay)
            cell.onToggle = { PlaybackPreferences.autoPlay = $0 }

        case .startMuted:
            cell.configure(icon: "speaker.slash.fill",
                           iconColor: Theme.ink,
                           title: L("settings.startMuted"),
                           subtitle: L("settings.startMutedSub"),
                           accessory: .toggle,
                           toggleOn: PlaybackPreferences.startMuted)
            cell.onToggle = { PlaybackPreferences.startMuted = $0 }

        case .clearHistory:
            cell.configure(icon: "trash.fill",
                           iconColor: Theme.red,
                           title: L("settings.clearHistory"),
                           titleColor: Theme.red,
                           subtitle: L("settings.clearHistorySub", librarySize()),
                           accessory: .chevron)

        case .feedback:
            cell.configure(icon: "bubble.left",
                           iconColor: Theme.ink,
                           title: L("settings.feedback"),
                           subtitle: L("settings.feedbackSub"),
                           accessory: .chevron)

        case .rate:
            cell.configure(icon: "star.fill",
                           iconColor: Theme.ink,
                           title: L("settings.rate"),
                           subtitle: L("settings.rateSub"),
                           accessory: .chevron)

        case .language:
            cell.configure(icon: "globe",
                           iconColor: Theme.ink,
                           title: L("settings.languageRow"),
                           subtitle: nil,
                           accessory: .value,
                           value: L10n.shared.preference.displayName)

        case .version:
            cell.configure(icon: "info.circle",
                           iconColor: Theme.ink,
                           title: L("settings.version"),
                           subtitle: nil,
                           accessory: .value,
                           value: "\(BuildInfo.appVersion) (\(BuildInfo.buildNumber))")

        case .engine:
            cell.configure(icon: "bolt.fill",
                           iconColor: Theme.red,
                           title: L("settings.engineRow"),
                           subtitle: nil,
                           accessory: .value,
                           value: "Ruffle \(BuildInfo.ruffleVersion)")
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .clearHistory:
            confirmClear()
        case .feedback:
            openLink("https://github.com/OperationSkuld/swf-player-community/issues")
        case .rate:
            showRateInfo()
        case .language:
            presentLanguageSheet()
        case .autoPlay, .startMuted, .version, .engine:
            break
        }
    }

    // MARK: - 动作

    private func presentLanguageSheet() {
        let sheet = UIAlertController(title: L("settings.languageRow"), message: nil, preferredStyle: .actionSheet)
        for language in AppLanguage.allCases {
            let mark = language == L10n.shared.preference ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: mark + language.displayName, style: .default) { _ in
                L10n.shared.preference = language
            })
        }
        sheet.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func confirmClear() {
        let alert = UIAlertController(title: L("settings.clearHistoryTitle"),
                                      message: L("settings.clearHistoryMessage"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("settings.clearAction"), style: .destructive) { [weak self] _ in
            LibraryStore.shared.clearAll()
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func showRateInfo() {
        let alert = UIAlertController(title: L("settings.rate"),
                                      message: L("settings.rateInfo"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("settings.openGitHub"), style: .default) { [weak self] _ in
            self?.openLink("https://github.com/OperationSkuld/swf-player-community")
        })
        present(alert, animated: true)
    }

    private func openLink(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    private func librarySize() -> String {
        let directory = LibraryStore.shared.swfDirectoryURL
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory,
                                                          includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        var total: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return BuildInfo.humanReadableSize(total)
    }
}
