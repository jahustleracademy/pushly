import type { RedeemSource } from '@/features/credits/domain/models';

export type ShieldRouteIntent = {
  type: 'route_redeem';
  suggestedMinutes: number;
  source: RedeemSource;
  createdAt?: string;
};

export type ShieldInstantRedeemIntent = {
  type: 'instant_redeem';
  minutes: number;
  source: RedeemSource;
  createdAt?: string;
};

export type RuntimeIntent = ShieldRouteIntent | ShieldInstantRedeemIntent;

export function parseRuntimeIntentFromUrl(url: string): RuntimeIntent | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }

  const path = `${parsed.hostname}${parsed.pathname || ''}`;
  if (!path.includes('redeem')) {
    return null;
  }

  const source = parsed.searchParams.get('source') === 'shield' ? 'shield' : 'app';
  const mode = parsed.searchParams.get('mode');
  const minutes = parseMinutes(parsed.searchParams.get('minutes'));
  const createdAt = parsed.searchParams.get('createdAt') ?? undefined;

  if (mode === 'instant') {
    if (minutes <= 0) {
      return null;
    }

    return {
      type: 'instant_redeem',
      source,
      minutes,
      createdAt
    };
  }

  return {
    type: 'route_redeem',
    source,
    suggestedMinutes: Math.max(1, minutes || 15),
    createdAt
  };
}

export function parsePendingRuntimeIntent(raw: string): RuntimeIntent | null {
  try {
    const parsed = JSON.parse(raw) as Partial<RuntimeIntent>;
    if (parsed.type === 'instant_redeem') {
      const minutes = parseMinutes(parsed.minutes);
      if (minutes <= 0) {
        return null;
      }

      return {
        type: 'instant_redeem',
        source: parsed.source === 'shield' ? 'shield' : 'app',
        minutes,
        createdAt: typeof parsed.createdAt === 'string' ? parsed.createdAt : undefined
      };
    }

    if (parsed.type === 'route_redeem') {
      return {
        type: 'route_redeem',
        source: parsed.source === 'shield' ? 'shield' : 'app',
        suggestedMinutes: Math.max(1, parseMinutes(parsed.suggestedMinutes) || 15),
        createdAt: typeof parsed.createdAt === 'string' ? parsed.createdAt : undefined
      };
    }

    return null;
  } catch {
    return null;
  }
}

export function markIntentHandled(intent: RuntimeIntent, handled: Set<string>) {
  const key = intentKey(intent);
  if (handled.has(key)) {
    return false;
  }

  handled.add(key);
  if (handled.size > 100) {
    const first = handled.values().next().value as string | undefined;
    if (first) {
      handled.delete(first);
    }
  }

  return true;
}

function parseMinutes(value: unknown): number {
  const parsed = typeof value === 'string' ? Number(value) : Number(value ?? 0);
  if (!Number.isFinite(parsed)) {
    return 0;
  }

  return Math.max(0, Math.floor(parsed));
}

function intentKey(intent: RuntimeIntent) {
  if (intent.type === 'instant_redeem') {
    return `${intent.type}:${intent.source}:${intent.minutes}:${intent.createdAt ?? ''}`;
  }

  return `${intent.type}:${intent.source}:${intent.suggestedMinutes}:${intent.createdAt ?? ''}`;
}
