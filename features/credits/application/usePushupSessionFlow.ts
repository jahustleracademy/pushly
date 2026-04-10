import { useMemo, useRef, useState } from 'react';
import type { PoseFrame } from '@/lib/native/pushly-native';
import { useCreditsRuntime } from './useCreditsRuntime';
import { challengeRewardPolicy } from '@/features/credits/domain/policies';

export function usePushupSessionFlow() {
  const { state, collectCreditsFromPushupProgress } = useCreditsRuntime();
  const sessionId = useRef(`session_${Date.now()}`);
  const sessionStartedAt = useRef<number | null>(null);

  const [isSessionActive, setIsSessionActive] = useState(true);
  const [latestRepCount, setLatestRepCount] = useState(0);
  const [sessionEarnedCredits, setSessionEarnedCredits] = useState(0);
  const [completionSummary, setCompletionSummary] = useState<{
    reps: number;
    earnedCredits: number;
    earnedMinutes: number;
    durationSeconds: number;
  } | null>(null);

  const handlePoseFrame = ({ nativeEvent }: { nativeEvent: PoseFrame }) => {
    if (!isSessionActive) {
      return;
    }

    if (!sessionStartedAt.current) {
      sessionStartedAt.current = Date.now();
    }

    const repCount = Math.max(0, nativeEvent.repCount ?? 0);
    setLatestRepCount(repCount);

    void collectCreditsFromPushupProgress({
      sourceSessionId: sessionId.current,
      repCount
    })
      .then((awarded) => {
        if (awarded > 0) {
          setSessionEarnedCredits((previous) => previous + awarded);
        }
      })
      .catch(() => {
        // Errors are exposed via global runtime state.
      });
  };

  const startNewSession = () => {
    sessionId.current = `session_${Date.now()}`;
    sessionStartedAt.current = Date.now();
    setIsSessionActive(true);
    setLatestRepCount(0);
    setSessionEarnedCredits(0);
    setCompletionSummary(null);
  };

  const finishSession = () => {
    const now = Date.now();
    const durationSeconds = sessionStartedAt.current ? Math.max(1, Math.floor((now - sessionStartedAt.current) / 1000)) : 0;

    setCompletionSummary({
      reps: latestRepCount,
      earnedCredits: sessionEarnedCredits,
      earnedMinutes: sessionEarnedCredits * challengeRewardPolicy.minutesPerCredit,
      durationSeconds
    });
    setIsSessionActive(false);
  };

  const availableMinutes = useMemo(
    () => state.dailyCredits.balance * challengeRewardPolicy.minutesPerCredit,
    [state.dailyCredits.balance]
  );

  return {
    state,
    isSessionActive,
    latestRepCount,
    sessionEarnedCredits,
    availableMinutes,
    completionSummary,
    handlePoseFrame,
    startNewSession,
    finishSession
  };
}
