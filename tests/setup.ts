import { beforeEach, vi } from 'vitest';

const asyncStorageState = new Map<string, string>();
const sharedState = {
  creditsSnapshot: null as string | null,
  pendingIntent: null as string | null
};

vi.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    async getItem(key: string) {
      return asyncStorageState.has(key) ? asyncStorageState.get(key)! : null;
    },
    async setItem(key: string, value: string) {
      asyncStorageState.set(key, value);
    },
    async removeItem(key: string) {
      asyncStorageState.delete(key);
    }
  }
}));

vi.mock('@/lib/native/pushly-native', () => ({
  PushlyNative: {
    getSharedCreditsSnapshot: async () => sharedState.creditsSnapshot,
    setSharedCreditsSnapshot: async (snapshot: string) => {
      sharedState.creditsSnapshot = snapshot;
    },
    getPendingShieldRedeemIntent: async () => sharedState.pendingIntent,
    setPendingShieldRedeemIntent: async (intent: string) => {
      sharedState.pendingIntent = intent;
    },
    consumePendingShieldRedeemIntent: async () => {
      const current = sharedState.pendingIntent;
      sharedState.pendingIntent = null;
      return current;
    },
    stopDeviceActivityMonitoring: async () => 'inactive',
    clearShield: async () => 'inactive',
    applyStoredShield: async () => 'active',
    startDeviceActivityMonitoring: async () => 'active'
  }
}));

beforeEach(() => {
  asyncStorageState.clear();
  sharedState.creditsSnapshot = null;
  sharedState.pendingIntent = null;
});
