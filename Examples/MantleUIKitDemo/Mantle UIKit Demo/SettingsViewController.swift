//
//  SettingsViewController.swift
//  Mantle UIKit Demo
//
//  Changes the mantle live: which demo, backgrounds, dimming, visibility, and
//  moving it to each of the current demo's detents.
//

import Mantle
import UIKit

final class SettingsViewController: UITableViewController {
    private var settings: DemoSettings
    private let onChange: (DemoSettings) -> Void
    private let onMove: (MantleDetent) -> Void

    private enum Section: Int, CaseIterable {
        case demo, background, behaviour, moveTo
    }

    init(settings: DemoSettings, onChange: @escaping (DemoSettings) -> Void, onMove: @escaping (MantleDetent) -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.onMove = onMove
        super.init(style: .insetGrouped)
        title = "Mantle"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    private func update(_ change: (inout DemoSettings) -> Void) {
        change(&settings)
        onChange(settings)
        tableView.reloadData()
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .demo: MantleDemo.allCases.count
        case .background: 2
        case .behaviour: 2
        case .moveTo: settings.demo.detents.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .demo: "Demo"
        case .background: "Background"
        case .behaviour: "Behaviour"
        case .moveTo: "Move to"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section) == .demo ? settings.demo.explanation.replacingOccurrences(of: "`", with: "") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .demo:
            let demo = MantleDemo.allCases[indexPath.row]
            content.text = demo.rawValue
            cell.accessoryType = demo == settings.demo ? .checkmark : .none

        case .background:
            let isCollapsed = indexPath.row == 0
            content.text = isCollapsed ? "Collapsed" : "Expanded"
            let control = UISegmentedControl(items: BackgroundChoice.allCases.map(\.rawValue))
            let current = isCollapsed ? settings.collapsedBackground : settings.expandedBackground
            control.selectedSegmentIndex = BackgroundChoice.allCases.firstIndex(of: current) ?? 0
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let control else { return }
                let choice = BackgroundChoice.allCases[control.selectedSegmentIndex]
                self?.update { isCollapsed ? ($0.collapsedBackground = choice) : ($0.expandedBackground = choice) }
            }, for: .valueChanged)
            cell.accessoryView = control
            cell.selectionStyle = .none

        case .behaviour:
            let isDimming = indexPath.row == 0
            content.text = isDimming ? "Dim background" : "Show mantle"
            let toggle = UISwitch()
            toggle.isOn = isDimming ? settings.dims : settings.showsMantle
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let isOn = toggle?.isOn else { return }
                self?.update { isDimming ? ($0.dims = isOn) : ($0.showsMantle = isOn) }
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none

        case .moveTo:
            content.text = settings.demo.detents[indexPath.row].description
            content.textProperties.color = .tintColor
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .demo: update { $0.demo = MantleDemo.allCases[indexPath.row] }
        case .moveTo: onMove(settings.demo.detents[indexPath.row])
        default: break
        }
    }
}
