import { ConfigContext, ExpoConfig } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'Pushly',
  slug: 'pushly',
  scheme: 'pushly',
  version: '0.1.0',
  orientation: 'portrait',
  userInterfaceStyle: 'dark',
  ios: {
    supportsTablet: false,
    bundleIdentifier: 'com.pushly.app',
    infoPlist: {
      NSCameraUsageDescription:
        'Pushly uses the camera to power real-time exercise tracking and pose detection.'
    }
  },
  android: {
    package: 'com.pushly.app'
  },
  plugins: ['expo-router'],
  experiments: {
    typedRoutes: true
  },
  extra: {
    eas: {
      projectId: '00000000-0000-0000-0000-000000000000'
    }
  }
});
