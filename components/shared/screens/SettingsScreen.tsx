import React, { useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Link, useRouter } from 'expo-router';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { useTheme } from '@/components/shared/ThemeProvider';
import { routes } from '@/constants/routes';
import { resetOnboardingProgress } from '@/features/onboarding/storage';
import { CREDITS_PER_PUSHUP, MINUTES_PER_CREDIT, useCreditsRuntime, useProtectionStatus } from '@/features/credits';

export function SettingsScreen() {
  const router = useRouter();
  const { theme } = useTheme();
  const [isResettingOnboarding, setIsResettingOnboarding] = useState(false);
  const { state } = useCreditsRuntime();
  const { loading, snapshot, error, refresh } = useProtectionStatus();

  const handleRestartOnboarding = async () => {
    if (isResettingOnboarding) {
      return;
    }

    try {
      setIsResettingOnboarding(true);
      await resetOnboardingProgress();
      router.replace(routes.onboarding as never);
    } finally {
      setIsResettingOnboarding(false);
    }
  };

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.topGap}>
          <Text variant="title">Einstellungen</Text>
          <Text variant="body" style={{ color: theme.colors.textMuted, marginTop: 8 }}>
            Schutzstatus, Regeln und Runtime-Management fuer v1.
          </Text>
        </View>

        <Card style={styles.card}>
          <Text variant="heading">Screen Time Status</Text>
          {loading ? (
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>Status wird geladen ...</Text>
          ) : (
            <>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                Berechtigung: {snapshot?.authorizationStatus ?? 'unbekannt'}
              </Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                Auswahl: Apps {snapshot?.selectionSummary.appCount ?? 0}, Kategorien {snapshot?.selectionSummary.categoryCount ?? 0}, Domains {snapshot?.selectionSummary.webDomainCount ?? 0}
              </Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                Monitoring: {snapshot?.monitoringStatus ?? 'unbekannt'}
              </Text>
            </>
          )}
          {error ? (
            <Text variant="caption" style={{ color: theme.colors.dangerSoft }}>
              {error}
            </Text>
          ) : null}
          <Button label="Status aktualisieren" variant="secondary" onPress={() => { void refresh(); }} />
        </Card>

        <Card style={styles.card}>
          <Text variant="heading">Unlock-Regeln (v1)</Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Nur Push-ups sind aktiv.
          </Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            1 Push-up = {CREDITS_PER_PUSHUP} Credits.
          </Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            1 Credit = {MINUTES_PER_CREDIT} Minute.
          </Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Credits resetten taeglich automatisch.
          </Text>
        </Card>

        <Card style={styles.card}>
          <Text variant="heading">Hinweise</Text>
          {snapshot?.authorizationStatus !== 'approved' ? (
            <Text variant="caption" style={{ color: theme.colors.dangerSoft }}>
              Screen-Time-Berechtigung fehlt. Unlock funktioniert nur eingeschraenkt.
            </Text>
          ) : null}
          {snapshot && !snapshot.selectionSummary.hasSelection ? (
            <Text variant="caption" style={{ color: theme.colors.dangerSoft }}>
              Es sind keine Apps fuer den Schutz ausgewaehlt.
            </Text>
          ) : null}
          {snapshot?.authorizationStatus === 'approved' && snapshot.selectionSummary.hasSelection ? (
            <Text variant="caption" style={{ color: theme.colors.accent }}>
              Schutzkonfiguration ist vorhanden.
            </Text>
          ) : null}
        </Card>

        {__DEV__ ? (
          <Card style={styles.card}>
            <Text variant="heading">Debug (Development)</Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              dateKey: {state.dailyCredits.dateKey}
            </Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              balance: {state.dailyCredits.balance}, earned: {state.dailyCredits.earned}, spent: {state.dailyCredits.spent}
            </Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              activeUnlockWindow: {state.activeUnlockWindow ? state.activeUnlockWindow.endsAt : 'none'}
            </Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              lastRedeemRequest: {state.lastRedeemRequest ? state.lastRedeemRequest.requestedAt : 'none'}
            </Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              ledgerEntries: {state.ledger.entries.length}
            </Text>
          </Card>
        ) : null}

        <Card style={styles.card}>
          <Text variant="heading">Management</Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Onboarding und Auth-Entrypoints.
          </Text>
        </Card>

        <View style={styles.actions}>
          <Button
            label={isResettingOnboarding ? 'Onboarding wird gestartet ...' : 'Onboarding neu starten'}
            onPress={() => {
              void handleRestartOnboarding();
            }}
          />
          <Link href="/(auth)/login" asChild>
            <Button label="Login" variant="secondary" />
          </Link>
          <Link href="/(auth)/signup" asChild>
            <Button label="Signup" variant="secondary" />
          </Link>
        </View>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingBottom: 24
  },
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
