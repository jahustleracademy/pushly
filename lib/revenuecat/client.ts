import { Platform } from 'react-native';
import Purchases, { CustomerInfo, LOG_LEVEL } from 'react-native-purchases';
import { env } from '@/lib/config/env';

let isConfigured = false;

function getRevenueCatKey() {
  if (Platform.OS === 'ios') return env.revenueCatIosApiKey;
  if (Platform.OS === 'android') return env.revenueCatAndroidApiKey;
  return '';
}

export async function initRevenueCat() {
  if (isConfigured) {
    return true;
  }

  const apiKey = getRevenueCatKey();
  if (!apiKey) {
    console.warn('[Pushly][RevenueCat] Missing API key. Running in disabled mode.');
    return false;
  }

  Purchases.configure({ apiKey });
  if (__DEV__) {
    Purchases.setLogLevel(LOG_LEVEL.DEBUG);
  }

  isConfigured = true;
  return true;
}

export function hasActiveSubscription(customerInfo: CustomerInfo, entitlement = 'pro') {
  return Boolean(customerInfo.entitlements.active[entitlement]);
}

export async function getCustomerInfo() {
  const ready = await initRevenueCat();
  if (!ready) {
    return null;
  }
  return Purchases.getCustomerInfo();
}

export async function restorePurchases(entitlement = 'pro') {
  const ready = await initRevenueCat();
  if (!ready) {
    return false;
  }
  const info = await Purchases.restorePurchases();
  return hasActiveSubscription(info, entitlement);
}
