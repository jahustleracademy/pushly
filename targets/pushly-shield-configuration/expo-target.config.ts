export default {
  name: 'pushly-shield-configuration',
  displayName: 'Pushly Shield UI',
  type: 'action',
  platforms: ['ios'],
  appGroup: 'group.com.pushly.shared',
  ios: {
    deploymentTarget: '16.0',
    frameworks: ['ManagedSettings', 'ManagedSettingsUI', 'FamilyControls', 'UIKit'],
    entitlements: {
      'com.apple.security.application-groups': ['group.com.pushly.shared'],
      'com.apple.developer.family-controls': true
    },
    infoPlist: {
      NSExtension: {
        NSExtensionPointIdentifier: 'com.apple.ManagedSettingsUI.shield-configuration-service',
        NSExtensionPrincipalClass: 'PushlyShieldConfigurationExtension'
      }
    }
  }
};
