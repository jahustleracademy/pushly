import Foundation
import ManagedSettings
import os

private let logger = Logger(subsystem: "com.artur.pushly", category: "shield-action")
private let pushlyAppGroup = "group.com.pushly.shared"
private let pushlyPendingShieldRedeemIntentKey = "pushly.pendingShieldRedeemIntent.v1"

final class PushlyShieldActionExtension: ShieldActionDelegate {
  override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    handleAction(action, completionHandler: completionHandler)
  }

  override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    handleAction(action, completionHandler: completionHandler)
  }

  override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    handleAction(action, completionHandler: completionHandler)
  }

  private func handleAction(_ action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    switch action {
    case .primaryButtonPressed:
      if persistRedeemRouteIntent() {
        // Official response path: defer lets iOS proceed while the parent app consumes the pending intent.
        completionHandler(.defer)
      } else {
        completionHandler(.close)
      }
    case .secondaryButtonPressed:
      completionHandler(.close)
    @unknown default:
      completionHandler(.close)
    }
  }

  private func persistRedeemRouteIntent() -> Bool {
    let payload: [String: Any] = [
      "type": "route_redeem",
      "source": "shield",
      "suggestedMinutes": 15,
      "createdAt": ISO8601DateFormatter().string(from: Date())
    ]

    guard
      let data = try? JSONSerialization.data(withJSONObject: payload),
      let jsonString = String(data: data, encoding: .utf8)
    else {
      logger.error("Failed to encode pending shield redeem intent")
      return false
    }

    guard let defaults = UserDefaults(suiteName: pushlyAppGroup) else {
      logger.error("App group defaults unavailable")
      return false
    }

    defaults.set(jsonString, forKey: pushlyPendingShieldRedeemIntentKey)
    logger.log("Stored pending shield redeem intent")
    return true
  }
}
