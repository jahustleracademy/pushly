import { describe, expect, it } from 'vitest';
import type { CreditsSnapshot } from '@/features/credits/domain/models';
import { __storageTestUtils } from '@/features/credits/infrastructure/storage';

function snapshot(overrides?: Partial<CreditsSnapshot>): CreditsSnapshot {
  return {
    dailyCredits: {
      dateKey: '2026-04-10',
      balance: 10,
      earned: 20,
      spent: 10,
      updatedAt: '2026-04-10T10:00:00.000Z'
    },
    ledger: {
      entries: []
    },
    activeUnlockWindow: null,
    lastRedeemRequest: null,
    updatedAt: '2026-04-10T10:00:00.000Z',
    ...overrides
  };
}

describe('credits storage winner logic', () => {
  it('prefers the newer snapshot by updatedAt', () => {
    const older = snapshot({ updatedAt: '2026-04-10T09:00:00.000Z' });
    const newer = snapshot({ updatedAt: '2026-04-10T10:00:00.000Z' });

    expect(__storageTestUtils.pickMostRecentSnapshot(older, newer)).toEqual(newer);
  });

  it('resolves ties by ledger size', () => {
    const baseTime = '2026-04-10T10:00:00.000Z';
    const a = snapshot({ updatedAt: baseTime, ledger: { entries: [{ id: '1', occurredAt: baseTime, dateKey: '2026-04-10', type: 'earn', creditsDelta: 2, reason: 'x' }] } });
    const b = snapshot({ updatedAt: baseTime, ledger: { entries: [] } });

    expect(__storageTestUtils.pickMostRecentSnapshot(b, a)).toEqual(a);
  });

  it('reconstructs snapshot fields including lastRedeemRequest', () => {
    const raw = JSON.stringify(snapshot({
      lastRedeemRequest: {
        id: 'r1',
        requestedAt: '2026-04-10T10:00:00.000Z',
        source: 'shield',
        requestedMinutes: 15,
        requiredCredits: 15
      }
    }));

    const parsed = __storageTestUtils.parseSnapshotCandidate(raw, '2026-04-10', '2026-04-10T10:00:00.000Z');
    expect(parsed?.lastRedeemRequest?.source).toBe('shield');
    expect(parsed?.dailyCredits.balance).toBe(10);
  });
});
