import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function SessionScreen() {
  return (
    <PlaceholderTemplate
      title="Detektion"
      subtitle="Hier wird spaeter die echte Liegestuetz-Erkennung, Kamera-Pruefung und Unlock-Session laufen."
      todos={[
        'Kamera-Preview',
        'Liegestuetz-Erkennung',
        'Unlock-Session State',
        'Session-Verlauf'
      ]}
      links={[{ href: '/progress', label: 'Zum Verlauf' }]}
    />
  );
}
