import { NativeModule, requireNativeModule } from 'expo';

import type {
  CameraAuthorizationStatus,
  DeviceActivityMonitoringStatus,
  PoseDebugExportResult,
  ProtectedSelectionSummary,
  PushlyNativeModuleEvents,
  ScreenTimeAuthorizationStatus,
  ShieldStatus
} from './PushlyNative.types';

declare class PushlyNativeModule extends NativeModule<PushlyNativeModuleEvents> {
  getScreenTimeAuthorizationStatusAsync(): Promise<ScreenTimeAuthorizationStatus>;
  requestScreenTimeAuthorizationAsync(): Promise<ScreenTimeAuthorizationStatus>;
  presentFamilyActivityPickerAsync(): Promise<ProtectedSelectionSummary>;
  getStoredSelectionSummaryAsync(): Promise<ProtectedSelectionSummary>;
  applyStoredShieldAsync(): Promise<ShieldStatus>;
  clearShieldAsync(): Promise<ShieldStatus>;
  getCameraAuthorizationStatusAsync(): Promise<CameraAuthorizationStatus>;
  startDeviceActivityMonitoringAsync(): Promise<DeviceActivityMonitoringStatus>;
  stopDeviceActivityMonitoringAsync(): Promise<DeviceActivityMonitoringStatus>;
  getDeviceActivityMonitoringStatusAsync(): Promise<DeviceActivityMonitoringStatus>;
  isPoseEngineAvailableAsync(): Promise<boolean>;
  exportPoseDebugSessionAsync(): Promise<PoseDebugExportResult>;
}

export default requireNativeModule<PushlyNativeModule>('PushlyNative');
