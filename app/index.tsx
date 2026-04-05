import { useEffect, useState } from 'react';
import { ActivityIndicator, Image, StyleSheet, View } from 'react-native';
import { Redirect } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';
import { Text } from '@/components/ui/Text';
import { useTheme } from '@/components/shared/ThemeProvider';
import { getOnboardingCompleted } from '@/features/onboarding/storage';
import { routes } from '@/constants/routes';

export default function Index() {
  const { theme } = useTheme();
  const [target, setTarget] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    getOnboardingCompleted()
      .then((completed) => {
        if (!mounted) {
          return;
        }

        setTarget(completed ? routes.home : routes.onboarding);
      })
      .catch(() => {
        if (mounted) {
          setTarget(routes.onboarding);
        }
      });

    return () => {
      mounted = false;
    };
  }, []);

  if (!target) {
    return (
      <LinearGradient
        colors={[theme.colors.backgroundDeep, theme.colors.background, '#101406']}
        style={styles.loadingScreen}
      >
        <View style={styles.loadingStack}>
          <Image source={require('../assets/images/logo_header.png')} style={styles.logo} resizeMode="contain" />
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Pushly startet deinen Schutzmodus ...
          </Text>
          <ActivityIndicator color={theme.colors.accent} size="small" />
        </View>
      </LinearGradient>
    );
  }

  return <Redirect href={target as never} />;
}

const styles = StyleSheet.create({
  loadingScreen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center'
  },
  loadingStack: {
    alignItems: 'center',
    gap: 18
  },
  logo: {
    width: 180,
    height: 56
  }
});
