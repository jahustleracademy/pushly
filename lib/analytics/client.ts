import { env } from '@/lib/config/env';

type AnalyticsProps = Record<string, string | number | boolean | null | undefined>;

export function track(event: string, props?: AnalyticsProps) {
  if (!env.analyticsEnabled) {
    return;
  }

  // TODO: Plug PostHog, Segment, or Firebase in one place only.
  console.log('[Pushly][Analytics]', event, props ?? {});
}
