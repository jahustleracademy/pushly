import ExpoModulesCore
#if os(iOS)
import AVFoundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit
#endif

private let pushlyAppGroup = "group.com.pushly.shared"
private let pushlySelectionKey = "pushly.familyActivitySelection"
private let pushlySelectionUpdatedAtKey = "pushly.familyActivitySelectionUpdatedAt"
private let pushlySharedCreditsSnapshotKey = "pushly.creditsSnapshot.v1"
private let pushlyPendingShieldRedeemIntentKey = "pushly.pendingShieldRedeemIntent.v1"
#if os(iOS)
private let pushlyMonitoringActiveKey = "pushly.deviceActivityMonitoringActive"
private let pushlyMonitoringActivity = DeviceActivityName("pushly.daily.monitor")
#endif

public final class PushlyNativeModule: Module {
  #if os(iOS)
  private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pushly.main"))
  private var pickerPromise: Promise?
  private weak var pickerController: UIViewController?
  #endif

  public func definition() -> ModuleDefinition {
    Name("PushlyNative")

    AsyncFunction("getScreenTimeAuthorizationStatusAsync") { () -> String in
      #if os(iOS)
      return self.authorizationStatusLabel()
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("requestScreenTimeAuthorizationAsync") { () async throws -> String in
      #if os(iOS)
      guard #available(iOS 16.0, *) else {
        return "unsupported"
      }

      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
      return self.authorizationStatusLabel()
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("presentFamilyActivityPickerAsync") { (promise: Promise) in
      #if os(iOS)
      guard #available(iOS 16.0, *) else {
        promise.resolve(self.selectionSummaryDictionary(selection: nil))
        return
      }

      DispatchQueue.main.async {
        self.presentFamilyActivityPicker(promise: promise)
      }
      #else
      promise.resolve([
        "appCount": 0,
        "categoryCount": 0,
        "webDomainCount": 0,
        "hasSelection": false,
        "lastUpdatedAt": nil
      ])
      #endif
    }

    AsyncFunction("getStoredSelectionSummaryAsync") { () -> [String: Any?] in
      #if os(iOS)
      return self.selectionSummaryDictionary(selection: self.loadStoredSelection())
      #else
      return [
        "appCount": 0,
        "categoryCount": 0,
        "webDomainCount": 0,
        "hasSelection": false,
        "lastUpdatedAt": nil
      ]
      #endif
    }

    AsyncFunction("applyStoredShieldAsync") { () -> String in
      #if os(iOS)
      guard #available(iOS 16.0, *) else {
        return "unsupported"
      }

      guard let selection = self.loadStoredSelection() else {
        self.store.clearAllSettings()
        return "inactive"
      }

      self.store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
      self.store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
      self.store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

      return selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
        ? "inactive"
        : "active"
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("clearShieldAsync") { () -> String in
      #if os(iOS)
      self.store.clearAllSettings()
      return "inactive"
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("getCameraAuthorizationStatusAsync") { () -> String in
      #if os(iOS)
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .notDetermined:
        return "not_determined"
      case .denied:
        return "denied"
      case .authorized:
        return "authorized"
      case .restricted:
        return "restricted"
      @unknown default:
        return "restricted"
      }
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("startDeviceActivityMonitoringAsync") { () throws -> String in
      #if os(iOS)
      guard #available(iOS 16.0, *) else {
        return "unsupported"
      }

      do {
        try self.startMonitoring()
        return "active"
      } catch {
        throw Exception(name: "E_DEVICE_ACTIVITY_START_FAILED", description: error.localizedDescription)
      }
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("stopDeviceActivityMonitoringAsync") { () -> String in
      #if os(iOS)
      guard #available(iOS 16.0, *) else {
        return "unsupported"
      }

      self.stopMonitoring()
      return "inactive"
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("getDeviceActivityMonitoringStatusAsync") { () -> String in
      #if os(iOS)
      guard #available(iOS 16.0, *) else {
        return "unsupported"
      }

      return self.isMonitoringActive() ? "active" : "inactive"
      #else
      return "unsupported"
      #endif
    }

    AsyncFunction("isPoseEngineAvailableAsync") { () -> Bool in
      #if os(iOS)
      let config = PushlyPoseConfig()
      let mediaPipeAvailable = MediaPipePoseBackend(config: config).isAvailable
      return mediaPipeAvailable || VisionPoseBackend(config: config).isAvailable
      #else
      return false
      #endif
    }

    AsyncFunction("exportPoseDebugSessionAsync") { () async throws -> [String: String] in
      #if os(iOS)
      return try await withCheckedThrowingContinuation { continuation in
        Task { @MainActor in
          PushlyNativeCameraView.exportLatestDebugSession { result in
            switch result {
            case .success(let path):
              continuation.resume(returning: ["path": path])
            case .failure(let error):
              continuation.resume(throwing: Exception(name: "E_POSE_EXPORT_FAILED", description: error.localizedDescription))
            }
          }
        }
      }
      #else
      return ["path": ""]
      #endif
    }

    AsyncFunction("getSharedCreditsSnapshotAsync") { () -> String? in
      #if os(iOS)
      return UserDefaults(suiteName: pushlyAppGroup)?.string(forKey: pushlySharedCreditsSnapshotKey)
      #else
      return nil
      #endif
    }

    AsyncFunction("setSharedCreditsSnapshotAsync") { (snapshot: String) in
      #if os(iOS)
      UserDefaults(suiteName: pushlyAppGroup)?.set(snapshot, forKey: pushlySharedCreditsSnapshotKey)
      #endif
    }

    AsyncFunction("getPendingShieldRedeemIntentAsync") { () -> String? in
      #if os(iOS)
      return UserDefaults(suiteName: pushlyAppGroup)?.string(forKey: pushlyPendingShieldRedeemIntentKey)
      #else
      return nil
      #endif
    }

    AsyncFunction("setPendingShieldRedeemIntentAsync") { (intent: String) in
      #if os(iOS)
      UserDefaults(suiteName: pushlyAppGroup)?.set(intent, forKey: pushlyPendingShieldRedeemIntentKey)
      #endif
    }

    AsyncFunction("consumePendingShieldRedeemIntentAsync") { () -> String? in
      #if os(iOS)
      let defaults = UserDefaults(suiteName: pushlyAppGroup)
      let intent = defaults?.string(forKey: pushlyPendingShieldRedeemIntentKey)
      defaults?.removeObject(forKey: pushlyPendingShieldRedeemIntentKey)
      return intent
      #else
      return nil
      #endif
    }

    View(PushlyNativeCameraView.self) {
      Prop("isActive") { (view: PushlyNativeCameraView, isActive: Bool?) in
        view.isActive = isActive ?? true
      }

      Prop("showSkeleton") { (view: PushlyNativeCameraView, showSkeleton: Bool?) in
        view.showSkeleton = showSkeleton ?? true
      }

      Prop("cameraPosition") { (view: PushlyNativeCameraView, position: String?) in
        view.cameraPosition = position == "back" ? .back : .front
      }

      Prop("repTarget") { (view: PushlyNativeCameraView, repTarget: Double?) in
        view.repTarget = Int(repTarget ?? 3)
      }

      Prop("debugMode") { (view: PushlyNativeCameraView, debugMode: Bool?) in
        view.debugMode = debugMode ?? false
      }

      Prop("forceFullFrameProcessing") { (view: PushlyNativeCameraView, enabled: Bool?) in
        view.forceFullFrameProcessing = enabled ?? false
      }

      Prop("forceROIProcessing") { (view: PushlyNativeCameraView, enabled: Bool?) in
        view.forceROIProcessing = enabled ?? false
      }

      Prop("poseBackendMode") { (view: PushlyNativeCameraView, mode: String?) in
        view.poseBackendMode = mode ?? "auto"
      }

      Events("onPoseFrame")
    }
  }
}

