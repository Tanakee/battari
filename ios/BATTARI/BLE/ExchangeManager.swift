import CoreBluetooth
import Foundation

/// BLEで近くの相手を探し、プロフィールを交換する（G5・G6）。
///
/// 各端末は「アドバタイズ（見つけてもらう）」と「スキャン（探す）」を同時に行う。
/// 電波強度で相手を検知したら、トークン（アドバタイズ名）の小さい方がセントラルとして接続し、
/// もう一方はペリフェラルとして待つ。接続後は次の2つのキャラクタリスティックでやりとりする。
///   inbox  : セントラル → ペリフェラル（Write with response）
///   outbox : ペリフェラル → セントラル（Notify）
/// すべてのコールバックはメインキューで受ける。
final class ExchangeManager: NSObject, ObservableObject {
    enum Phase: Equatable {
        /// G5。直前の交換が終わった理由があれば持つ
        case searching(lastEnd: String?)
        /// G6。waiting は自分が承認済みで相手を待っている状態
        case confirming(ProfilePreview, thumbnail: Data, waiting: Bool)
        case transferring
        case completed(ExchangeSession.Received)
    }

    enum Radio: Equatable { case unknown, poweredOn, poweredOff, unauthorized, unsupported }

    /// 自分の情報（交換で送るもの）
    struct Me {
        var preview: ProfilePreview
        var thumbnail: Data
        var profile: ProfilePayload
        var icon: Data
    }

    static let serviceUUID = CBUUID(string: "6A1E0001-5B3C-4E2B-9C1D-BA77A2100000")
    static let inboxUUID = CBUUID(string: "6A1E0002-5B3C-4E2B-9C1D-BA77A2100000")
    static let outboxUUID = CBUUID(string: "6A1E0003-5B3C-4E2B-9C1D-BA77A2100000")

    @Published private(set) var phase: Phase = .searching(lastEnd: nil)
    @Published private(set) var radio: Radio = .unknown

    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var serviceAdded = false
    private let inbox = CBMutableCharacteristic(type: inboxUUID, properties: [.write], value: nil, permissions: [.writeable])
    private let outbox = CBMutableCharacteristic(type: outboxUUID, properties: [.notify], value: nil, permissions: [.readable])

    /// アドバタイズ名。接続する側を決めるためだけに使う（6桁の16進数）
    let token = String(format: "%06X", UInt32.random(in: 0...0xFFFFFF))
    private var me: Me?
    private var active = false
    private var detector = ProximityDetector()

    // 接続中の相手
    private enum Link {
        case asCentral(CBPeripheral, inbox: CBCharacteristic?)
        case asPeripheral(CBCentral)
    }
    private var link: Link?
    private var partnerToken: String?
    private var session: ExchangeSession?
    private var reassembler = Reassembler()
    /// 送信待ちのチャンク。profileEnd はプロフィールの最後のチャンク
    private var outgoing: [(data: Data, profileEnd: Bool)] = []
    private var awaitingWrite: Bool? // 書き込み完了待ちのチャンクがプロフィールの最後か
    private var closeWhenFlushed = false
    private var approvalTimer: Timer?
    private var linkTimeout: DispatchWorkItem?

    // MARK: - 画面から呼ぶ操作

