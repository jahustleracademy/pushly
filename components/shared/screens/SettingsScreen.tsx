import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function SettingsScreen() {
  return (
    <PlaceholderTemplate
      title="Einstellungen"
      subtitle="Schutz-Apps, Kamera-Pruefung, Account und spaetere Paywall-/Abo-Einstellungen."
      todos={['Schutz-Apps verwalten', 'Kamera und Erkennung', 'Account und Rechtliches']}
      links={[
        { href: '/(auth)/login', label: 'Login' },
        { href: '/(auth)/signup', label: 'Signup' }
      ]}
    />
  );
}
