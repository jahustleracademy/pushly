import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function SessionScreen() {
  return (
    <PlaceholderTemplate
      title="Session"
      subtitle="Live training runtime where camera, pose, and counters will run in real time."
      todos={[
        'camera preview with frame lifecycle handling',
        'pose model inference loop',
        'push-up and squat rep state machine',
        'session timeline and persistence'
      ]}
      links={[{ href: '/progress', label: 'See Progress' }]}
    />
  );
}
