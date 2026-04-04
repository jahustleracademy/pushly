import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function WorkoutScreen() {
  return (
    <PlaceholderTemplate
      title="Workout"
      subtitle="Program templates, exercise selection, and future AI coaching entry point."
      todos={['exercise plan model', 'adaptive workout generator', 'warm-up and cooldown flows']}
      links={[{ href: '/session', label: 'Start Session (Placeholder)' }]}
    />
  );
}
