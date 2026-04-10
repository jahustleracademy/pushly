import { describe, expect, it } from 'vitest';
import { challengeRewardPolicy } from '@/features/credits/domain/policies';

describe('challengeRewardPolicy', () => {
  it('converts push-ups to credits with v1 ratio', () => {
    expect(challengeRewardPolicy.creditsForPushups(1)).toBe(2);
    expect(challengeRewardPolicy.creditsForPushups(30)).toBe(60);
  });

  it('converts requested minutes to credits with v1 ratio', () => {
    expect(challengeRewardPolicy.creditsForMinutes(1)).toBe(1);
    expect(challengeRewardPolicy.creditsForMinutes(60)).toBe(60);
  });

  it('awards only the positive rep delta', () => {
    expect(challengeRewardPolicy.creditsForRepDelta(3, 7)).toBe(8);
    expect(challengeRewardPolicy.creditsForRepDelta(7, 3)).toBe(0);
  });
});
