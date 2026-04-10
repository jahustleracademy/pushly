import { PushlyNative, type DeviceActivityMonitoringStatus, type ProtectedSelectionSummary, type ScreenTimeAuthorizationStatus } from '@/lib/native/pushly-native';

export type ProtectionStatusSnapshot = {
  authorizationStatus: ScreenTimeAuthorizationStatus;
  selectionSummary: ProtectedSelectionSummary;
  monitoringStatus: DeviceActivityMonitoringStatus;
};

export const protectionStatusService = {
  loadSnapshot: async (): Promise<ProtectionStatusSnapshot> => {
    const [authorizationStatus, selectionSummary, monitoringStatus] = await Promise.all([
      PushlyNative.getScreenTimeAuthorizationStatus(),
      PushlyNative.getStoredSelectionSummary(),
      PushlyNative.getDeviceActivityMonitoringStatus()
    ]);

    return {
      authorizationStatus,
      selectionSummary,
      monitoringStatus
    };
  }
};
