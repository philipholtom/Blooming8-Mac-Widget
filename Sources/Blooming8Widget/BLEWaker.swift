import CoreBluetooth
import Foundation

/// Sends a Bluetooth "wake" pulse to a Blooming8 frame so its Wi-Fi radio
/// comes back up after it's gone to sleep. Ported from a Python/bleak script
/// already confirmed working against this hardware: scan for the frame by
/// its advertised name, connect, discover services, and write a
/// 0x01-then-0x00 pulse to whichever of two known characteristics it exposes.
@MainActor
final class BLEWaker: NSObject {
    private static let wakeCharUUIDs: Set<CBUUID> = [
        CBUUID(string: "0000F001-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")
    ]

    private var centralManager: CBCentralManager?
    private var targetPeripheral: CBPeripheral?
    private var targetName = ""
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didPulseAnyCharacteristic = false

    /// Scans for a BLE peripheral advertising `deviceName`, connects, and writes
    /// a wake pulse to its known characteristic(s). Returns true once at least
    /// one pulse was sent — not a guarantee the frame actually woke, just that
    /// the BLE side of things succeeded.
    func wake(deviceName: String, timeout: TimeInterval = 20) async -> Bool {
        guard continuation == nil else { return false } // a wake is already in progress
        guard !deviceName.isEmpty else { return false }

        targetName = deviceName
        didPulseAnyCharacteristic = false

        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.finish(false)
            }
        }
    }

    private func finish(_ success: Bool) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        centralManager?.stopScan()
        if let peripheral = targetPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        targetPeripheral = nil
        centralManager = nil
        cont.resume(returning: success)
    }

    private func pulseAndDisconnect(characteristics: [CBCharacteristic], peripheral: CBPeripheral) async {
        for characteristic in characteristics {
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
                ? .withoutResponse
                : .withResponse
            didPulseAnyCharacteristic = true
            peripheral.writeValue(Data([0x01]), for: characteristic, type: writeType)
            try? await Task.sleep(nanoseconds: 50_000_000)
            peripheral.writeValue(Data([0x00]), for: characteristic, type: writeType)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        centralManager?.cancelPeripheralConnection(peripheral)
    }
}

extension BLEWaker: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil, options: nil)
        case .unauthorized, .unsupported, .poweredOff:
            finish(false)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        guard let name = advertisedName, name.caseInsensitiveCompare(targetName) == .orderedSame else { return }
        central.stopScan()
        targetPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(false)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(didPulseAnyCharacteristic)
    }
}

extension BLEWaker: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            finish(false)
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        let matches = characteristics.filter { Self.wakeCharUUIDs.contains($0.uuid) }
        guard !matches.isEmpty else { return }
        Task { await self.pulseAndDisconnect(characteristics: matches, peripheral: peripheral) }
    }
}
