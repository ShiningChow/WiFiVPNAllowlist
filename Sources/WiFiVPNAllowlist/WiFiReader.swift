import AppKit
@preconcurrency import CoreLocation
import CoreWLAN
import Foundation

enum LocationPermissionState: String, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var title: String {
        switch self {
        case .notDetermined: "尚未授权"
        case .authorized: "已授权"
        case .denied: "已拒绝"
        case .restricted: "系统限制"
        }
    }
}

@MainActor
final class WiFiReader: NSObject, @MainActor CLLocationManagerDelegate {
    var authorizationDidChange: (() -> Void)?

    private let locationManager = CLLocationManager()
    private let wifiClient = CWWiFiClient.shared()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    var permissionState: LocationPermissionState {
        guard CLLocationManager.locationServicesEnabled() else {
            return .restricted
        }

        switch locationManager.authorizationStatus {
        case .notDetermined: return LocationPermissionState.notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return LocationPermissionState.authorized
        case .denied: return LocationPermissionState.denied
        case .restricted: return LocationPermissionState.restricted
        @unknown default: return LocationPermissionState.restricted
        }
    }

    func requestPermission() {
        guard permissionState == .notDetermined else {
            return
        }
        NSApp?.activate(ignoringOtherApps: true)
        locationManager.requestWhenInUseAuthorization()
    }

    func currentSSID() -> String? {
        guard permissionState == .authorized else {
            return nil
        }

        if let primarySSID = wifiClient.interface()?.ssid(), !primarySSID.isEmpty {
            return primarySSID
        }

        return wifiClient.interfaces()?.compactMap { interface -> String? in
            guard interface.serviceActive(), interface.powerOn() else {
                return nil
            }
            return interface.ssid()
        }.first
    }

    func currentInterfaceName() -> String? {
        if let primaryInterface = wifiClient.interface(),
           primaryInterface.serviceActive(),
           primaryInterface.powerOn() {
            return primaryInterface.interfaceName
        }

        return wifiClient.interfaces()?.first(where: {
            $0.serviceActive() && $0.powerOn()
        })?.interfaceName
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDidChange?()
    }
}
