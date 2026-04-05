import React from 'react';
import { Text as RNText, TextProps, StyleSheet } from 'react-native';
import { useTheme } from '@/components/shared/ThemeProvider';

type Variant = 'title' | 'heading' | 'body' | 'caption';

type Props = TextProps & {
  variant?: Variant;
};

export function Text({ variant = 'body', style, ...props }: Props) {
  const { theme } = useTheme();
  const variantStyle = variantStyles(theme);

  return <RNText {...props} style={[variantStyle[variant], { color: theme.colors.text }, style]} />;
}

const variantStyles = (theme: ReturnType<typeof useTheme>['theme']) =>
  StyleSheet.create({
    title: {
      fontSize: 32,
      lineHeight: 36,
      fontFamily: theme.typography.heavy,
      letterSpacing: -0.8
    },
    heading: {
      fontSize: 22,
      lineHeight: 27,
      fontFamily: theme.typography.bold,
      letterSpacing: -0.4
    },
    body: {
      fontSize: 16,
      lineHeight: 23,
      fontFamily: theme.typography.regular
    },
    caption: {
      fontSize: 13,
      lineHeight: 17,
      fontFamily: theme.typography.medium
    }
  });