    func start(as me: Me) {
        var me = me
        me.preview.token = token
        self.me = me
        active = true
        phase = .searching(lastEnd: nil)
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            beginDiscovery()
        }
    }

    /// G7「貼って続けて交換」で、もう一度探し始める
    func resume() {
        guard me != nil else { return }
        active = true
        phase = .searching(lastEnd: nil)
        beginDiscovery()
    }

    /// G5を閉じたとき
    func stop() {
        active = false
        approvalTimer?.invalidate()
        if session?.isFinished == false { apply(session?.handle(.userDeclined) ?? []) }
        closeLink()
        central?.stopScan()
        peripheralManager?.stopAdvertising()
        central = nil
        peripheralManager = nil
        serviceAdded = false
    }

    #if DEBUG
    /// デモモードで画面を確認するため
    func debugShow(_ phase: Phase) { self.phase = phase }
    #endif

    func accept() { apply(session?.handle(.userAccepted) ?? []) }
    func decline() { apply(session?.handle(.userDeclined) ?? []) }

    // MARK: - 探す・見つけてもらう

    private func beginDiscovery() {
        guard active, link == nil else { return }
        detector.reset()
        if central?.state == .poweredOn, central?.isScanning == false {
            central?.scanForPeripherals(withServices: [Self.serviceUUID],
                                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        if peripheralManager?.state == .poweredOn, serviceAdded, peripheralManager?.isAdvertising == false {
            peripheralManager?.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: token,
            ])
        }
    }

    private func pauseDiscovery() {
        central?.stopScan()
        peripheralManager?.stopAdvertising()
    }

    private func updateRadio() {
        switch CBManager.authorization {
        case .denied, .restricted:
            radio = .unauthorized
            return
        default: break
        }
        switch central?.state {
        case .poweredOn?: radio = .poweredOn
        case .poweredOff?: radio = .poweredOff
        case .unauthorized?: radio = .unauthorized
        case .unsupported?: radio = .unsupported
        default: radio = .unknown
        }
    }

    // MARK: - 交換セッション

    private func openSession(link: Link, partnerToken: String?) {
        guard let me else { return }
        self.link = link
        self.partnerToken = partnerToken
        reassembler = Reassembler()
        outgoing = []
        awaitingWrite = nil
        closeWhenFlushed = false
        session = ExchangeSession(myPreview: me.preview, myThumbnail: me.thumbnail, myProfile: me.profile, myIcon: me.icon)
        pauseDiscovery()
        apply(session!.handle(.linkReady))
        // 相手の情報が届かないまま止まらないようにする
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, case .handshaking? = self.session?.state else { return }
            self.linkLost()
        }
        linkTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
    }

    private func apply(_ actions: [ExchangeSession.Action]) {
        for action in actions {
            switch action {
            case let .send(message): enqueue(message)
            case .startApprovalTimer:
                approvalTimer?.invalidate()
                approvalTimer = Timer.scheduledTimer(withTimeInterval: Exchange.approvalTimeout, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.apply(self.session?.handle(.approvalTimedOut) ?? [])
                }
            case .cancelApprovalTimer:
                approvalTimer?.invalidate()
                approvalTimer = nil
            case .close:
                closeWhenFlushed = true
            }
        }
        publishPhase()
        pump()
    }

    private func publishPhase() {
        guard let session else { return }
        switch session.state {
        case .handshaking:
            break
        case let .confirming(preview, thumb, local, _):
            phase = .confirming(preview, thumbnail: thumb, waiting: local)
        case .transferring:
            phase = .transferring
        case let .done(received):
            linkTimeout?.cancel()
            if let partnerToken { detector.block(peer: partnerToken, at: Date()) }
            phase = .completed(received)
            active = false // G7へ進む。続けて交換する場合は resume() で再開する
        case let .ended(reason):
            linkTimeout?.cancel()
            if let partnerToken { detector.block(peer: partnerToken, at: Date()) }
            phase = .searching(lastEnd: reason.message)
        }
    }

    // MARK: - 送信

    private func enqueue(_ message: ExchangeMessage) {
        guard let link, let data = try? message.encoded() else { return }
        let size: Int
        switch link {
        case let .asCentral(peripheral, _): size = peripheral.maximumWriteValueLength(for: .withResponse)
        case let .asPeripheral(central): size = central.maximumUpdateValueLength
        }
        let parts = Framing.chunks(of: data, size: max(20, size))
        let isProfile: Bool
        if case .profile = message { isProfile = true } else { isProfile = false }
        for (i, part) in parts.enumerated() {
            outgoing.append((part, isProfile && i == parts.count - 1))
        }
    }

    /// 送信待ちのチャンクを順に送る
    private func pump() {
        guard let link else { return }
        switch link {
        case let .asCentral(peripheral, inbox?):
            guard awaitingWrite == nil, !outgoing.isEmpty else { break }
            let next = outgoing.removeFirst()
            awaitingWrite = next.profileEnd
            peripheral.writeValue(next.data, for: inbox, type: .withResponse)
            return
        case .asCentral:
            return
        case let .asPeripheral(central):
            while let next = outgoing.first {
                guard peripheralManager?.updateValue(next.data, for: outbox, onSubscribedCentrals: [central]) == true else {
                    return // 送信キューが空いたら peripheralManagerIsReady で続きから送る
                }
                outgoing.removeFirst()
                if next.profileEnd { chunkFlushed(profileEnd: true); return }
            }
        }
        if outgoing.isEmpty, awaitingWrite == nil, closeWhenFlushed { closeLink() }
    }

    private func chunkFlushed(profileEnd: Bool) {
        if profileEnd {
            apply(session?.handle(.profileSent) ?? [])
        } else {
            pump()
        }
    }

    private func receive(_ chunk: Data) {
        do {
            for raw in try reassembler.append(chunk) {
                let message = try ExchangeMessage.decode(raw)
                if case let .hello(preview, _) = message, partnerToken == nil { partnerToken = preview.token }
                apply(session?.handle(.received(message)) ?? [])
            }
        } catch {
            apply(session?.handle(.linkClosed) ?? [])
            closeLink()
        }
    }

    private func closeLink() {
        approvalTimer?.invalidate()
        approvalTimer = nil
        linkTimeout?.cancel()
        if case let .asCentral(peripheral, _)? = link {
            central?.cancelPeripheralConnection(peripheral)
        }
        link = nil
        outgoing = []
        awaitingWrite = nil
        closeWhenFlushed = false
        if case .searching = phase { beginDiscovery() }
    }

    private func linkLost() {
        guard link != nil else { return }
        apply(session?.handle(.linkClosed) ?? [])
        closeLink()
    }
}

