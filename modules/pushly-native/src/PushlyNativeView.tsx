import { requireNativeView } from 'expo';
import * as React from 'react';

import type { PushlyCameraViewProps } from './PushlyNative.types';

const NativeView: React.ComponentType<PushlyCameraViewProps> =
  requireNativeView('PushlyNative');

export default function PushlyCameraView(props: PushlyCameraViewProps) {
  return <NativeView {...props} />;
}
