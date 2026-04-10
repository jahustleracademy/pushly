import React from 'react';
import { Image, StyleSheet, View } from 'react-native';
import { Link } from 'expo-router';
import { Screen } from '@/components/ui/Screen';
import { Card } from '@/components/ui/Card';
import { Text } from '@/components/ui/Text';
import { Button } from '@/components/ui/Button';
import { useTheme } from '@/components/shared/ThemeProvider';
import { useCreditsDashboard } from '@/features/credits';

export function HomeScreen() {
  const { theme } = useTheme();
  const { state, availableMinutes, todayPushups, todayRedeemedMinutes, remainingUnlockMs, remainingUnlockLabel } = useCreditsDashboard();

  return (
    <Screen>
      <View style={styles.top}>
        <Image source={require('../../../assets/images/logo_header.png')} style={styles.logo} resizeMode="contain" />
        <Text variant="title">Heute zaehlt jede Wiederholung.</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted }}>
          Sammle Credits mit Push-ups und loese sie spaeter als Free Time ein.
        </Text>
      </View>

      <Card style={styles.heroCard}>
        <Text variant="caption" style={{ color: theme.colors.accent }}>
          DAILY DASHBOARD
        </Text>
        <Text variant="heading">{state.dailyCredits.balance} Credits verfuegbar</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted }}>{availableMinutes} Minuten Free Time moeglich.</Text>
      </Card>

      <View style={styles.metricRow}>
        <Card style={styles.metricCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Push-ups heute
          </Text>
          <Text variant="heading">{todayPushups}</Text>
        </Card>
        <Card style={styles.metricCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Verdient heute
          </Text>
          <Text variant="heading">{state.dailyCredits.earned} Credits</Text>
        </Card>
      </View>

      <View style={styles.metricRow}>
        <Card style={styles.metricCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Eingeloest heute
          </Text>
          <Text variant="heading">{todayRedeemedMinutes} Min</Text>
        </Card>
        <Card style={styles.metricCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Verbleibend
          </Text>
          <Text variant="heading">{state.dailyCredits.balance} Credits</Text>
        </Card>
      </View>

      <Card style={styles.actionCard}>
        <Text variant="heading">Heute aktiv</Text>
        {state.activeUnlockWindow && remainingUnlockMs > 0 ? (
          <Text variant="body" style={{ color: theme.colors.accent }}>
            Unlock aktiv: noch {remainingUnlockLabel}
          </Text>
        ) : (
          <Text variant="body" style={{ color: theme.colors.textMuted }}>
            Kein aktives Unlock-Fenster.
          </Text>
        )}

        <View style={styles.actions}>
          <Link href="/session" asChild>
            <Button label="Push-ups starten" />
          </Link>
          <Link href="/redeem" asChild>
            <Button label="Zeit einloesen" variant="secondary" />
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