#if os(iOS)
private extension PushlyNativeModule {
  func authorizationStatusLabel() -> String {
    guard #available(iOS 16.0, *) else {
      return "unsupported"
    }

    switch AuthorizationCenter.shared.authorizationStatus {
    case .approved:
      return "approved"
    case .denied:
      return "denied"
    case .notDetermined:
      return "not_determined"
    @unknown default:
      return "restricted"
    }
  }

  func presentFamilyActivityPicker(promise: Promise) {
    pickerPromise = promise

    let currentSelection = loadStoredSelection() ?? FamilyActivitySelection()
    let host = UIHostingController(
      rootView: PushlyFamilyActivityPickerSheet(
        selection: currentSelection,
        onCancel: { [weak self] in
          self?.dismissPicker(with: nil, resolve: false)
        },
        onConfirm: { [weak self] selection in
          self?.dismissPicker(with: selection, resolve: true)
        }
      )
    )

    host.modalPresentationStyle = .formSheet

    guard let presenter = topViewController() else {
      promise.reject("E_NO_VIEW_CONTROLLER", "Could not find a view controller to present the Family Activity Picker.")
      pickerPromise = nil
      return
    }

    pickerController = host
    presenter.present(host, animated: true)
  }

  func dismissPicker(with selection: FamilyActivitySelection?, resolve: Bool) {
    let promise = pickerPromise
    pickerPromise = nil

    if let selection, resolve {
      saveSelection(selection)
    }

    pickerController?.dismiss(animated: true)
    pickerController = nil

    if resolve {
      promise?.resolve(selectionSummaryDictionary(selection: selection))
    } else {
      promise?.resolve(selectionSummaryDictionary(selection: loadStoredSelection()))
    }
  }

  func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let root = base ?? UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController

    if let navigationController = root as? UINavigationController {
      return topViewController(base: navigationController.visibleViewController)
    }

    if let tabBarController = root as? UITabBarController, let selected = tabBarController.selectedViewController {
      return topViewController(base: selected)
    }

    if let presented = root?.presentedViewController {
      return topViewController(base: presented)
    }

    return root
  }

  func selectionSummaryDictionary(selection: FamilyActivitySelection?) -> [String: Any?] {
    let resolvedSelection = selection ?? loadStoredSelection() ?? FamilyActivitySelection()
    let updatedAt = UserDefaults(suiteName: pushlyAppGroup)?.string(forKey: pushlySelectionUpdatedAtKey)

    return [
      "appCount": resolvedSelection.applicationTokens.count,
      "categoryCount": resolvedSelection.categoryTokens.count,
      "webDomainCount": resolvedSelection.webDomainTokens.count,
      "hasSelection": !(resolvedSelection.applicationTokens.isEmpty && resolvedSelection.categoryTokens.isEmpty && resolvedSelection.webDomainTokens.isEmpty),
      "lastUpdatedAt": updatedAt
    ]
  }

  func loadStoredSelection() -> FamilyActivitySelection? {
    guard
      let defaults = UserDefaults(suiteName: pushlyAppGroup),
      let data = defaults.data(forKey: pushlySelectionKey)
    else {
      return nil
    }

    return try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
  }

  func saveSelection(_ selection: FamilyActivitySelection) {
    guard
      let defaults = UserDefaults(suiteName: pushlyAppGroup),
      let data = try? PropertyListEncoder().encode(selection)
    else {
      return
    }

    defaults.set(data, forKey: pushlySelectionKey)
    defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: pushlySelectionUpdatedAtKey)
  }

  @available(iOS 16.0, *)
  func startMonitoring() throws {
    let center = DeviceActivityCenter()
    let schedule = DeviceActivitySchedule(
      intervalStart: DateComponents(hour: 0, minute: 0),
      intervalEnd: DateComponents(hour: 23, minute: 59),
      repeats: true
    )

    try center.startMonitoring(pushlyMonitoringActivity, during: schedule)
    UserDefaults(suiteName: pushlyAppGroup)?.set(true, forKey: pushlyMonitoringActiveKey)
  }

  @available(iOS 16.0, *)
  func stopMonitoring() {
    let center = DeviceActivityCenter()
    center.stopMonitoring([pushlyMonitoringActivity])
    UserDefaults(suiteName: pushlyAppGroup)?.set(false, forKey: pushlyMonitoringActiveKey)
  }

  @available(iOS 16.0, *)
  func isMonitoringActive() -> Bool {
    UserDefaults(suiteName: pushlyAppGroup)?.bool(forKey: pushlyMonitoringActiveKey) ?? false
  }
}

@available(iOS 16.0, *)
private struct PushlyFamilyActivityPickerSheet: View {
  @State var selection: FamilyActivitySelection
  let onCancel: () -> Void
  let onConfirm: (FamilyActivitySelection) -> Void

  var body: some View {
    NavigationStack {
      FamilyActivityPicker(selection: $selection)
        .navigationTitle("Geschützte Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen", action: onCancel)
          }

          ToolbarItem(placement: .confirmationAction) {
            Button("Sichern") {
              onConfirm(selection)
            }
          }
        }
    }
  }
}
#endif
