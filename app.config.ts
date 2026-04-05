import { ConfigContext, ExpoConfig } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'Pushly',
  slug: 'pushly',
  scheme: 'pushly',
  version: '0.1.0',
  orientation: 'portrait',
  userInterfaceStyle: 'dark',
  icon: './assets/images/icon.png',
  splash: {
    image: './assets/images/splash.jpg',
    resizeMode: 'contain',
    backgroundColor: '#060706'
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: 'com.artur.pushly',
    icon: './assets/images/icon.png',
    entitlements: {
      'com.apple.security.application-groups': ['group.com.pushly.shared'],
      'com.apple.developer.family-controls': true
    },
    infoPlist: {
      NSCameraUsageDescription:
        'Pushly uses the camera to power real-time exercise tracking and pose detection.',
      NSPhotoLibraryAddUsageDescription:
        'Pushly may save premium onboarding and workout visuals to your library when you choose to export them.'
    }
  },
  web: {
    favicon: './assets/images/favicon.png'
  },
  plugins: [
    'expo-router',
    [
      'expo-build-properties',
      {
        ios: {
          deploymentTarget: '16.0'
        }
      }
    ],
    [
      'expo-targets',
      {
        debug: false,
        targetsRoot: './targets'
      }
    ]
  ],
  experiments: {
    typedRoutes: true
  },
  extra: {
    eas: {
      projectId: '00000000-0000-0000-0000-000000000000'
    }
  }
});
