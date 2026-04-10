import { useCallback, useEffect, useState } from 'react';
import { protectionStatusService, type ProtectionStatusSnapshot } from '@/features/credits/integration/protectionStatusService';

export function useProtectionStatus() {
  const [state, setState] = useState<{
    loading: boolean;
    snapshot: ProtectionStatusSnapshot | null;
    error: string | null;
  }>({
    loading: true,
    snapshot: null,
    error: null
  });

  const refresh = useCallback(async () => {
    setState((previous) => ({
      ...previous,
      loading: true,
      error: null
    }));

    try {
      const snapshot = await protectionStatusService.loadSnapshot();
      setState({ loading: false, snapshot, error: null });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Status konnte nicht geladen werden';
      setState({ loading: false, snapshot: null, error: message });
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return {
    ...state,
    refresh
  };
}
