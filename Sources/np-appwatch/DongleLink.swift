import CoreBluetooth
import Foundation

/// The dongle's control service (firmware/band-dongle/CONTROL.md in the main project), over the
/// link macOS already holds for the dongle as a keyboard and mouse.
final class DongleLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "4E500100-3C1A-4E0B-9D1E-6F2B5A7C8D90")
    static let status = CBUUID(string: "4E500101-3C1A-4E0B-9D1E-6F2B5A7C8D90")
    static let command = CBUUID(string: "4E500102-3C1A-4E0B-9D1E-6F2B5A7C8D90")

    enum State: Equatable {
        case unavailable(String)
        case searching
        case connecting
        case ready

        var title: String {
            switch self {
            case .unavailable(let why): why
            case .searching: "Looking for the dongle"
            case .connecting: "Connecting"
            case .ready: "Connected"
            }
        }
    }

    private(set) var state: State = .searching {
        didSet { if state != oldValue { log("Dongle: \(state.title)"); onChange?() } }
    }
    var onChange: (() -> Void)?
    /// The control service is ready (again): say which app is in front.
    var onReady: (() -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var writes: [(Error?) -> Void] = []
    private var statusReads: [(String?) -> Void] = []
    private var lookAgain: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Writes a command; `done` runs when the dongle acknowledged it.
    func send(_ text: String, done: @escaping (Error?) -> Void) {
        guard state == .ready, let peripheral, let commandCharacteristic else {
            return done(NSError(domain: "np-appwatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "not connected"]))
        }
        writes.append(done)
        peripheral.writeValue(Data(text.utf8), for: commandCharacteristic, type: .withResponse)
    }

    func readStatus(done: @escaping (String?) -> Void) {
        guard state == .ready, let peripheral, let statusCharacteristic else { return done(nil) }
        statusReads.append(done)
        if statusReads.count == 1 { peripheral.readValue(for: statusCharacteristic) }
    }

    // MARK: finding the dongle

    private func find() {
        guard central.state == .poweredOn, peripheral == nil else { return }
        state = .searching
        // Usually macOS is already connected to it (it's this Mac's keyboard and mouse).
        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.service]).first {
            central.stopScan()
            return connect(connected)
        }
        if !central.isScanning { central.scanForPeripherals(withServices: [Self.service]) }
        lookAgain?.invalidate()
        lookAgain = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.find() }
    }

    private func connect(_ found: CBPeripheral) {
        lookAgain?.invalidate()
        peripheral = found
        found.delegate = self
        state = .connecting
        central.connect(found)
    }

    private func reset(retryAfter delay: TimeInterval) {
        peripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        let failed = NSError(domain: "np-appwatch", code: 2, userInfo: [NSLocalizedDescriptionKey: "the dongle went away"])
        writes.forEach { $0(failed) }
        writes.removeAll()
        statusReads.forEach { $0(nil) }
        statusReads.removeAll()
        if central.state == .poweredOn { state = .searching }
        lookAgain?.invalidate()
        lookAgain = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.find() }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: find()
        case .poweredOff: state = .unavailable("Bluetooth is off")
        case .unauthorized: state = .unavailable("No Bluetooth permission (System Settings › Privacy & Security › Bluetooth)")
        case .unsupported: state = .unavailable("This Mac has no Bluetooth LE")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Couldn't connect: \(error?.localizedDescription ?? "no reason given")")
        reset(retryAfter: 3)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        reset(retryAfter: 2)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            log("The dongle has no control service: \(error?.localizedDescription ?? "is its firmware too old?")")
            return central.cancelPeripheralConnection(peripheral)
        }
        peripheral.discoverCharacteristics([Self.status, Self.command], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        commandCharacteristic = nil
        statusCharacteristic = nil
        state = .connecting
        peripheral.discoverServices([Self.service])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.command { commandCharacteristic = characteristic }
            if characteristic.uuid == Self.status { statusCharacteristic = characteristic }
        }
        guard commandCharacteristic != nil else {
            log("The dongle's control service has no command characteristic")
            return central.cancelPeripheralConnection(peripheral)
        }
        state = .ready
        onReady?()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.command, !writes.isEmpty else { return }
        writes.removeFirst()(error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.status else { return }
        let text = error == nil ? characteristic.value.flatMap { String(data: $0, encoding: .utf8) } : nil
        let readers = statusReads
        statusReads.removeAll()
        readers.forEach { $0(text) }
    }
}