// MARK: - セントラル（探して接続する側）

extension ExchangeManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateRadio()
        if central.state == .poweredOn { beginDiscovery() } else { linkLost() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active, link == nil, case .searching = phase,
              let theirs = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name,
              theirs != token else { return }
        guard detector.update(peer: theirs, rssi: RSSI.intValue, at: Date()) else { return }
        // トークンの小さい方が接続しにいく。大きい方は接続されるのを待つ
        guard token < theirs else { return }
        link = .asCentral(peripheral, inbox: nil)
        partnerToken = theirs
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.session == nil else { return }
            self.closeLink()
        }
        linkTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isCurrent(peripheral) else { return }
        closeLink()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard isCurrent(peripheral) else { return } // 前の相手の切断通知は無視する
        if session?.isFinished == false { linkLost() } else { closeLink() }
    }

    private func isCurrent(_ peripheral: CBPeripheral) -> Bool {
        if case let .asCentral(p, _)? = link { return p.identifier == peripheral.identifier }
        return false
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return closeLink() }
        peripheral.discoverCharacteristics([Self.inboxUUID, Self.outboxUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let chars = service.characteristics ?? []
        guard let inbox = chars.first(where: { $0.uuid == Self.inboxUUID }),
              let outbox = chars.first(where: { $0.uuid == Self.outboxUUID }) else { return closeLink() }
        link = .asCentral(peripheral, inbox: inbox)
        peripheral.setNotifyValue(true, for: outbox)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.outboxUUID, characteristic.isNotifying, error == nil,
              case let .asCentral(p, inbox?)? = link, p == peripheral else { return }
        openSession(link: .asCentral(peripheral, inbox: inbox), partnerToken: partnerToken)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.outboxUUID, let value = characteristic.value else { return }
        receive(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let written = awaitingWrite else { return }
        awaitingWrite = nil
        if error != nil { return linkLost() }
        chunkFlushed(profileEnd: written)
    }
}

// MARK: - ペリフェラル（見つけてもらう側）

extension ExchangeManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        updateRadio()
        guard peripheral.state == .poweredOn else { return linkLost() }
        if !serviceAdded {
            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [inbox, outbox]
            peripheral.add(service)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        serviceAdded = error == nil
        beginDiscovery()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        // 交換中・G5以外なら受け付けない（相手側は情報が届かずタイムアウトする）
        guard characteristic.uuid == Self.outboxUUID, active, link == nil, case .searching = phase else { return }
        openSession(link: .asPeripheral(central), partnerToken: nil)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard case let .asPeripheral(c)? = link, c.identifier == central.identifier else { return }
        linkLost()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == Self.inboxUUID {
            guard case let .asPeripheral(c)? = link, c.identifier == request.central.identifier,
                  let value = request.value else { continue }
            receive(value)
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        pump()
    }
}
