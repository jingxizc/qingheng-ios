import Combine
@preconcurrency import CoreBluetooth
import Foundation

struct ScaleMeasurement: Identifiable, Equatable {
    let id = UUID()
    let weightKg: Double
    let measuredAt: Date
    let deviceID: UUID
    let deviceName: String
}

struct ScaleDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

@MainActor
final class BluetoothScaleManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case bluetoothOff
        case permissionDenied
        case idle
        case scanning
        case connecting(String)
        case connected(String)
        case error(String)

        var title: String {
            switch self {
            case .bluetoothOff: "蓝牙未开启"
            case .permissionDenied: "需要蓝牙权限"
            case .idle: "等待连接"
            case .scanning: "正在寻找体重秤"
            case let .connecting(name): "正在连接 \(name)"
            case let .connected(name): "已连接 \(name)"
            case let .error(message): message
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var devices: [ScaleDevice] = []
    @Published private(set) var liveWeightKg: Double?
    @Published private(set) var latestMeasurement: ScaleMeasurement?
    @Published private(set) var connectedDeviceName: String?

    private static let weightService = CBUUID(string: "181D")
    private static let bodyCompositionService = CBUUID(string: "181B")
    private static let weightMeasurement = CBUUID(string: "2A9D")
    private static let bodyCompositionMeasurement = CBUUID(string: "2A9C")
    private static let bindingPolicyVersion = 2

    private enum ReadingOrigin {
        case advertisement
        case characteristic
    }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var shouldMonitor = false
    private var lastPublishedWeight: Double?
    private var lastPublishedAt: Date?
    private var lastUnstableAtByDevice: [UUID: Date] = [:]

    private var selectedDeviceID: UUID? {
        get {
            guard let value = UserDefaults.standard.string(forKey: "selectedScaleID") else {
                return nil
            }
            return UUID(uuidString: value)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: "selectedScaleID")
        }
    }

    override init() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: "scaleBindingPolicyVersion") < Self.bindingPolicyVersion {
            // Earlier versions silently selected the first scale discovered nearby.
            // Require one explicit selection after upgrading so that old unsafe
            // bindings cannot continue syncing another person's device.
            defaults.removeObject(forKey: "selectedScaleID")
            defaults.set(Self.bindingPolicyVersion, forKey: "scaleBindingPolicyVersion")
        }

        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.qingheng.scale.central"]
        )
    }

    func startMonitoring() {
        shouldMonitor = true
        guard central.state == .poweredOn else {
            updateState(for: central.state)
            return
        }
        beginScan()
    }

    func stopMonitoring() {
        shouldMonitor = false
        central.stopScan()
        if connectedPeripheral == nil {
            state = .idle
        }
    }

    func connect(to device: ScaleDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        selectedDeviceID = peripheral.identifier
        resetReadingSession()
        connect(peripheral)
    }

    func forgetScale() {
        selectedDeviceID = nil
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        connectedDeviceName = nil
        liveWeightKg = nil
        latestMeasurement = nil
        devices = []
        resetReadingSession()
        if shouldMonitor, central.state == .poweredOn {
            beginScan()
        }
    }

    private func beginScan() {
        guard !central.isScanning, connectedPeripheral == nil else { return }
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.weightService, Self.bodyCompositionService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard connectedPeripheral?.identifier != peripheral.identifier else { return }
        central.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        let name = displayName(for: peripheral)
        state = .connecting(name)
        central.connect(
            peripheral,
            options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ]
        )
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false ? name : nil) ?? "小米体重秤"
    }

    private func handle(
        _ reading: ParsedScaleReading,
        from peripheral: CBPeripheral,
        origin: ReadingOrigin
    ) {
        guard selectedDeviceID == peripheral.identifier else { return }
        let now = Date()

        if !reading.isStable {
            liveWeightKg = reading.weightKg
            lastUnstableAtByDevice[peripheral.identifier] = now
            return
        }

        if origin == .advertisement {
            guard let activityAt = lastUnstableAtByDevice[peripheral.identifier],
                  now.timeIntervalSince(activityAt) >= 0,
                  now.timeIntervalSince(activityAt) <= 45
            else {
                // Xiaomi scales can keep advertising their last stable value after
                // the person has stepped off. A fresh session must first contain a
                // changing/non-stable reading before its stable result is accepted.
                return
            }
        }

        liveWeightKg = reading.weightKg
        lastUnstableAtByDevice[peripheral.identifier] = nil
        if let lastPublishedWeight,
           let lastPublishedAt,
           abs(lastPublishedWeight - reading.weightKg) < 0.02,
           now.timeIntervalSince(lastPublishedAt) < 20 {
            return
        }

        self.lastPublishedWeight = reading.weightKg
        self.lastPublishedAt = now
        latestMeasurement = ScaleMeasurement(
            weightKg: reading.weightKg,
            measuredAt: now,
            deviceID: peripheral.identifier,
            deviceName: displayName(for: peripheral)
        )
    }

    private func resetReadingSession() {
        lastUnstableAtByDevice = [:]
        lastPublishedWeight = nil
        lastPublishedAt = nil
    }

    private func parseAdvertisements(
        _ advertisementData: [String: Any],
        peripheral: CBPeripheral
    ) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey]
                as? [CBUUID: Data]
        else {
            return
        }

        if let data = serviceData[Self.weightService],
           let reading = ScaleDataParser.parseXiaomiWeightAdvertisement(data) {
            handle(reading, from: peripheral, origin: .advertisement)
        }

        if let data = serviceData[Self.bodyCompositionService] {
            let reading = ScaleDataParser.parseXiaomiBodyComposition(data)
                ?? ScaleDataParser.parseStandardBodyComposition(data)
            if let reading {
                handle(reading, from: peripheral, origin: .advertisement)
            }
        }
    }

    private func updateState(for bluetoothState: CBManagerState) {
        switch bluetoothState {
        case .poweredOn:
            if shouldMonitor { beginScan() }
        case .poweredOff:
            state = .bluetoothOff
        case .unauthorized:
            state = .permissionDenied
        case .unsupported:
            state = .error("此设备不支持蓝牙低功耗")
        case .resetting:
            state = .error("蓝牙正在重新启动")
        case .unknown:
            state = .idle
        @unknown default:
            state = .idle
        }
    }
}

