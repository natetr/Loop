//
//  SettingsTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import InsulinKit
import LoopKit
import RileyLinkKit
import MinimedKit

private let ConfigCellIdentifier = "ConfigTableViewCell"

private let EnabledString = NSLocalizedString("Enabled", comment: "The detail text describing an enabled setting")
private let TapToSetString = NSLocalizedString("Tap to set", comment: "The empty-state text for a configuration value")


final class SettingsTableViewController: UITableViewController, DailyValueScheduleTableViewControllerDelegate {

    @IBOutlet var devicesSectionTitleView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 44

        tableView.register(RileyLinkDeviceTableViewCell.nib(), forCellReuseIdentifier: RileyLinkDeviceTableViewCell.className)

        dataManagerObserver = NotificationCenter.default.addObserver(forName: nil, object: dataManager, queue: nil) { [weak self = self] (note) -> Void in
            DispatchQueue.main.async {
                if let deviceManager = self?.dataManager.rileyLinkManager {
                    switch note.name {
                    case Notification.Name.DeviceManagerDidDiscoverDevice:
                        self?.tableView.insertRows(at: [IndexPath(row: deviceManager.devices.count - 1, section: Section.devices.rawValue)], with: .automatic)
                    case Notification.Name.DeviceConnectionStateDidChange,
                         Notification.Name.DeviceRSSIDidChange,
                         Notification.Name.DeviceNameDidChange:
                      if let device = note.userInfo?[RileyLinkDeviceManager.RileyLinkDeviceKey] as? RileyLinkDevice, let index = deviceManager.devices.index(where: { $0 === device }) {
                            self?.tableView.reloadRows(at: [IndexPath(row: index, section: Section.devices.rawValue)], with: .none)
                        }
                    default:
                        break
                    }
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        dataManager.rileyLinkManager.setDeviceScanningEnabled(true)

        if case .some = dataManager.cgm, dataManager.loopManager.glucoseStore.authorizationRequired {
            dataManager.loopManager.glucoseStore.authorize { (success, error) -> Void in
                // Do nothing for now
            }
        }

        AnalyticsManager.shared.didDisplaySettingsScreen()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        dataManager.rileyLinkManager.setDeviceScanningEnabled(false)
    }

    deinit {
        dataManagerObserver = nil
    }

    var dataManager: DeviceDataManager!

    private var dataManagerObserver: Any? {
        willSet {
            if let observer = dataManagerObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    fileprivate enum Section: Int, CaseCountable {
        case loop = 0
        case devices
        case pump
        case cgm
        case configuration
        case services
    }

    fileprivate enum LoopRow: Int, CaseCountable {
        case dosing = 0
        case preferredInsulinDataSource
        case diagnostic
    }

    fileprivate enum PumpRow: Int, CaseCountable {
        case pumpID = 0
        case batteryChemistry
    }

    fileprivate enum CGMRow: Int, CaseCountable {
        case enlite = 0
        case g4
        case g5
        case dexcomShare      // only displayed if g4 or g5 switched on
        case g5TransmitterID  // only displayed if g5 switched on
    }

    fileprivate enum ConfigurationRow: Int, CaseCountable {
        case glucoseTargetRange = 0
        case suspendThreshold
        case insulinModel
        case basalRate
        case carbRatio
        case insulinSensitivity
        case maxBasal
        case maxBolus
    }

    fileprivate enum ServiceRow: Int, CaseCountable {
        case nightscout = 0
        case mLab
        case loggly
        case amplitude
    }

    fileprivate lazy var valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let vc as InsulinModelSettingsViewController:
            vc.insulinModel = dataManager.loopManager.insulinModelSettings?.model

            if let insulinSensitivitySchedule = dataManager.loopManager.insulinSensitivitySchedule {
                vc.insulinSensitivitySchedule = insulinSensitivitySchedule
            }

            dataManager.loopManager.glucoseStore.preferredUnit { (unit, error) in
                DispatchQueue.main.async {
                    if let unit = unit {
                        vc.glucoseUnit = unit
                    }

                    vc.delegate = self
                }
            }
        default:
            break
        }
    }
    
    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .loop:
            return LoopRow.count
        case .pump:
            return PumpRow.count
        case .cgm:
            switch dataManager.cgm {
            case .g4?:
                return CGMRow.count - 1  // No Transmitter ID cell
            case .g5?:
                return CGMRow.count
            default:
                return CGMRow.count - 2  // No Share or Transmitter ID cell
            }
        case .configuration:
            return ConfigurationRow.count
        case .devices:
            return dataManager.rileyLinkManager.devices.count
        case .services:
            return ServiceRow.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .dosing:
                let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

                switchCell.switch?.isOn = dataManager.loopManager.settings.dosingEnabled
                switchCell.textLabel?.text = NSLocalizedString("Closed Loop", comment: "The title text for the looping enabled switch cell")

                switchCell.switch?.addTarget(self, action: #selector(dosingEnabledChanged(_:)), for: .valueChanged)

                return switchCell
            case .preferredInsulinDataSource:
                let cell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

                cell.textLabel?.text = NSLocalizedString("Preferred Data Source", comment: "The title text for the preferred insulin data source config")
                cell.detailTextLabel?.text = String(describing: dataManager.preferredInsulinDataSource)

                return cell
            case .diagnostic:
                let cell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

                cell.textLabel?.text = NSLocalizedString("Issue Report", comment: "The title text for the issue report cell")
                cell.detailTextLabel?.text = nil

                return cell
            }
        case .pump:
            let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)
            switch PumpRow(rawValue: indexPath.row)! {
            case .pumpID:
                configCell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                configCell.detailTextLabel?.text = dataManager.pumpID ?? TapToSetString
            case .batteryChemistry:
                configCell.textLabel?.text = NSLocalizedString("Pump Battery Type", comment: "The title text for the battery type value")
                configCell.detailTextLabel?.text = String(describing: dataManager.batteryChemistry)
            }
            return configCell
        case .cgm:
            let row = CGMRow(rawValue: indexPath.row)!
            switch row {
            case .dexcomShare:
                let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)
                let shareService = dataManager.remoteDataManager.shareService

                configCell.textLabel?.text = shareService.title
                configCell.detailTextLabel?.text = shareService.username ?? TapToSetString

                return configCell
            case .g5TransmitterID:
                let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

                configCell.textLabel?.text = NSLocalizedString("Transmitter ID", comment: "The title text for the Dexcom G5 transmitter ID config value")

                if case .g5(let transmitterID)? = dataManager.cgm {
                    configCell.detailTextLabel?.text = transmitterID ?? TapToSetString
                }

                return configCell
            default:
                let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

                switch row {
                case .enlite:
                    switchCell.switch?.isOn = dataManager.cgm == .enlite
                    switchCell.textLabel?.text = NSLocalizedString("Sof-Sensor / Enlite", comment: "The title text for the Medtronic sensor switch cell")
                    switchCell.switch?.addTarget(self, action: #selector(enliteChanged(_:)), for: .valueChanged)
                case .g4:
                    switchCell.switch?.isOn = dataManager.cgm == .g4
                    switchCell.textLabel?.text = NSLocalizedString("G4 Share Receiver", comment: "The title text for the G4 Share Receiver switch cell")
                    switchCell.switch?.addTarget(self, action: #selector(g4Changed(_:)), for: .valueChanged)
                case .g5:
                    if case .g5? = dataManager.cgm {
                        switchCell.switch?.isOn = true
                    } else {
                        switchCell.switch?.isOn = false
                    }

                    switchCell.textLabel?.text = NSLocalizedString("G5 Transmitter", comment: "The title text for the G5 Transmitter switch cell")
                    switchCell.switch?.addTarget(self, action: #selector(g5Changed(_:)), for: .valueChanged)
                case .dexcomShare, .g5TransmitterID:
                    assertionFailure()
                }

                return switchCell
            }
        case .configuration:
            let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .basalRate:
                configCell.textLabel?.text = NSLocalizedString("Basal Rates", comment: "The title text for the basal rate schedule")

                if let basalRateSchedule = dataManager.loopManager.basalRateSchedule {
                    configCell.detailTextLabel?.text = "\(basalRateSchedule.total()) U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .carbRatio:
                configCell.textLabel?.text = NSLocalizedString("Carb Ratios", comment: "The title text for the carb ratio schedule")

                if let carbRatioSchedule = dataManager.loopManager.carbRatioSchedule {
                    let unit = carbRatioSchedule.unit
                    let value = valueNumberFormatter.string(from: NSNumber(value: carbRatioSchedule.averageQuantity().doubleValue(for: unit))) ?? "—"

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for carb ratio average. (1: value)(2: carb unit)"), value, unit)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .insulinSensitivity:
                configCell.textLabel?.text = NSLocalizedString("Insulin Sensitivities", comment: "The title text for the insulin sensitivity schedule")

                if let insulinSensitivitySchedule = dataManager.loopManager.insulinSensitivitySchedule {
                    let unit = insulinSensitivitySchedule.unit
                    let value = valueNumberFormatter.string(from: NSNumber(value: insulinSensitivitySchedule.averageQuantity().doubleValue(for: unit))) ?? "—"

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@/U", comment: "Format string for insulin sensitivity average (1: value)(2: glucose unit)"), value, unit.glucoseUnitDisplayString)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .glucoseTargetRange:
                configCell.textLabel?.text = NSLocalizedString("Correction Range", comment: "The title text for the glucose target range schedule")

                if let glucoseTargetRangeSchedule = dataManager.loopManager.settings.glucoseTargetRangeSchedule {
                    let unit = glucoseTargetRangeSchedule.unit
                    let value = glucoseTargetRangeSchedule.value(at: Date())
                    let minTarget = valueNumberFormatter.string(from: NSNumber(value: value.minValue)) ?? "—"
                    let maxTarget = valueNumberFormatter.string(from: NSNumber(value: value.maxValue)) ?? "—"

                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ – %2$@ %3$@", comment: "Format string for glucose target range. (1: Min target)(2: Max target)(3: glucose unit)"), minTarget, maxTarget, unit.glucoseUnitDisplayString)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .suspendThreshold:
                configCell.textLabel?.text = NSLocalizedString("Suspend Threshold", comment: "The title text in settings")
                
                if let suspendThreshold = dataManager.loopManager.settings.suspendThreshold {
                    let value = valueNumberFormatter.string(from: NSNumber(value: suspendThreshold.value)) ?? "-"
                    configCell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ %2$@", comment: "Format string for current suspend threshold. (1: value)(2: bg unit)"), value, suspendThreshold.unit.glucoseUnitDisplayString)
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .insulinModel:
                configCell.textLabel?.text = NSLocalizedString("Insulin Model", comment: "The title text for the insulin model setting row")

                if let settings = dataManager.loopManager.insulinModelSettings {
                    configCell.detailTextLabel?.text = settings.title
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .maxBasal:
                configCell.textLabel?.text = NSLocalizedString("Maximum Basal Rate", comment: "The title text for the maximum basal rate value")

                if let maxBasal = dataManager.loopManager.settings.maximumBasalRatePerHour {
                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.string(from: NSNumber(value: maxBasal))!) U/hour"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            case .maxBolus:
                configCell.textLabel?.text = NSLocalizedString("Maximum Bolus", comment: "The title text for the maximum bolus value")

                if let maxBolus = dataManager.loopManager.settings.maximumBolus {
                    configCell.detailTextLabel?.text = "\(valueNumberFormatter.string(from: NSNumber(value: maxBolus))!) U"
                } else {
                    configCell.detailTextLabel?.text = TapToSetString
                }
            }

            return configCell
        case .devices:
            let deviceCell = tableView.dequeueReusableCell(withIdentifier: RileyLinkDeviceTableViewCell.className) as! RileyLinkDeviceTableViewCell
            let device = dataManager.rileyLinkManager.devices[indexPath.row]

            deviceCell.configureCellWithName(device.name,
                signal: device.RSSI,
                peripheralState: device.peripheral.state
            )

            deviceCell.connectSwitch.addTarget(self, action: #selector(deviceConnectionChanged(_:)), for: .valueChanged)

            return deviceCell
        case .services:
            let configCell = tableView.dequeueReusableCell(withIdentifier: ConfigCellIdentifier, for: indexPath)

            switch ServiceRow(rawValue: indexPath.row)! {
            case .nightscout:
                let nightscoutService = dataManager.remoteDataManager.nightscoutService

                configCell.textLabel?.text = nightscoutService.title
                configCell.detailTextLabel?.text = nightscoutService.siteURL?.absoluteString ?? TapToSetString
            case .mLab:
                let mLabService = dataManager.logger.mLabService

                configCell.textLabel?.text = mLabService.title
                configCell.detailTextLabel?.text = mLabService.databaseName ?? TapToSetString
            case .loggly:
                let logglyService = dataManager.logger.logglyService

                configCell.textLabel?.text = logglyService.title
                configCell.detailTextLabel?.text = logglyService.isAuthorized ? EnabledString : TapToSetString
            case .amplitude:
                let amplitudeService = AnalyticsManager.shared.amplitudeService

                configCell.textLabel?.text = amplitudeService.title
                configCell.detailTextLabel?.text = amplitudeService.isAuthorized ? EnabledString : TapToSetString
            }

            return configCell
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .loop:
            return Bundle.main.localizedNameAndVersion
        case .pump:
            return NSLocalizedString("Pump", comment: "The title of the pump section in settings")
        case .cgm:
            return NSLocalizedString("Continuous Glucose Monitor", comment: "The title of the continuous glucose monitor section in settings")
        case .configuration:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        case .devices:
            return nil
        case .services:
            return NSLocalizedString("Services", comment: "The title of the services section in settings")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        switch Section(rawValue: indexPath.section)! {
        case .cgm:
            switch CGMRow(rawValue: indexPath.row)! {
            case .dexcomShare, .g5TransmitterID:
                return 1
            default:
                break
            }
        default:
            break
        }

        return 0
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)

        switch Section(rawValue: indexPath.section)! {
        case .pump:
            let row = PumpRow(rawValue: indexPath.row)!
            switch row {
            case .pumpID:
                let vc: TextFieldTableViewController
                switch row {
                case .pumpID:
                    vc = PumpIDTableViewController(pumpID: dataManager.pumpID, region: dataManager.pumpState?.pumpRegion)
                default:
                    fatalError()
                }
                vc.title = sender?.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self

                show(vc, sender: indexPath)
            case .batteryChemistry:
                let vc = RadioSelectionTableViewController.batteryChemistryType(dataManager.batteryChemistry)
                vc.title = sender?.textLabel?.text
                vc.delegate = self

                show(vc, sender: sender)
            }
        case .cgm:
            switch CGMRow(rawValue: indexPath.row)! {
            case .dexcomShare:
                let service = dataManager.remoteDataManager.shareService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.shareService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .g5TransmitterID:
                let vc: TextFieldTableViewController
                var value: String?

                if case .g5(let transmitterID)? = dataManager.cgm {
                    value = transmitterID
                }

                vc = .transmitterID(value)
                vc.title = sender?.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self

                show(vc, sender: indexPath)
            default:
                break
            }
        case .configuration:
            let row = ConfigurationRow(rawValue: indexPath.row)!
            switch row {
            case .maxBasal, .maxBolus:
                let vc: TextFieldTableViewController

                switch row {
                case .maxBasal:
                    vc = .maxBasal(dataManager.loopManager.settings.maximumBasalRatePerHour)
                case .maxBolus:
                    vc = .maxBolus(dataManager.loopManager.settings.maximumBolus)
                default:
                    fatalError()
                }

                vc.title = sender?.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self

                show(vc, sender: indexPath)
            case .basalRate:
                let scheduleVC = SingleValueScheduleTableViewController()

                if let profile = dataManager.loopManager.basalRateSchedule {
                    scheduleVC.timeZone = profile.timeZone
                    scheduleVC.scheduleItems = profile.items
                }
                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Basal Rates", comment: "The title of the basal rate profile screen")

                show(scheduleVC, sender: sender)
            case .carbRatio:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Carb Ratios", comment: "The title of the carb ratios schedule screen")
                scheduleVC.unit = .gram()

                if let schedule = dataManager.loopManager.carbRatioSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit
                }

                show(scheduleVC, sender: sender)
            case .insulinSensitivity:
                let scheduleVC = DailyQuantityScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Insulin Sensitivities", comment: "The title of the insulin sensitivities schedule screen")

                if let schedule = dataManager.loopManager.insulinSensitivitySchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit

                    show(scheduleVC, sender: sender)
                } else {
                    dataManager.loopManager.glucoseStore.preferredUnit { (unit, error) -> Void in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.presentAlertController(with: error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.show(scheduleVC, sender: sender)
                            }
                        }
                    }
                }
            case .glucoseTargetRange:
                let scheduleVC = GlucoseRangeScheduleTableViewController()

                scheduleVC.delegate = self
                scheduleVC.title = NSLocalizedString("Correction Range", comment: "The title of the glucose target range schedule screen")

                if let schedule = dataManager.loopManager.settings.glucoseTargetRangeSchedule {
                    scheduleVC.timeZone = schedule.timeZone
                    scheduleVC.scheduleItems = schedule.items
                    scheduleVC.unit = schedule.unit
                    scheduleVC.overrideRanges = schedule.overrideRanges

                    show(scheduleVC, sender: sender)
                } else {
                    dataManager.loopManager.glucoseStore.preferredUnit { (unit, error) -> Void in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.presentAlertController(with: error)
                            } else if let unit = unit {
                                scheduleVC.unit = unit
                                self.show(scheduleVC, sender: sender)
                            }
                        }
                    }
                }
            case .suspendThreshold:
                if let minBGGuard = dataManager.loopManager.settings.suspendThreshold {
                    let vc = GlucoseThresholdTableViewController(threshold: minBGGuard.value, glucoseUnit: minBGGuard.unit)
                    vc.delegate = self
                    vc.indexPath = indexPath
                    vc.title = sender?.textLabel?.text
                    self.show(vc, sender: sender)
                } else {
                    dataManager.loopManager.glucoseStore.preferredUnit { (unit, error) -> Void in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.presentAlertController(with: error)
                            } else if let unit = unit {
                                let vc = GlucoseThresholdTableViewController(threshold: nil, glucoseUnit: unit)
                                vc.delegate = self
                                vc.indexPath = indexPath
                                vc.title = sender?.textLabel?.text
                                self.show(vc, sender: sender)
                            }
                        }
                    }
                }
            case .insulinModel:
                performSegue(withIdentifier: InsulinModelSettingsViewController.className, sender: sender)
            }
        case .devices:
            let vc = RileyLinkDeviceTableViewController()
            vc.device = dataManager.rileyLinkManager.devices[indexPath.row]

            show(vc, sender: sender)
        case .loop:
            switch LoopRow(rawValue: indexPath.row)! {
            case .preferredInsulinDataSource:
                let vc = RadioSelectionTableViewController.insulinDataSource(dataManager.preferredInsulinDataSource)
                vc.title = sender?.textLabel?.text
                vc.delegate = self

                show(vc, sender: sender)
            case .diagnostic:
                let vc = CommandResponseViewController.generateDiagnosticReport(dataManager: dataManager)
                vc.title = sender?.textLabel?.text

                show(vc, sender: sender)
            case .dosing:
                break
            }
        case .services:
            switch ServiceRow(rawValue: indexPath.row)! {
            case .nightscout:
                let service = dataManager.remoteDataManager.nightscoutService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.nightscoutService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .mLab:
                let service = dataManager.logger.mLabService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.logger.mLabService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .loggly:
                let service = dataManager.logger.logglyService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.logger.logglyService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            case .amplitude:
                let service = AnalyticsManager.shared.amplitudeService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    AnalyticsManager.shared.amplitudeService = service

                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }

                show(vc, sender: sender)
            }
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .devices:
            return devicesSectionTitleView
        case .loop, .pump, .cgm, .configuration, .services:
            return nil
        }
    }

    // MARK: - Device mangement

    @objc private func dosingEnabledChanged(_ sender: UISwitch) {
        dataManager.loopManager.settings.dosingEnabled = sender.isOn
    }

    @objc private func deviceConnectionChanged(_ connectSwitch: UISwitch) {
        let switchOrigin = connectSwitch.convert(CGPoint.zero, to: tableView)

        if let indexPath = tableView.indexPathForRow(at: switchOrigin), indexPath.section == Section.devices.rawValue
        {
            let device = dataManager.rileyLinkManager.devices[indexPath.row]

            if connectSwitch.isOn {
                dataManager.connectToRileyLink(device)
            } else {
                dataManager.disconnectFromRileyLink(device)
            }
        }
    }

    // MARK: - CGM State

    // MARK: Model

    /// Temporarily caches the last transmitter ID so curious switch-flippers don't lose it!
    private var g5TransmitterID: String?

    @objc private func g5Changed(_ sender: UISwitch) {
        tableView.beginUpdates()
        if sender.isOn {
            setG4SwitchOff()
            setEnliteSwitchOff()
            let shareRowExists = tableView.numberOfRows(inSection: Section.cgm.rawValue) > CGMRow.dexcomShare.rawValue
            dataManager.cgm = .g5(transmitterID: g5TransmitterID)

            var indexPaths = [IndexPath(row: CGMRow.g5TransmitterID.rawValue, section:Section.cgm.rawValue)]
            if !shareRowExists {
                indexPaths.insert(IndexPath(row: CGMRow.dexcomShare.rawValue, section:Section.cgm.rawValue), at: 0)
            }

            tableView.insertRows(at: indexPaths, with: .top)
        } else {
            removeDexcomShareRow()
            removeG5TransmitterIDRow()
            dataManager.cgm = nil
        }
        tableView.endUpdates()
    }

    @objc private func g4Changed(_ sender: UISwitch) {
        tableView.beginUpdates()
        if sender.isOn {
            setG5SwitchOff()
            setEnliteSwitchOff()
            removeG5TransmitterIDRow()
            let shareRowExists = tableView.numberOfRows(inSection: Section.cgm.rawValue) > CGMRow.dexcomShare.rawValue
            dataManager.cgm = .g4

            if !shareRowExists {
                tableView.insertRows(at: [IndexPath(row: CGMRow.dexcomShare.rawValue, section:Section.cgm.rawValue)], with: .top)
            }
        } else {
            removeDexcomShareRow()
            dataManager.cgm = nil
        }
        tableView.endUpdates()
    }

    @objc func enliteChanged(_ sender: UISwitch) {
        tableView.beginUpdates()
        if sender.isOn {
            setG5SwitchOff()
            setG4SwitchOff()
            removeDexcomShareRow()
            removeG5TransmitterIDRow()
            dataManager.cgm = .enlite
        } else {
            dataManager.cgm = nil
        }
        tableView.endUpdates()
    }

    // MARK: Views

    private func removeDexcomShareRow() {
        switch dataManager.cgm {
        case .g4?, .g5?:
            tableView.deleteRows(at: [IndexPath(row: CGMRow.dexcomShare.rawValue, section: Section.cgm.rawValue)], with: .top)
        default:
            break;
        }
    }

    private func removeG5TransmitterIDRow() {
        if case .g5(let transmitterID)? = dataManager.cgm {
            g5TransmitterID = transmitterID
            tableView.deleteRows(at: [IndexPath(row: CGMRow.g5TransmitterID.rawValue, section: Section.cgm.rawValue)], with: .top)
        }
    }

    private func setG5SwitchOff() {
        let switchCell = tableView.cellForRow(at: IndexPath(row: CGMRow.g5.rawValue, section: Section.cgm.rawValue)) as! SwitchTableViewCell
        switchCell.switch?.setOn(false, animated: true)
    }

    private func setG4SwitchOff() {
        let switchCell = tableView.cellForRow(at: IndexPath(row: CGMRow.g4.rawValue, section: Section.cgm.rawValue)) as! SwitchTableViewCell
        switchCell.switch?.setOn(false, animated: true)
    }

    private func setEnliteSwitchOff() {
        let switchCell = tableView.cellForRow(at: IndexPath(row: CGMRow.enlite.rawValue, section: Section.cgm.rawValue)) as! SwitchTableViewCell
        switchCell.switch?.setOn(false, animated: true)
    }

    // MARK: - DailyValueScheduleTableViewControllerDelegate

    func dailyValueScheduleTableViewControllerWillFinishUpdating(_ controller: DailyValueScheduleTableViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .basalRate:
                    if let controller = controller as? SingleValueScheduleTableViewController {
                        dataManager.loopManager.basalRateSchedule = BasalRateSchedule(dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                        AnalyticsManager.shared.didChangeBasalRateSchedule()
                    }
                case .glucoseTargetRange:
                    if let controller = controller as? GlucoseRangeScheduleTableViewController {
                        dataManager.loopManager.settings.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone, overrideRanges: controller.overrideRanges, override: dataManager.loopManager.settings.glucoseTargetRangeSchedule?.override)
                        AnalyticsManager.shared.didChangeGlucoseTargetRangeSchedule()
                    }
                case let row:
                    if let controller = controller as? DailyQuantityScheduleTableViewController {
                        switch row {
                        case .carbRatio:
                            dataManager.loopManager.carbRatioSchedule = CarbRatioSchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                            AnalyticsManager.shared.didChangeCarbRatioSchedule()
                        case .insulinSensitivity:
                            dataManager.loopManager.insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: controller.unit, dailyItems: controller.scheduleItems, timeZone: controller.timeZone)
                            AnalyticsManager.shared.didChangeInsulinSensitivitySchedule()
                        default:
                            break
                        }
                    }
                }

                tableView.reloadRows(at: [indexPath], with: .none)
            default:
                break
            }
        }
    }
}


