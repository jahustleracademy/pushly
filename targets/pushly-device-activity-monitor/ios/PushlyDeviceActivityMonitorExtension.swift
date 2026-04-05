import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

private let pushlySelectionKey = "pushly.familyActivitySelection"
private let pushlyAppGroup = "group.com.pushly.shared"

final class PushlyDeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pushly.main"))

  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    applyStoredShieldSelection()
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    store.clearAllSettings()
  }

  override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    super.eventDidReachThreshold(event, activity: activity)
    applyStoredShieldSelection()
  }

  private func applyStoredShieldSelection() {
    guard
      let defaults = UserDefaults(suiteName: pushlyAppGroup),
      let data = defaults.data(forKey: pushlySelectionKey),
      let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    else {
      store.clearAllSettings()
      return
    }

    store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
    store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
  }
}
