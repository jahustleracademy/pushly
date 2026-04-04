import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function PaywallScreen() {
  return (
    <PlaceholderTemplate
      title="Paywall"
      subtitle="Subscription funnel powered by RevenueCat foundation."
      todos={['offerings fetch', 'package selection UI', 'restore purchases and entitlement sync']}
    />
  );
}
