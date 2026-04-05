import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function WorkoutScreen() {
  return (
    <PlaceholderTemplate
      title="Schutzmodi"
      subtitle="Hier koennen spaeter unterschiedliche Sperr- und Unlock-Profile fuer Arbeit, Lernen und Freizeit entstehen."
      todos={['Arbeitsmodus', 'Abendmodus', 'strenger Fokusmodus']}
      links={[{ href: '/session', label: 'Detektion ansehen' }]}
    />
  );
}
