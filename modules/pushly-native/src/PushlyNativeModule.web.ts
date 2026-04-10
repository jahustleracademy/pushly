import { registerWebModule, NativeModule } from 'expo';

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
  private sharedCreditsSnapshot: string | null = null;
  private pendingShieldRedeemIntent: string | null = null;

  async getScreenTimeAuthorizationStatusAsync(): Promise<ScreenTimeAuthorizationStatus> {
    return 'unsupported';
  }

  async requestScreenTimeAuthorizationAsync(): Promise<ScreenTimeAuthorizationStatus> {
    return 'unsupported';
  }

  async presentFamilyActivityPickerAsync(): Promise<ProtectedSelectionSummary> {
    return {
      appCount: 3,
      categoryCount: 1,
      webDomainCount: 0,
      hasSelection: true,
      lastUpdatedAt: new Date().toISOString()
    };
  }

  async getStoredSelectionSummaryAsync(): Promise<ProtectedSelectionSummary> {
    return this.presentFamilyActivityPickerAsync();
  }

  async applyStoredShieldAsync(): Promise<ShieldStatus> {
    return 'active';
  }

  async clearShieldAsync(): Promise<ShieldStatus> {
    return 'inactive';
  }

  async getCameraAuthorizationStatusAsync(): Promise<CameraAuthorizationStatus> {
    return 'authorized';
  }

  async startDeviceActivityMonitoringAsync(): Promise<DeviceActivityMonitoringStatus> {
    return 'active';
  }

  async stopDeviceActivityMonitoringAsync(): Promise<DeviceActivityMonitoringStatus> {
    return 'inactive';
  }

  async getDeviceActivityMonitoringStatusAsync(): Promise<DeviceActivityMonitoringStatus> {
    return 'active';
  }

  async isPoseEngineAvailableAsync(): Promise<boolean> {
    return true;
  }

  async exportPoseDebugSessionAsync(): Promise<PoseDebugExportResult> {
    return { path: '' };
  }

  async getSharedCreditsSnapshotAsync(): Promise<string | null> {
    return this.sharedCreditsSnapshot;
  }

  async setSharedCreditsSnapshotAsync(snapshot: string): Promise<void> {
    this.sharedCreditsSnapshot = snapshot;
  }

  async getPendingShieldRedeemIntentAsync(): Promise<string | null> {
    return this.pendingShieldRedeemIntent;
  }

  async setPendingShieldRedeemIntentAsync(intent: string): Promise<void> {
    this.pendingShieldRedeemIntent = intent;
  }

  async consumePendingShieldRedeemIntentAsync(): Promise<string | null> {
    const current = this.pendingShieldRedeemIntent;
    this.pendingShieldRedeemIntent = null;
    return current;
  }
}

export default registerWebModule(PushlyNativeModule, 'PushlyNative');
