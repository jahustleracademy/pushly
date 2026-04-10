import { useMemo, useState } from 'react';
import { useCreditsRuntime } from './useCreditsRuntime';
import type { RedeemSource } from '@/features/credits/domain/models';

export function useRedeemFlow(initialMinutes = '15', source: RedeemSource = 'app') {
  const { state, redeemMinutes } = useCreditsRuntime();
  const [minutesInput, setMinutesInput] = useState(initialMinutes);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const requestedMinutes = useMemo(() => {
    const parsed = Number(minutesInput);
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    return Math.max(0, Math.floor(parsed));
  }, [minutesInput]);

  const canSubmit = requestedMinutes > 0 && state.dailyCredits.balance >= requestedMinutes && !isSubmitting;

  const submit = async () => {
    if (!canSubmit) {
      return null;
    }

    setIsSubmitting(true);
    try {
      const result = await redeemMinutes(requestedMinutes, source);
      setMessage(`Unlock aktiv bis ${new Date(result.unlockWindow.endsAt).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}`);
      return result;
    } catch (error) {
      const text = error instanceof Error ? error.message : 'Einloesen fehlgeschlagen';
      setMessage(text);
      return null;
    } finally {
      setIsSubmitting(false);
    }
  };

  return {
    state,
    minutesInput,
    setMinutesInput,
    requestedMinutes,
    canSubmit,
    isSubmitting,
    message,
    submit
  };
}
