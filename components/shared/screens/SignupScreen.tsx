import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function SignupScreen() {
  return (
    <PlaceholderTemplate
      title="Signup"
      subtitle="Create account flow. Currently scaffold only."
      todos={['email/password sign up', 'profile bootstrap', 'onboarding transition']}
      links={[{ href: '/(auth)/login', label: 'Already have an account?' }]}
    />
  );
}
