import * as React from 'react';
import { StyleSheet, View } from 'react-native';

import type { PushlyCameraViewProps } from './PushlyNative.types';

export default function PushlyCameraView({ style }: PushlyCameraViewProps) {
  return <View style={[styles.fallback, style]} />;
}

const styles = StyleSheet.create({
  fallback: {
    minHeight: 240
  }
});
