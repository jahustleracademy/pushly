import { useEffect } from 'react';
import { AppState } from 'react-native';
import * as Linking from 'expo-linking';
import { useRouter } from 'expo-router';
import { creditsRuntimeStore } from '@/features/credits/application/creditsRuntime';
import { markIntentHandled, parsePendingRuntimeIntent, parseRuntimeIntentFromUrl, type RuntimeIntent } from '@/features/credits/application/shieldIntentReconcile';
import { PushlyNative } from '@/lib/native/pushly-native';

const handledIntentKeys = new Set<string>();

export function AppRuntimeProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();

  useEffect(() => {
    void creditsRuntimeStore.bootstrap();

    const resolvePendingShieldIntent = async () => {
      const raw = await PushlyNative.consumePendingShieldRedeemIntent().catch(() => null);
      if (!raw) {
        return;
      }

      const intent = parsePendingRuntimeIntent(raw);
      if (!intent || !markIntentHandled(intent, handledIntentKeys)) {
        return;
      }

      await handleIntent(intent, router);
    };

    const reconcileAndResolve = () => {
      void creditsRuntimeStore.reconcileRuntime();
      void resolvePendingShieldIntent();
    };

    const heartbeat = setInterval(() => {
      if (AppState.currentState === 'active') {
        reconcileAndResolve();
      }
    }, 30_000);

    const appStateSub = AppState.addEventListener('change', (nextState) => {
      if (nextState === 'active') {
        reconcileAndResolve();
      }
    });

    const linkSub = Linking.addEventListener('url', ({ url }) => {
      const intent = parseRuntimeIntentFromUrl(url);
      if (!intent) {
        return;
      }

      if (!markIntentHandled(intent, handledIntentKeys)) {
        return;
      }

      void handleIntent(intent, router);
    });

    void Linking.getInitialURL().then((url) => {
      if (!url) {
        reconcileAndResolve();
        return;
      }

      const intent = parseRuntimeIntentFromUrl(url);
      if (!intent) {
        reconcileAndResolve();
        return;
      }

      if (!markIntentHandled(intent, handledIntentKeys)) {
        return;
      }

      void handleIntent(intent, router);
    });

    return () => {
      clearInterval(heartbeat);
      appStateSub.remove();
      linkSub.remove();
    };
  }, [router]);

  return <>{children}</>;
}

async function handleIntent(intent: RuntimeIntent, router: ReturnType<typeof useRouter>) {
  if (intent.type === 'instant_redeem') {
    try {
      await creditsRuntimeStore.redeemMinutes(intent.minutes, 'shield');
    } catch {
      // UI layer consumes current error state via runtime store.
    }
    return;
  }

  router.push({
    pathname: '/redeem',
    params: {
      source: intent.source,
      minutes: `${Math.max(1, intent.suggestedMinutes || 15)}`
    }
  });
}
