import { useSyncExternalStore } from 'react';
import { creditsRuntimeStore } from './creditsRuntime';

export function useCreditsRuntime() {
  const state = useSyncExternalStore(creditsRuntimeStore.subscribe, creditsRuntimeStore.getState, creditsRuntimeStore.getState);

  return {
    state,
    bootstrap: creditsRuntimeStore.bootstrap,
    reconcileRuntime: creditsRuntimeStore.reconcileRuntime,
    collectCreditsFromPushupProgress: creditsRuntimeStore.collectCreditsFromPushupProgress,
    redeemMinutes: creditsRuntimeStore.redeemMinutes
  };
}
