import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function HomeScreen() {
  return (
    <PlaceholderTemplate
      title="Pushly"
      subtitle="AI fitness foundation with clean infra, modular features, and iOS-first architecture."
      todos={[
        'live camera preview module integration',
        'on-device pose detection pipeline',
        'real-time push-up counter calibration',
        'real-time squat counter calibration',
        'workout session engine orchestration'
      ]}
      links={[
        { href: '/workout', label: 'Open Workout' },
        { href: '/session', label: 'Open Session' },
        { href: '/paywall', label: 'Open Paywall' }
      ]}
    />
  );
}
