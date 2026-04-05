import { NativeModule } from 'expo';

import type {
  CameraAuthorizationStatus,
  DeviceActivityMonitoringStatus,
  PoseDebugExportResult,
  ProtectedSelectionSummary,
  PushlyNativeModuleEvents,
  ScreenTimeAuthorizationStatus,
  ShieldStatus
} from './PushlyNative.types';

class PushlyNativeModule extends NativeModule<PushlyNativeModuleEvents> {
  async getScreenTimeAuthorizationStatusAsync(): Promise<ScreenTimeAuthorizationStatus> {
    return 'unsupported';
  }

  async requestScreenTimeAuthorizationAsync(): Promise<ScreenTimeAuthorizationStatus> {
    return 'unsupported';
  }

  async presentFamilyActivityPickerAsync(): Promise<ProtectedSelectionSummary> {
    return {
      appCount: 0,
      categoryCount: 0,
      webDomainCount: 0,
      hasSelection: false,
      lastUpdatedAt: null
    };
  }

  async getStoredSelectionSummaryAsync(): Promise<ProtectedSelectionSummary> {
    return this.presentFamilyActivityPickerAsync();
  }

  async applyStoredShieldAsync(): Promise<ShieldStatus> {
    return 'unsupported';
  }

  async clearShieldAsync(): Promise<ShieldStatus> {
    return 'unsupported';
  }

  async getCameraAuthorizationStatusAsync(): Promise<CameraAuthorizationStatus> {
    return 'unsupported';
  }

  async startDeviceActivityMonitoringAsync(): Promise<DeviceActivityMonitoringStatus> {
    return 'unsupported';
  }

  async stopDeviceActivityMonitoringAsync(): Promise<DeviceActivityMonitoringStatus> {
    return 'unsupported';
  }

  async getDeviceActivityMonitoringStatusAsync(): Promise<DeviceActivityMonitoringStatus> {
    return 'unsupported';
  }

  async isPoseEngineAvailableAsync(): Promise<boolean> {
    return false;
  }

  async exportPoseDebugSessionAsync(): Promise<PoseDebugExportResult> {
    return { path: '' };
  }
}

export default new PushlyNativeModule();
