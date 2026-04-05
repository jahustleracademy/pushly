export default {
  name: 'pushly-device-activity-monitor',
  displayName: 'Pushly Monitor',
  type: 'device-activity-monitor',
  platforms: ['ios'],
  appGroup: 'group.com.pushly.shared',
  ios: {
    deploymentTarget: '16.0',
    frameworks: ['DeviceActivity', 'ManagedSettings', 'FamilyControls'],
    entitlements: {
      'com.apple.security.application-groups': ['group.com.pushly.shared'],
      'com.apple.developer.family-controls': true
    }
  }
};
