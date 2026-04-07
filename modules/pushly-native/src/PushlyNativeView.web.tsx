import * as React from 'react';
import { useEffect, useRef } from 'react';
import { Animated, Easing, StyleSheet, View } from 'react-native';

import type { PoseFrame, PushlyCameraViewProps } from './PushlyNative.types';
import { Text } from '@/components/ui/Text';
import { pushlyTheme } from '@/constants/theme';

export default function PushlyCameraView({
  isActive = true,
  onPoseFrame,
  repTarget = 3,
  style
}: PushlyCameraViewProps) {
  const repCount = useRef(0);
  const glow = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(glow, {
          toValue: 1,
          duration: 1200,
          easing: Easing.inOut(Easing.quad),
          useNativeDriver: true
        }),
        Animated.timing(glow, {
          toValue: 0,
          duration: 1200,
          easing: Easing.inOut(Easing.quad),
          useNativeDriver: true
        })
      ])
    );

    loop.start();
    return () => {
      loop.stop();
    };
  }, [glow]);

  useEffect(() => {
    if (!isActive || !onPoseFrame) {
      return;
    }

    const interval = setInterval(() => {
      repCount.current = Math.min(repTarget, repCount.current + 1);

      const payload: PoseFrame = {
        bodyDetected: true,
        confidence: 0.92,
        formEvidenceScore: 87,
        instruction: repCount.current >= repTarget ? 'Stark. Test geschafft.' : 'Web-Demo simuliert die Erkennung.',
        joints: [],
        repCount: repCount.current,
        state: repCount.current >= repTarget ? 'rep_counted' : 'ascending'
      };

      onPoseFrame({ nativeEvent: payload });
    }, 1200);

    return () => clearInterval(interval);
  }, [isActive, onPoseFrame, repTarget]);

  return (
    <View style={[styles.shell, style]}>
      <Animated.View
        style={[
          styles.glow,
          {
            opacity: glow.interpolate({
              inputRange: [0, 1],
              outputRange: [0.28, 0.82]
            }),
            transform: [
              {
                scale: glow.interpolate({
                  inputRange: [0, 1],
                  outputRange: [0.92, 1.08]
                })
              }
            ]
          }
        ]}
      />
      <View style={styles.figure}>
        <View style={styles.head} />
        <View style={styles.torso} />
        <View style={[styles.limb, styles.armLeft]} />
        <View style={[styles.limb, styles.armRight]} />
        <View style={[styles.limb, styles.legLeft]} />
        <View style={[styles.limb, styles.legRight]} />
      </View>
      <View style={styles.copy}>
        <Text variant="heading">Web-Demo aktiv</Text>
        <Text variant="caption" style={{ color: pushlyTheme.colors.textMuted }}>
          Auf iPhone rendert hier die echte Native-Kamera mit Live-Skelett und Reps.
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    alignItems: 'center',
    backgroundColor: '#060706',
    borderColor: 'rgba(255,255,255,0.12)',
    borderRadius: 28,
    borderWidth: 1,
    flex: 1,
    justifyContent: 'center',
    minHeight: 360,
    overflow: 'hidden',
    padding: 24
  },
  glow: {
    backgroundColor: '#BAFA20',
    borderRadius: 220,
    height: 240,
    position: 'absolute',
    width: 240
  },
  figure: {
    alignItems: 'center',
    height: 200,
    justifyContent: 'center',
    width: 220
  },
  head: {
    backgroundColor: '#D8F978',
    borderRadius: 18,
    height: 28,
    left: 82,
    position: 'absolute',
    top: 28,
    width: 28
  },
  torso: {
    backgroundColor: '#D8F978',
    borderRadius: 20,
    height: 28,
    position: 'absolute',
    top: 82,
    width: 140
  },
  limb: {
    backgroundColor: '#D8F978',
    borderRadius: 12,
    height: 14,
    position: 'absolute',
    width: 92
  },
  armLeft: {
    left: 8,
    top: 114,
    transform: [{ rotate: '16deg' }]
  },
  armRight: {
    right: 8,
    top: 114,
    transform: [{ rotate: '-16deg' }]
  },
  legLeft: {
    left: 32,
    top: 156,
    transform: [{ rotate: '-10deg' }]
  },
  legRight: {
    right: 32,
    top: 156,
    transform: [{ rotate: '10deg' }]
  },
  copy: {
    alignItems: 'center',
    gap: 6
  }
});
