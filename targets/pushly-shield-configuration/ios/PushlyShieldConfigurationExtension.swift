import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

private let pushlyAppGroup = "group.com.pushly.shared"
private let pushlySharedCreditsSnapshotKey = "pushly.creditsSnapshot.v1"

final class PushlyShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    makeConfiguration(appName: application.localizedDisplayName ?? "Diese App")
  }

  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    makeConfiguration(appName: application.localizedDisplayName ?? category.localizedDisplayName ?? "Diese App")
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    makeConfiguration(appName: webDomain.domain ?? "Diese Seite")
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    makeConfiguration(appName: webDomain.domain ?? category.localizedDisplayName ?? "Diese Seite")
  }

  private func makeConfiguration(appName: String) -> ShieldConfiguration {
    let availableCredits = loadAvailableCredits()
    let subtitleText = availableCredits > 0
      ? "Du hast heute \(availableCredits) Credits bereit. Loese Free Time in Pushly ein."
      : "Mach Push-ups in Pushly und tausche Credits gegen Free Time."

    return ShieldConfiguration(
      backgroundBlurStyle: .systemThinMaterialDark,
      backgroundColor: UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0),
      icon: UIImage(systemName: "figure.strengthtraining.traditional"),
      title: ShieldConfiguration.Label(
        text: "\(appName) ist geschuetzt",
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: subtitleText,
        color: UIColor(white: 0.88, alpha: 1.0)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: "Free Time einloesen",
        color: .white
      ),
      primaryButtonBackgroundColor: UIColor(red: 0.18, green: 0.78, blue: 0.45, alpha: 1.0),
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: "Spaeter",
        color: UIColor(white: 0.75, alpha: 1.0)
      )
    )
  }

  private func loadAvailableCredits() -> Int {
    guard
      let defaults = UserDefaults(suiteName: pushlyAppGroup),
      let rawSnapshot = defaults.string(forKey: pushlySharedCreditsSnapshotKey),
      let data = rawSnapshot.data(using: .utf8),
      let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let dailyCredits = jsonObject["dailyCredits"] as? [String: Any],
      let balance = dailyCredits["balance"] as? NSNumber
    else {
      return 0
    }

    return max(0, balance.intValue)
  }
}
