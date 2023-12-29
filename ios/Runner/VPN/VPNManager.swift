//
//  VPNManager.swift
//  Runner
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import Combine
import NetworkExtension

enum VPNManagerAlertType: String {
    case RequestVPNPermission
    case RequestNotificationPermission
    case EmptyConfiguration
    case StartCommandServer
    case CreateService
    case StartService
}

struct VPNManagerAlert {
    let alert: VPNManagerAlertType?
    let message: String?
}

class VPNManager: ObservableObject {
    private var cancelBag: Set<AnyCancellable> = []
    
    private var observer: NSObjectProtocol?
    private var manager = NEVPNManager.shared()
    private var loaded: Bool = false
    private var timer: Timer?
            
    static let shared: VPNManager = VPNManager()
        
    @Published private(set) var state: NEVPNStatus = .invalid
    @Published private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil)
    
    @Published private(set) var upload: Int64 = 0
    @Published private(set) var download: Int64 = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    
    private var _connectTime: Date?
    private var connectTime: Date? {
        set {
            UserDefaults(suiteName: FilePath.groupName)?.set(newValue?.timeIntervalSince1970, forKey: "SingBoxConnectTime")
            _connectTime = newValue
        }
        get {
            if let _connectTime {
                return _connectTime
            }
            guard let interval = UserDefaults(suiteName: FilePath.groupName)?.value(forKey: "SingBoxConnectTime") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }
    private var readingWS: Bool = false
    
    @Published var isConnectedToAnyVPN: Bool = false
    
    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: nil) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            self?.state = connection.status
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateStats()
            elapsedTime = -1 * (connectTime?.timeIntervalSinceNow ?? 0)
        }
    }
                
    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
    }
    
    func setup() async throws {
        // guard !loaded else { return }
        loaded = true
        try await loadVPNPreference()
    }
    
    private func loadVPNPreference() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = managers.first {
            self.manager = manager
            return
        }
        let newManager = NETunnelProviderManager()
        let `protocol` = NETunnelProviderProtocol()
        `protocol`.providerBundleIdentifier = "\(Bundle.main.baseBundleIdentifier).SingBoxPacketTunnel"
        `protocol`.serverAddress = "Hiddify"
        newManager.protocolConfiguration = `protocol`
        newManager.localizedDescription = "Hiddify"
        try await newManager.saveToPreferences()
        try await newManager.loadFromPreferences()
        self.manager = newManager
    }
    
    private func enableVPNManager() async throws {
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }
    
    @MainActor private func set(upload: Int64, download: Int64) {
        self.upload = upload
        self.download = download
    }
    
    var isAnyVPNConnected: Bool {
        let cfDict = CFNetworkCopySystemProxySettings()
        let nsDict = cfDict!.takeRetainedValue() as NSDictionary
        guard let keys = nsDict["__SCOPED__"] as? NSDictionary else {
            return false
        }
        for key: String in keys.allKeys as! [String] {
            if (key == "tap" || key == "tun" || key == "ppp" || key == "ipsec" || key == "ipsec0" || key == "utun1" || key == "utun2") {
                return true
            } else if key.starts(with: "utun") {
                return true
            }
        }
        return false
    }
    
    func reset() {
        loaded = false
        if state != .disconnected && state != .invalid {
            disconnect()
        }
        $state.filter { $0 == .disconnected || $0 == .invalid }.first().sink { [weak self] _ in
            Task { [weak self] () in
                self?.manager = .shared()
                let managers = try? await NETunnelProviderManager.loadAllFromPreferences()
                for manager in managers ?? [] {
                    try? await manager.removeFromPreferences()
                }
                try? await self?.loadVPNPreference()
            }
        }.store(in: &cancelBag)
        
    }
    
    private func updateStats() {
        let isAnyVPNConnected = self.isAnyVPNConnected
        if isConnectedToAnyVPN != isAnyVPNConnected {
            isConnectedToAnyVPN = isAnyVPNConnected
        }
        guard state == .connected else { return }
        guard let connection = manager.connection as? NETunnelProviderSession else { return }
        try? connection.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
            guard
                let response,
                let response = String(data: response, encoding: .utf8)
            else { return }
            let responseComponents = response.components(separatedBy: ",")
            guard
                responseComponents.count == 2,
                let upload = Int64(responseComponents[0]),
                let download = Int64(responseComponents[1])
            else { return }
            Task { [upload, download, weak self] () in
                await self?.set(upload: upload, download: download)
            }
        }
    }
    
    func connect(with config: String, disableMemoryLimit: Bool = false) async throws {
        await set(upload: 0, download: 0)
        guard state == .disconnected else { return }
        try await enableVPNManager()
        try manager.connection.startVPNTunnel(options: [
            "Config": config as NSString,
            "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
        ])
        connectTime = .now
    }
    
    func disconnect() {
        guard state == .connected else { return }
        manager.connection.stopVPNTunnel()
    }
    
}

