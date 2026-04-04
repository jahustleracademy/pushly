import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function SettingsScreen() {
  return (
    <PlaceholderTemplate
      title="Settings"
      subtitle="Account, profile, app preferences, and privacy controls."
      todos={['account management', 'notification preferences', 'privacy and legal surfaces']}
      links={[
        { href: '/(auth)/login', label: 'Login' },
        { href: '/(auth)/signup', label: 'Signup' }
      ]}
    />
  );
}
