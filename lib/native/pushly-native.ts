import PushlyNativeModule, {
  type CameraAuthorizationStatus,
  type DeviceActivityMonitoringStatus,
  PushlyCameraView,
  type PoseFrame,
  type ProtectedSelectionSummary,
  type PushUpDetectionState,
  type ScreenTimeAuthorizationStatus,
  type ShieldStatus,
  type SkeletonJoint
} from '@/modules/pushly-native';

export { PushlyCameraView };

export type {
  PoseFrame,
  ProtectedSelectionSummary,
  PushUpDetectionState,
  ScreenTimeAuthorizationStatus,
  CameraAuthorizationStatus,
  DeviceActivityMonitoringStatus,
  ShieldStatus,
  SkeletonJoint
};

export const PushlyNative = {
  getScreenTimeAuthorizationStatus: () => PushlyNativeModule.getScreenTimeAuthorizationStatusAsync(),
  requestScreenTimeAuthorization: () => PushlyNativeModule.requestScreenTimeAuthorizationAsync(),
  presentFamilyActivityPicker: () => PushlyNativeModule.presentFamilyActivityPickerAsync(),
  getStoredSelectionSummary: () => PushlyNativeModule.getStoredSelectionSummaryAsync(),
  applyStoredShield: () => PushlyNativeModule.applyStoredShieldAsync(),
  clearShield: () => PushlyNativeModule.clearShieldAsync(),
  getCameraAuthorizationStatus: () => PushlyNativeModule.getCameraAuthorizationStatusAsync(),
  startDeviceActivityMonitoring: () => PushlyNativeModule.startDeviceActivityMonitoringAsync(),
  stopDeviceActivityMonitoring: () => PushlyNativeModule.stopDeviceActivityMonitoringAsync(),
  getDeviceActivityMonitoringStatus: () => PushlyNativeModule.getDeviceActivityMonitoringStatusAsync(),
  isPoseEngineAvailable: () => PushlyNativeModule.isPoseEngineAvailableAsync()
};
