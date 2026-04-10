import { useEffect, useMemo, useState } from 'react';
import { useCreditsRuntime } from './useCreditsRuntime';
import { formatRemainingUnlock, getAvailableMinutes, getRemainingUnlockMs, getTodayPushups, getTodayRedeemedMinutes } from './selectors';

export function useCreditsDashboard() {
  const { state, bootstrap, reconcileRuntime, redeemMinutes } = useCreditsRuntime();
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    void bootstrap();
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [bootstrap]);

  const remainingUnlockMs = useMemo(() => getRemainingUnlockMs(state, now), [state, now]);

  return {
    state,
    availableMinutes: getAvailableMinutes(state),
    todayPushups: getTodayPushups(state),
    todayRedeemedMinutes: getTodayRedeemedMinutes(state),
    remainingUnlockMs,
    remainingUnlockLabel: formatRemainingUnlock(remainingUnlockMs),
    redeemMinutes,
    reconcileRuntime
  };
}
