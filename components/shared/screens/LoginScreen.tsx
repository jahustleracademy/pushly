import React from 'react';
import { PlaceholderTemplate } from './PlaceholderTemplate';

export function LoginScreen() {
  return (
    <PlaceholderTemplate
      title="Login"
      subtitle="Auth entry point. Currently scaffold only."
      todos={['email/password sign in', 'magic link option', 'session restore handling']}
      links={[{ href: '/(auth)/signup', label: 'Need an account?' }]}
    />
  );
}