extension SettingsTableViewController: InsulinModelSettingsViewControllerDelegate {
    func insulinModelSettingsViewControllerDidChangeValue(_ controller: InsulinModelSettingsViewController) {
        guard let indexPath = self.tableView.indexPathForSelectedRow else {
            return
        }

        switch Section(rawValue: indexPath.section)! {
        case .configuration:
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .insulinModel:
                if let model = controller.insulinModel {
                    dataManager.loopManager.insulinModelSettings = InsulinModelSettings(model: model)
                }

                tableView.reloadRows(at: [indexPath], with: .none)
            default:
                assertionFailure()
            }
        default:
            assertionFailure()
        }
    }
}


extension SettingsTableViewController: RadioSelectionTableViewControllerDelegate {
    func radioSelectionTableViewControllerDidChangeSelectedIndex(_ controller: RadioSelectionTableViewController) {
        if let indexPath = self.tableView.indexPathForSelectedRow {
            switch Section(rawValue: indexPath.section)! {
            case .loop:
                switch LoopRow(rawValue: indexPath.row)! {
                case .preferredInsulinDataSource:
                    if let selectedIndex = controller.selectedIndex, let dataSource = InsulinDataSource(rawValue: selectedIndex) {
                        dataManager.preferredInsulinDataSource = dataSource

                        tableView.reloadRows(at: [IndexPath(row: LoopRow.preferredInsulinDataSource.rawValue, section: Section.loop.rawValue)], with: .none)
                    }
                default:
                    assertionFailure()
                }

            case .pump:
                switch PumpRow(rawValue: indexPath.row)! {
                case .batteryChemistry:
                    if let selectedIndex = controller.selectedIndex, let dataSource = BatteryChemistryType(rawValue: selectedIndex) {
                        dataManager.batteryChemistry = dataSource

                        tableView.reloadRows(at: [IndexPath(row: PumpRow.batteryChemistry.rawValue, section: Section.configuration.rawValue)], with: .none)
                    }
                default:
                    assertionFailure()
                }
            default:
                assertionFailure()
            }
        }
    }
}

