import React from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Link } from 'expo-router';
import { Screen } from '@/components/ui/Screen';
import { Card } from '@/components/ui/Card';
import { Text } from '@/components/ui/Text';
import { Button } from '@/components/ui/Button';
import { useTheme } from '@/components/shared/ThemeProvider';
import { PushlyCameraView } from '@/lib/native/pushly-native';
import { usePushupSessionFlow } from '@/features/credits/application/usePushupSessionFlow';

export function SessionScreen() {
  const { theme } = useTheme();
  const {
    state,
    isSessionActive,
    latestRepCount,
    sessionEarnedCredits,
    availableMinutes,
    completionSummary,
    handlePoseFrame,
    finishSession,
    startNewSession
  } = usePushupSessionFlow();

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.top}>
          <Text variant="title">Push-up Session</Text>
          <Text variant="body" style={{ color: theme.colors.textMuted }}>
            Jede Wiederholung gibt direkt Credits fuer spaetere Free Time.
          </Text>
        </View>

        <Card style={styles.metricsCard}>
          <View style={styles.metricRow}>
            <View style={styles.metricItem}>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>Session Reps</Text>
              <Text variant="heading">{latestRepCount}</Text>
            </View>
            <View style={styles.metricItem}>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>Session Credits</Text>
              <Text variant="heading" style={{ color: theme.colors.accent }}>{sessionEarnedCredits}</Text>
            </View>
            <View style={styles.metricItem}>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>Verfuegbar</Text>
              <Text variant="heading">{state.dailyCredits.balance}</Text>
            </View>
          </View>
        </Card>

        <View style={styles.cameraWrap}>
          <PushlyCameraView
            isActive={isSessionActive}
            showSkeleton
            repTarget={999}
            poseBackendMode="auto"
            forceFullFrameProcessing={true}
            debugMode={false}
            onPoseFrame={handlePoseFrame}
            style={styles.camera}
          />
        </View>

        <Card style={styles.redeemCard}>
          <Text variant="heading">{isSessionActive ? 'Session aktiv' : 'Session abgeschlossen'}</Text>
          {completionSummary ? (
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              {completionSummary.reps} Reps · {completionSummary.earnedCredits} Credits · {completionSummary.earnedMinutes} Min · {completionSummary.durationSeconds}s
            </Text>
          ) : (
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              Verfuegbar danach: {availableMinutes} Minuten.
            </Text>
          )}

          <Button
            label={isSessionActive ? 'Session beenden' : 'Neue Session starten'}
            onPress={isSessionActive ? finishSession : startNewSession}
          />
          <Link href="/redeem" asChild>
            <Button label="Zeit einloesen" variant="secondary" />
          </Link>

          {state.lastError ? (
            <Text variant="caption" style={{ color: theme.colors.dangerSoft }}>
              Runtime: {state.lastError}
            </Text>
          ) : null}
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
  metricsCard: {
    gap: 12
  },
  metricRow: {
    flexDirection: 'row',
    gap: 10
  },
  metricItem: {
    flex: 1,
    gap: 4
  },
  cameraWrap: {
    borderRadius: 20,
    overflow: 'hidden'
  },
  camera: {
    minHeight: 360,
    width: '100%'
  },
  redeemCard: {
    gap: 10
  }
});
