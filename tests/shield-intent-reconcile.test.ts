import { describe, expect, it } from 'vitest';
import { markIntentHandled, parsePendingRuntimeIntent, parseRuntimeIntentFromUrl } from '@/features/credits/application/shieldIntentReconcile';

describe('shield intent reconcile', () => {
  it('parses route intent from pending payload', () => {
    const raw = JSON.stringify({
      type: 'route_redeem',
      source: 'shield',
      suggestedMinutes: 25,
      createdAt: '2026-04-10T10:00:00.000Z'
    });

    const parsed = parsePendingRuntimeIntent(raw);
    expect(parsed?.type).toBe('route_redeem');
    expect(parsed?.source).toBe('shield');
    if (parsed?.type === 'route_redeem') {
      expect(parsed.suggestedMinutes).toBe(25);
    }
  });

  it('deduplicates identical intents to prevent duplicate redeem/routing', () => {
    const handled = new Set<string>();
    const intent = parsePendingRuntimeIntent(JSON.stringify({
      type: 'instant_redeem',
      source: 'shield',
      minutes: 15,
      createdAt: '2026-04-10T10:00:00.000Z'
    }));

    expect(intent).not.toBeNull();
    expect(markIntentHandled(intent!, handled)).toBe(true);
    expect(markIntentHandled(intent!, handled)).toBe(false);
  });

  it('parses deep-link contract for shield redeem route', () => {
    const parsed = parseRuntimeIntentFromUrl('pushly://redeem?source=shield&minutes=30');
    expect(parsed?.type).toBe('route_redeem');
    if (parsed?.type === 'route_redeem') {
      expect(parsed.suggestedMinutes).toBe(30);
    }
  });
});
