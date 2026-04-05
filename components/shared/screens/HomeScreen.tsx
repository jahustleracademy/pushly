import React from 'react';
import { Image, StyleSheet, View } from 'react-native';
import { Link } from 'expo-router';
import { Screen } from '@/components/ui/Screen';
import { Card } from '@/components/ui/Card';
import { Text } from '@/components/ui/Text';
import { Button } from '@/components/ui/Button';
import { useTheme } from '@/components/shared/ThemeProvider';

export function HomeScreen() {
  const { theme } = useTheme();

  return (
    <Screen>
      <View style={styles.top}>
        <Image source={require('../../../assets/images/logo_header.png')} style={styles.logo} resizeMode="contain" />
        <Text variant="title">Dein Schutz ist jetzt nativ aufgesetzt.</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted }}>
          Onboarding, iOS Screen-Time-Basis, Device-Activity-Target und die Live-Pose-Pipeline sind in Pushly verankert.
        </Text>
      </View>

      <Card style={styles.heroCard}>
        <Text variant="caption" style={{ color: theme.colors.accent }}>
          SYSTEM STATUS
        </Text>
        <Text variant="heading">Pushly V1 schützt deine Trigger-Apps mit Reibung statt Erinnerung.</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted }}>
          Die App verfügt jetzt über echte iOS-Scaffolds für Family Controls, Shield-Aktivierung und Vision-basierte Push-up-Erkennung.
        </Text>
      </Card>

      <View style={styles.metricRow}>
        <Card style={styles.metricCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Unlock-Regel
          </Text>
          <Text variant="heading">Liegestütze</Text>
        </Card>
        <Card style={styles.metricCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Native Basis
          </Text>
          <Text variant="heading">iOS first</Text>
        </Card>
      </View>

      <Card style={styles.actionCard}>
        <Text variant="heading">Bereite Bereiche</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted }}>
          Die Session-Fläche zeigt dir als Nächstes die native Kamera-/Pose-Schicht, und in den Einstellungen hängen wir echte Schutz- und Account-Flows an.
        </Text>

        <View style={styles.actions}>
          <Link href="/session" asChild>
            <Button label="Detektion ansehen" />
          </Link>
          <Link href="/progress" asChild>
            <Button label="Verlauf ansehen" variant="secondary" />
          </Link>
        </View>
      </Card>
    </Screen>
  );
}

const styles = StyleSheet.create({
  top: {
    gap: 10,
    marginBottom: 18
  },
  logo: {
    width: 150,
    height: 46
  },
  heroCard: {
    gap: 10,
    marginBottom: 14
  },
  metricRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 14
  },
  metricCard: {
    flex: 1,
    gap: 8
  },
  actionCard: {
    gap: 12
  },
  actions: {
    gap: 10
  }
});
