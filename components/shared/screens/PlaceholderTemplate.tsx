import React from 'react';
import { StyleSheet, View } from 'react-native';
import { Link } from 'expo-router';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { useTheme } from '@/components/shared/ThemeProvider';

type Props = {
  title: string;
  subtitle: string;
  todos?: string[];
  links?: { href: string; label: string }[];
};

export function PlaceholderTemplate({ title, subtitle, todos = [], links = [] }: Props) {
  const { theme } = useTheme();

  return (
    <Screen>
      <View style={styles.topGap}>
        <Text variant="title">{title}</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted, marginTop: 8 }}>
          {subtitle}
        </Text>
      </View>

      <Card style={styles.card}>
        <Text variant="heading">Roadmap Hooks</Text>
        {todos.map((todo) => (
          <Text key={todo} variant="body" style={styles.todo}>
            TODO: {todo}
          </Text>
        ))}
      </Card>

      <View style={styles.actions}>
        {links.map((item) => (
          <Link key={item.label} href={item.href as never} asChild>
            <Button label={item.label} variant="secondary" />
          </Link>
        ))}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  topGap: {
    marginBottom: 20
  },
  card: {
    marginBottom: 16,
    gap: 10
  },
  todo: {
    opacity: 0.95
  },
  actions: {
    gap: 12
  }
});