extension SettingsTableViewController: TextFieldTableViewControllerDelegate {
    func textFieldTableViewControllerDidEndEditing(_ controller: TextFieldTableViewController) {
        if let indexPath = controller.indexPath {
            switch Section(rawValue: indexPath.section)! {
            case .pump:
                switch PumpRow(rawValue: indexPath.row)! {
                case .pumpID:
                    dataManager.pumpID = controller.value

                    if  let controller = controller as? PumpIDTableViewController,
                        let region = controller.region
                    {
                        dataManager.pumpState?.pumpRegion = region
                    }
                default:
                    assertionFailure()
                }
            case .cgm:
                switch CGMRow(rawValue: indexPath.row)! {
                case .g5TransmitterID:
                    var transmitterID = controller.value

                    if transmitterID?.isEmpty ?? false {
                        transmitterID = nil
                    }

                    dataManager.cgm = .g5(transmitterID: transmitterID)
                default:
                    assertionFailure()
                }
            case .configuration:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .suspendThreshold:
                    if let controller = controller as? GlucoseThresholdTableViewController,
                        let value = controller.value, let minBGGuard = valueNumberFormatter.number(from: value)?.doubleValue {
                        dataManager.loopManager.settings.suspendThreshold = GlucoseThreshold(unit: controller.glucoseUnit, value: minBGGuard)
                    } else {
                        dataManager.loopManager.settings.suspendThreshold = nil
                    }
                case .maxBasal:
                    if let value = controller.value, let rate = valueNumberFormatter.number(from: value)?.doubleValue {
                        dataManager.loopManager.settings.maximumBasalRatePerHour = rate
                    } else {
                        dataManager.loopManager.settings.maximumBasalRatePerHour = nil
                    }
                case .maxBolus:
                    if let value = controller.value, let units = valueNumberFormatter.number(from: value)?.doubleValue {
                        dataManager.loopManager.settings.maximumBolus = units
                    } else {
                        dataManager.loopManager.settings.maximumBolus = nil
                    }
                default:
                    assertionFailure()
                }
            default:
                assertionFailure()
            }
        }

        tableView.reloadData()
    }

    func textFieldTableViewControllerDidReturn(_ controller: TextFieldTableViewController) {
        _ = navigationController?.popViewController(animated: true)
    }
}


extension SettingsTableViewController: PumpIDTableViewControllerDelegate {
    func pumpIDTableViewControllerDidChangePumpRegion(_ controller: PumpIDTableViewController) {
        if let region = controller.region {
            dataManager.pumpState?.pumpRegion = region
        }
    }
}
