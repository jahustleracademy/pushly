import React from 'react';
import { StyleSheet, View, ViewProps } from 'react-native';
import { useTheme } from '@/components/shared/ThemeProvider';

export function Card({ style, ...props }: ViewProps) {
  const { theme } = useTheme();

  return (
    <View
      {...props}
      style={[
        styles.base,
        {
          backgroundColor: theme.colors.surfaceElevated,
          borderColor: theme.colors.border
        },
        style
      ]}
    />
  );
}

const styles = StyleSheet.create({
  base: {
    borderRadius: 16,
    borderWidth: 1,
    padding: 16
  }
});
