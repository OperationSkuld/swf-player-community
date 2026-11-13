import UIKit

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case language
        case about
        case data
    }

    private enum AboutRow: Int, CaseIterable {
        case description
        case version
        case edition
        case engine
        case restrictions
        case licenses
    }

    private var languageObserver: NSObjectProtocol?

    override init(style: UITableView.Style) {
        super.init(style: style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationController?.navigationBar.tintColor = Theme.red
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L("settings.done"), style: .done, target: self, action: #selector(close)
        )
        title = L("settings.title")

        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshStrings()
        }
    }

    private func refreshStrings() {
        title = L("settings.title")
        navigationItem.rightBarButtonItem?.title = L("settings.done")
        tableView.reloadData()
    }

    @objc private func close() { dismiss(animated: true) }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .language: return AppLanguage.allCases.count
        case .about: return AboutRow.allCases.count
        case .data: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .language: return L("settings.sectionLanguage")
        case .about: return L("settings.sectionAbout")
        case .data: return L("settings.sectionData")
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == Section.language.rawValue ? L("settings.languageHint") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SettingsCell")
        let detail = cell.detailTextLabel
        let text = cell.textLabel
        text?.font = UIFont.systemFont(ofSize: 15)
        text?.numberOfLines = 0
        detail?.font = UIFont.systemFont(ofSize: 12)
        detail?.numberOfLines = 0
        detail?.text = nil
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.imageView?.image = nil

        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .language:
            let language = AppLanguage.allCases[indexPath.row]
            text?.text = language.displayName
            cell.accessoryType = language == L10n.shared.preference ? .checkmark : .none
            cell.tintColor = Theme.red

        case .about:
            guard let row = AboutRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .description:
                text?.text = L("settings.aboutText")
                text?.font = UIFont.systemFont(ofSize: 12.5)
                text?.textColor = Theme.secondary
                cell.selectionStyle = .none
            case .version:
                text?.text = L("settings.version")
                detail?.text = "\(BuildInfo.appVersion) (\(BuildInfo.buildNumber))"
                cell.selectionStyle = .none
            case .edition:
                text?.text = L("settings.edition")
                detail?.text = BuildInfo.edition
                cell.selectionStyle = .none
            case .engine:
                text?.text = L("settings.engine", BuildInfo.ruffleVersion)
                cell.selectionStyle = .none
            case .restrictions:
                text?.text = L("settings.noLimits")
                text?.textColor = Theme.red
                cell.selectionStyle = .none
            case .licenses:
                text?.text = L("settings.license")
                cell.accessoryType = .disclosureIndicator
            }

        case .data:
            text?.text = L("settings.clearHistory")
            text?.textColor = Theme.red
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .language:
            L10n.shared.preference = AppLanguage.allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: Section.language.rawValue), with: .automatic)

        case .about:
            guard AboutRow(rawValue: indexPath.row) == .licenses else { return }
            let alert = UIAlertController(title: L("settings.license"),
                                          message: L("settings.licenseText"),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
            present(alert, animated: true)

        case .data:
            let alert = UIAlertController(title: L("settings.clearHistoryTitle"),
                                          message: L("settings.clearHistoryMessage"),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: L("settings.clearAction"), style: .destructive) { _ in
                LibraryStore.shared.clearAll()
            })
            present(alert, animated: true)
        }
    }
}
