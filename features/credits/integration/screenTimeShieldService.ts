import { PushlyNative } from '@/lib/native/pushly-native';

export type ShieldRuntimeService = {
  beginTimedUnlock: () => Promise<void>;
  endTimedUnlock: () => Promise<void>;
  ensureShieldingActive: () => Promise<void>;
};

export const screenTimeShieldService: ShieldRuntimeService = {
  beginTimedUnlock: async () => {
    await PushlyNative.stopDeviceActivityMonitoring();
    await PushlyNative.clearShield();
  },
  endTimedUnlock: async () => {
    await PushlyNative.applyStoredShield();
    await PushlyNative.startDeviceActivityMonitoring();
  },
  ensureShieldingActive: async () => {
    await PushlyNative.applyStoredShield();
    await PushlyNative.startDeviceActivityMonitoring();
  }
};
