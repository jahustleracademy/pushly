import React from 'react';
import { Pressable, StyleSheet, ViewStyle } from 'react-native';
import { useTheme } from '@/components/shared/ThemeProvider';
import { Text } from '@/components/ui/Text';

type Props = {
  label: string;
  onPress?: () => void;
  variant?: 'primary' | 'secondary';
  style?: ViewStyle;
};

export function Button({ label, onPress, variant = 'primary', style }: Props) {
  const { theme } = useTheme();
  const isPrimary = variant === 'primary';

  return (
    <Pressable
      onPress={onPress}
      style={[
        styles.button,
        {
          backgroundColor: isPrimary ? theme.colors.accent : theme.colors.surfaceElevated,
          borderColor: isPrimary ? theme.colors.accentStrong : theme.colors.border
        },
        style
      ]}
    >
      <Text
        variant="caption"
        style={{
          color: isPrimary ? '#00160E' : theme.colors.text,
          textAlign: 'center'
        }}
      >
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    borderRadius: 14,
    borderWidth: 1,
    minHeight: 50,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16
  }
});
