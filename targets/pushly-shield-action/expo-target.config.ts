export default {
  name: 'pushly-shield-action',
  displayName: 'Pushly Shield Action',
  type: 'action',
  platforms: ['ios'],
  appGroup: 'group.com.pushly.shared',
  ios: {
    deploymentTarget: '16.0',
    frameworks: ['ManagedSettings', 'FamilyControls'],
    entitlements: {
      'com.apple.security.application-groups': ['group.com.pushly.shared'],
      'com.apple.developer.family-controls': true
    },
    infoPlist: {
      NSExtension: {
        NSExtensionPointIdentifier: 'com.apple.ManagedSettingsUI.shield-action-service',
        NSExtensionPrincipalClass: 'PushlyShieldActionExtension'
      }
    }
  }
};
