import React from 'react';
import { ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { Screen } from '@/components/ui/Screen';
import { Card } from '@/components/ui/Card';
import { Text } from '@/components/ui/Text';
import { Button } from '@/components/ui/Button';
import { useTheme } from '@/components/shared/ThemeProvider';
import { useCreditsDashboard, useRedeemFlow } from '@/features/credits';

const QUICK_MINUTES = [10, 15, 30, 45, 60];

export function RedeemScreen() {
  const { theme } = useTheme();
  const params = useLocalSearchParams<{ source?: string; minutes?: string }>();
  const incomingSource = params.source === 'shield' ? 'shield' : 'app';
  const initialMinutes = typeof params.minutes === 'string' && Number.isFinite(Number(params.minutes))
    ? `${Math.max(1, Math.floor(Number(params.minutes)))}`
    : '15';
  const { state, availableMinutes, remainingUnlockMs, remainingUnlockLabel } = useCreditsDashboard();
  const { minutesInput, setMinutesInput, requestedMinutes, canSubmit, isSubmitting, message, submit } = useRedeemFlow(initialMinutes, incomingSource);

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.top}>
          <Text variant="title">Free Time einloesen</Text>
          <Text variant="body" style={{ color: theme.colors.textMuted }}>
            Credits werden sofort abgezogen und Apps danach automatisch wieder gesperrt.
          </Text>
          {incomingSource === 'shield' ? (
            <Text variant="caption" style={{ color: theme.colors.accent }}>
              Shield-Flow: Waehle Minuten und bestaetige den Unlock.
            </Text>
          ) : null}
        </View>

        <Card style={styles.summaryCard}>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>Verfuegbare Credits</Text>
          <Text variant="heading" style={{ color: theme.colors.accent }}>{state.dailyCredits.balance}</Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>Entspricht {availableMinutes} Minuten</Text>
        </Card>

        <Card style={styles.redeemCard}>
          <Text variant="heading">Minuten waehlen</Text>
          <TextInput
            value={minutesInput}
            onChangeText={setMinutesInput}
            keyboardType="number-pad"
            style={[styles.input, { color: theme.colors.text, borderColor: theme.colors.border }]}
            placeholder="Minuten"
            placeholderTextColor={theme.colors.textMuted}
          />

          <View style={styles.quickRow}>
            {QUICK_MINUTES.map((value) => (
              <View key={value} style={styles.quickCell}>
                <Button label={`${value}m`} variant={requestedMinutes === value ? 'primary' : 'secondary'} onPress={() => setMinutesInput(`${value}`)} />
              </View>
            ))}
          </View>

          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Einloesen: {requestedMinutes} Credits fuer {requestedMinutes} Minuten.
          </Text>

          <Button
            label={isSubmitting ? 'Wird eingeloest ...' : 'Jetzt entsperren'}
            onPress={() => {
              void submit();
            }}
            variant={canSubmit ? 'primary' : 'secondary'}
          />

          {!canSubmit ? (
            <Text variant="caption" style={{ color: theme.colors.dangerSoft }}>
              Nicht genug Credits oder ungueltige Minutenanzahl.
            </Text>
          ) : null}

          {message ? (
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              {message}
            </Text>
          ) : null}
        </Card>

        <Card style={styles.statusCard}>
          <Text variant="heading">Aktiver Unlock</Text>
          {state.activeUnlockWindow && remainingUnlockMs > 0 ? (
            <>
              <Text variant="body" style={{ color: theme.colors.accent }}>Noch {remainingUnlockLabel}</Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                Ende: {new Date(state.activeUnlockWindow.endsAt).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}
              </Text>
            </>
          ) : (
            <Text variant="caption" style={{ color: theme.colors.textMuted }}>
              Aktuell kein Unlock aktiv.
            </Text>
          )}
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
  summaryCard: {
    gap: 6
  },
  redeemCard: {
    gap: 10
  },
  input: {
    minHeight: 50,
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 12,
    fontSize: 18
  },
  quickRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8
  },
  quickCell: {
    width: '30%'
  },
  statusCard: {
    gap: 8
  }
});
