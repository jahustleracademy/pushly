import React, { useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Screen } from '@/components/ui/Screen';
import { Card } from '@/components/ui/Card';
import { Text } from '@/components/ui/Text';
import { useTheme } from '@/components/shared/ThemeProvider';
import { getDailyHistory, getTodayActivity, getTodayPushups, getTodayRedeemedMinutes, useCreditsRuntime } from '@/features/credits';

export function ProgressScreen() {
  const { theme } = useTheme();
  const { state } = useCreditsRuntime();

  const todayPushups = useMemo(() => getTodayPushups(state), [state]);
  const todayRedeemedMinutes = useMemo(() => getTodayRedeemedMinutes(state), [state]);
  const todayActivity = useMemo(() => getTodayActivity(state), [state]);
  const history = useMemo(() => getDailyHistory(state, 5), [state]);

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.top}>
          <Text variant="title">Verlauf</Text>
          <Text variant="body" style={{ color: theme.colors.textMuted }}>
            Dein heutiger Fortschritt und die letzten Aktivitaeten.
          </Text>
        </View>

        <View style={styles.metricRow}>
          <Card style={styles.metricCard}>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>Push-ups heute</Text>
            <Text variant="heading">{todayPushups}</Text>
          </Card>
          <Card style={styles.metricCard}>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>Credits heute</Text>
            <Text variant="heading">{state.dailyCredits.earned}</Text>
          </Card>
        </View>

        <View style={styles.metricRow}>
          <Card style={styles.metricCard}>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>Eingeloest heute</Text>
            <Text variant="heading">{todayRedeemedMinutes} Min</Text>
          </Card>
          <Card style={styles.metricCard}>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>Verbleibend</Text>
            <Text variant="heading" style={{ color: theme.colors.accent }}>{state.dailyCredits.balance}</Text>
          </Card>
        </View>

        <Card style={styles.sectionCard}>
          <Text variant="heading">Heutige Aktivitaeten</Text>
          {todayActivity.length === 0 ? (
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              Heute noch keine Aktivitaet.
            </Text>
          ) : (
            todayActivity.map((activity) => (
              <View key={activity.id} style={styles.activityRow}>
                <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                  {new Date(activity.at).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}
                </Text>
                <Text variant="caption">{activity.label}</Text>
                <Text
                  variant="caption"
                  style={{ color: activity.creditsDelta >= 0 ? theme.colors.accent : theme.colors.dangerSoft }}
                >
                  {activity.creditsDelta >= 0 ? `+${activity.creditsDelta}` : activity.creditsDelta}
                </Text>
              </View>
            ))
          )}
        </Card>

        <Card style={styles.sectionCard}>
          <Text variant="heading">Letzte Tage</Text>
          {history.map((day) => (
            <View key={day.dateKey} style={styles.historyRow}>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>{day.dateKey}</Text>
              <Text variant="caption">{day.pushups} Push-ups</Text>
              <Text variant="caption">{day.earnedCredits} Credits</Text>
              <Text variant="caption">{day.redeemedMinutes} Min</Text>
            </View>
          ))}
        </Card>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: 14,
    paddingBottom: 24
  },
  top: {
    gap: 8
  },
  metricRow: {
    flexDirection: 'row',
    gap: 10
  },
  metricCard: {
    flex: 1,
    gap: 6
  },
  sectionCard: {
    gap: 10
  },
  activityRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center'
  },
  historyRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center'
  }
});
