import Foundation
@preconcurrency import CoreBluetooth

struct BluetoothPhone: Identifiable {
    let id: UUID
    let name: String
    let signal: Int
}

/// One authenticated peer, bounded framed messages, GATT backpressure in both roles.
final class BluetoothTransport: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    static let serviceID = CBUUID(string: "913E3110-BF27-4871-B0D3-0F944C910401")
    private static let writeID = CBUUID(string: "913E3111-BF27-4871-B0D3-0F944C910401")
    private static let notifyID = CBUUID(string: "913E3112-BF27-4871-B0D3-0F944C910401")
    var discovered: ((BluetoothPhone) -> Void)?
    var opened: ((String) -> Void)?
    var closed: ((String) -> Void)?
    var received: ((Data) -> Void)?
    var status: ((String) -> Void)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheralManager!
    private var known: [UUID: CBPeripheral] = [:]
    private var remote: CBPeripheral?
    private var subscriber: CBCentral?
    private var writer: CBCharacteristic?
    private var notifier: CBMutableCharacteristic?
    private var incomingWriter: CBMutableCharacteristic?
    private var wantsDiscovery = true
    private var localName = "Flick"
    private var established = false
    private var writePending = false
    private var pendingWriteCount = 0
    private var outgoing: [Data] = []
    private var outgoingOffset = 0
    private var framer = BluetoothFramer()
    private var cipher: BluetoothCipher?
    private var deadline: DispatchWorkItem?
    var isConnected: Bool { established }

    func start(name: String, discoverable: Bool) {
        localName = name; wantsDiscovery = discoverable
        if central == nil {
            var centralOptions: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
            var peripheralOptions: [String: Any] = [CBPeripheralManagerOptionShowPowerAlertKey: true]
            #if !APP_EXTENSION
            centralOptions[CBCentralManagerOptionRestoreIdentifierKey] = "flick.central.v4"
            peripheralOptions[CBPeripheralManagerOptionRestoreIdentifierKey] = "flick.peripheral.v4"
            #endif
            central = CBCentralManager(delegate: self, queue: .main, options: centralOptions)
            peripheral = CBPeripheralManager(delegate: self, queue: .main, options: peripheralOptions)
        } else { updateDiscovery() }
    }
    func setDiscoverable(_ value: Bool) { wantsDiscovery = value; updateDiscovery() }
    private func updateDiscovery() {
        if central?.state == .poweredOn {
            if wantsDiscovery { central.scanForPeripherals(withServices: [Self.serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
            else { central.stopScan() }
        }
        if peripheral?.state == .poweredOn {
            if notifier == nil { installService() }
            else if wantsDiscovery && !peripheral.isAdvertising {
                peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceID], CBAdvertisementDataLocalNameKey: localName])
            } else if !wantsDiscovery { peripheral.stopAdvertising() }
        }
    }
    func connect(_ id: UUID) {
        guard !established, remote == nil, subscriber == nil, central?.state == .poweredOn, let device = known[id] else { return }
        remote = device; device.delegate = self
        central.connect(device, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        let job = DispatchWorkItem { [weak self] in guard let self = self, !self.established else { return }; self.disconnect("蓝牙连接超时，请让对方打开一甩后重试。") }
        deadline?.cancel(); deadline = job; DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: job)
    }
    func installCipher(_ value: BluetoothCipher) { cipher = value }
    func send(_ data: Data, handshake: Bool = false) throws {
        guard established else { throw BluetoothFailure.malformed }
        let payload: Data
        if handshake { payload = Data([0]) + data }
        else { guard let cipher = cipher else { throw BluetoothFailure.authentication }; payload = Data([1]) + (try cipher.seal(data)) }
        let frame = try BluetoothFramer.frame(payload)
        guard outgoing.reduce(0, { $0 + $1.count }) + frame.count <= 2 * BluetoothFramer.limit else { throw BluetoothFailure.oversized }
        outgoing.append(frame); drain()
    }
    func disconnect(_ reason: String = "蓝牙连接已断开，未完成的文件可以重试。") {
        let wasActive = established || remote != nil || subscriber != nil
        let oldRemote = remote
        let hadSubscriber = subscriber != nil
        remote = nil; subscriber = nil; writer = nil; established = false; writePending = false
        outgoing = []; outgoingOffset = 0; cipher = nil; framer = BluetoothFramer(); deadline?.cancel()
        if let oldRemote = oldRemote { central?.cancelPeripheralConnection(oldRemote) }
        if hadSubscriber, peripheral?.state == .poweredOn {
            peripheral.stopAdvertising(); peripheral.removeAllServices(); notifier = nil; incomingWriter = nil; installService()
        }
        if wasActive { closed?(reason) }
    }
    func stop() { wantsDiscovery = false; central?.stopScan(); peripheral?.stopAdvertising(); disconnect() }
    private func installService() {
        let write = CBMutableCharacteristic(type: Self.writeID, properties: [.write], value: nil, permissions: [.writeable])
        let notify = CBMutableCharacteristic(type: Self.notifyID, properties: [.notify], value: nil, permissions: [])
        incomingWriter = write; notifier = notify
        let service = CBMutableService(type: Self.serviceID, primary: true); service.characteristics = [write, notify]
        peripheral.add(service)
    }
    private func begin(_ name: String) {
        guard !established else { return }
        established = true; cipher = nil; framer = BluetoothFramer(); deadline?.cancel(); opened?(name)
    }
    private func consume(_ data: Data) {
        do {
            for frame in try framer.append(data) {
                guard let tag = frame.first else { throw BluetoothFailure.malformed }
                let body = Data(frame.dropFirst())
                if tag == 0 {
                    guard cipher == nil, body.count <= 8192 else { throw BluetoothFailure.authentication }
                    received?(body)
                } else if tag == 1, let cipher = cipher { received?(try cipher.open(body)) }
                else { throw BluetoothFailure.authentication }
            }
        } catch { disconnect("蓝牙数据核验失败，请重新连接。") }
    }
    private func drain() {
        guard established, !writePending else { return }
        if let remote = remote, let writer = writer {
            guard let frame = outgoing.first else { return }
            let count = min(remote.maximumWriteValueLength(for: .withResponse), frame.count - outgoingOffset)
            guard count > 0 else { disconnect("蓝牙写入长度无效。"); return }
            writePending = true; pendingWriteCount = count
            remote.writeValue(Data(frame.dropFirst(outgoingOffset).prefix(count)), for: writer, type: .withResponse)
        } else if let subscriber = subscriber, let notifier = notifier {
            while let frame = outgoing.first {
                let count = min(subscriber.maximumUpdateValueLength, frame.count - outgoingOffset)
                guard count > 0 else { disconnect("蓝牙通知长度无效。"); return }
                guard peripheral.updateValue(Data(frame.dropFirst(outgoingOffset).prefix(count)), for: notifier, onSubscribedCentrals: [subscriber]) else { return }
                advance(count)
            }
        }
    }
    private func advance(_ count: Int) {
        guard let first = outgoing.first else { return }
        outgoingOffset += count
        if outgoingOffset == first.count { outgoing.removeFirst(); outgoingOffset = 0 }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { updateDiscovery() }
        else { if established || remote != nil { disconnect("蓝牙已关闭或未获授权。") }; status?(central.state == .unauthorized ? "请在系统设置中允许一甩使用蓝牙。" : "请打开蓝牙，以发现附近设备或使用纯蓝牙传输。") }
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn { updateDiscovery() }
        else { notifier = nil; incomingWriter = nil; if established { disconnect("蓝牙已关闭，传输未完成。") } }
    }
    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        known[device.identifier] = device
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? device.name ?? "附近的一甩设备"
        discovered?(BluetoothPhone(id: device.identifier, name: name, signal: RSSI.intValue))
    }
    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard device === remote else { central.cancelPeripheralConnection(device); return }
        device.delegate = self; device.discoverServices([Self.serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) { if device === remote { disconnect("蓝牙连接失败，请重试。") } }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) { if device === remote { disconnect() } }
    func peripheral(_ device: CBPeripheral, didDiscoverServices error: Error?) {
        guard device === remote, error == nil, let service = device.services?.first(where: { $0.uuid == Self.serviceID }) else { disconnect("对方蓝牙服务不可用，请更新到同一版本。"); return }
        device.discoverCharacteristics([Self.writeID, Self.notifyID], for: service)
    }
    func peripheral(_ device: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if device === remote, invalidatedServices.contains(where: { $0.uuid == Self.serviceID }) { disconnect("对方蓝牙服务已重启，请重新连接。") }
    }
    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard device === remote, error == nil, let write = service.characteristics?.first(where: { $0.uuid == Self.writeID }), let notify = service.characteristics?.first(where: { $0.uuid == Self.notifyID }) else { disconnect("蓝牙服务不完整。"); return }
        writer = write; device.setNotifyValue(true, for: notify)
    }
    func peripheral(_ device: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard device === remote, characteristic.uuid == Self.notifyID else { return }
        if error == nil && characteristic.isNotifying { begin(device.name ?? "蓝牙设备") }
        else { disconnect("蓝牙通知未能开启。") }
    }
    func peripheral(_ device: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard device === remote, characteristic.uuid == Self.notifyID else { return }
        if let data = characteristic.value, error == nil { consume(data) } else { disconnect("蓝牙读取中断。") }
    }
    func peripheral(_ device: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard device === remote, characteristic.uuid == Self.writeID, writePending else { return }
        writePending = false
        if error != nil { disconnect("蓝牙写入中断。"); return }
        advance(pendingWriteCount); drain()
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error != nil { status?("无法开启蓝牙服务，请重试。"); return }; updateDiscovery()
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.notifyID, remote == nil, subscriber == nil else { return }
        subscriber = central; begin("附近的蓝牙设备"); drain()
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if subscriber?.identifier == central.identifier { disconnect() }
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { drain() }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == Self.writeID, request.offset == 0, subscriber?.identifier == request.central.identifier, let data = request.value else { peripheral.respond(to: request, withResult: .unlikelyError); continue }
            peripheral.respond(to: request, withResult: .success); consume(data)
        }
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let device = restored.first else { return }
        known[device.identifier] = device; remote = device; device.delegate = self
        if device.state == .connected { device.discoverServices([Self.serviceID]) } else { central.connect(device) }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        guard let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService], let service = services.first(where: { $0.uuid == Self.serviceID }) else { return }
        incomingWriter = service.characteristics?.first(where: { $0.uuid == Self.writeID }) as? CBMutableCharacteristic
        notifier = service.characteristics?.first(where: { $0.uuid == Self.notifyID }) as? CBMutableCharacteristic
        if let central = notifier?.subscribedCentrals?.first { subscriber = central; begin("已恢复的蓝牙设备") }
    }
}
