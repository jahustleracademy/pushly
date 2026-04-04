import React from 'react';
import { Text as RNText, TextProps, StyleSheet } from 'react-native';
import { useTheme } from '@/components/shared/ThemeProvider';

type Variant = 'title' | 'heading' | 'body' | 'caption';

type Props = TextProps & {
  variant?: Variant;
};

export function Text({ variant = 'body', style, ...props }: Props) {
  const { theme } = useTheme();

  return <RNText {...props} style={[styles[variant], { color: theme.colors.text }, style]} />;
}

const styles = StyleSheet.create({
  title: {
    fontSize: 30,
    lineHeight: 36,
    fontFamily: 'Sora_700Bold'
  },
  heading: {
    fontSize: 22,
    lineHeight: 28,
    fontFamily: 'Sora_600SemiBold'
  },
  body: {
    fontSize: 16,
    lineHeight: 22,
    fontFamily: 'Sora_400Regular'
  },
  caption: {
    fontSize: 13,
    lineHeight: 18,
    fontFamily: 'Sora_500Medium'
  }
});