extension BluetoothScaleManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateState(for: central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripherals[peripheral.identifier] = peripheral

        let device = ScaleDevice(
            id: peripheral.identifier,
            name: displayName(for: peripheral),
            rssi: RSSI.intValue
        )
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { $0.rssi > $1.rssi }
        }

        guard let selectedDeviceID,
              selectedDeviceID == peripheral.identifier
        else {
            return
        }

        parseAdvertisements(advertisementData, peripheral: peripheral)
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard selectedDeviceID == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        let name = displayName(for: peripheral)
        connectedDeviceName = name
        state = .connected(name)
        peripheral.discoverServices([Self.weightService, Self.bodyCompositionService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        state = .error(error?.localizedDescription ?? "体重秤连接失败")
        if shouldMonitor { beginScan() }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        connectedDeviceName = nil
        liveWeightKg = nil
        state = error.map { .error($0.localizedDescription) } ?? .scanning
        if shouldMonitor { beginScan() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let selectedDeviceID,
              let restored = dict[CBCentralManagerRestoredStatePeripheralsKey]
                as? [CBPeripheral],
              let peripheral = restored.first(where: { $0.identifier == selectedDeviceID })
        else {
            if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey]
                as? [CBPeripheral] {
                restored.forEach(central.cancelPeripheralConnection)
            }
            return
        }
        peripherals[peripheral.identifier] = peripheral
        connectedPeripheral = peripheral
        peripheral.delegate = self
    }
}

extension BluetoothScaleManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(
                [Self.weightMeasurement, Self.bodyCompositionMeasurement],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        service.characteristics?
            .filter {
                $0.uuid == Self.weightMeasurement
                    || $0.uuid == Self.bodyCompositionMeasurement
            }
            .forEach { peripheral.setNotifyValue(true, for: $0) }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              selectedDeviceID == peripheral.identifier,
              let data = characteristic.value
        else {
            return
        }

        let reading: ParsedScaleReading?
        switch characteristic.uuid {
        case Self.weightMeasurement:
            reading = ScaleDataParser.parseStandardWeightMeasurement(data)
        case Self.bodyCompositionMeasurement:
            reading = ScaleDataParser.parseXiaomiBodyComposition(data)
                ?? ScaleDataParser.parseStandardBodyComposition(data)
        default:
            reading = nil
        }

        if let reading {
            handle(reading, from: peripheral, origin: .characteristic)
        }
    }
}
