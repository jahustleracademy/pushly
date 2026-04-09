import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Animated,
  Easing,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  TextInput,
  View
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import * as Haptics from 'expo-haptics';
import Slider from '@react-native-community/slider';
import { FontAwesome6, Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useTheme } from '@/components/shared/ThemeProvider';
import { Text } from '@/components/ui/Text';
import { routes } from '@/constants/routes';
import {
  ATTEMPT_OPTIONS,
  DISTRACTING_APP_OPTIONS,
  FEELING_OPTIONS,
  getAppOption,
  getAverageComparison,
  getDiagnosisScore,
  getMonthlyHoursLost,
  getRecommendedPushUps,
  ONBOARDING_STEP_ORDER,
  PAYWALL_PLAN_OPTIONS,
  AUTH_METHOD_OPTIONS,
  PUSHLY_TRIAL_REP_TARGET,
  SETUP_PREVIEW_STEPS,
  TRUST_BULLETS
} from '@/features/onboarding/data';
import { useOnboardingFlow } from '@/features/onboarding/useOnboardingFlow';
import type { AppSelectionOption, SelectionOption } from '@/features/onboarding/types';
import {
  PushlyCameraView,
  PushlyNative,
  type PoseFrame,
  type ScreenTimeAuthorizationStatus
} from '@/lib/native/pushly-native';

const toneByStep: Partial<Record<(typeof ONBOARDING_STEP_ORDER)[number], 'accent' | 'danger'>> = {
  diagnosis: 'danger'
};

const ctaLabelByStep: Record<(typeof ONBOARDING_STEP_ORDER)[number], string> = {
  hero: 'Start',
  quizIntro: 'Weiter',
  name: 'Weiter',
  distractingApps: 'Weiter',
  scrollMinutes: 'Weiter',
  feelings: 'Weiter',
  attempts: 'Weiter',
  diagnosis: 'Weiter',
  reframe: 'Weiter',
  mechanic: 'Weiter',
  protectApps: 'Weiter',
  trust: 'Weiter',
  paywall: 'Weiter',
  screenTimePermission: 'Weiter',
  cameraCalibration: 'Kamera testen',
  pushUpTrial: 'Weiter',
  rating: 'Weiter',
  auth: 'Weiter',
  setupPreview: 'Schutz starten'
};

const stepLabelById: Record<(typeof ONBOARDING_STEP_ORDER)[number], string> = {
  hero: 'Start',
  quizIntro: 'Analyse',
  name: 'Profil',
  distractingApps: 'Trigger',
  scrollMinutes: 'Zeit',
  feelings: 'Gefühl',
  attempts: 'Versuche',
  diagnosis: 'Diagnose',
  reframe: 'Reframe',
  mechanic: 'Mechanik',
  protectApps: 'Schutz',
  trust: 'Vertrauen',
  paywall: 'Zugang',
  screenTimePermission: 'Berechtigung',
  cameraCalibration: 'Kamera',
  pushUpTrial: 'Trial',
  rating: 'Beweise',
  auth: 'Login',
  setupPreview: 'Fertig'
};

export function OnboardingFlow() {
  const router = useRouter();
  const { theme } = useTheme();
  const insets = useSafeAreaInsets();
  const flow = useOnboardingFlow();
  const [isCompleting, setIsCompleting] = useState(false);
  const [isNativeBusy, setIsNativeBusy] = useState(false);
  const [nativeMessage, setNativeMessage] = useState<string | null>(null);
  const [poseEngineReady, setPoseEngineReady] = useState(Platform.OS !== 'ios');
  const [latestPoseFrame, setLatestPoseFrame] = useState<PoseFrame | null>(null);
  const scrollRef = useRef<ScrollView | null>(null);
  const transition = useRef(new Animated.Value(1)).current;
  const backdropPulse = useRef(new Animated.Value(0)).current;
  const lastHapticAt = useRef(0);
  const previousTrialPassed = useRef(false);
  const nativeBootstrapDone = useRef(false);
  const styles = createStyles(theme);
  const tone = toneByStep[flow.currentStepId] ?? 'accent';

  useEffect(() => {
    const pulseLoop = Animated.loop(
      Animated.sequence([
        Animated.timing(backdropPulse, {
          toValue: 1,
          duration: 3400,
          easing: Easing.inOut(Easing.quad),
          useNativeDriver: true
        }),
        Animated.timing(backdropPulse, {
          toValue: 0,
          duration: 3400,
          easing: Easing.inOut(Easing.quad),
          useNativeDriver: true
        })
      ])
    );

    pulseLoop.start();

    return () => {
      pulseLoop.stop();
    };
  }, [backdropPulse]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ y: 0, animated: false });
    transition.setValue(0);

    Animated.timing(transition, {
      toValue: 1,
      duration: 360,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true
    }).start();
  }, [flow.currentStepId, transition]);

  const triggerHaptic = (
    kind: 'selection' | 'light' | 'medium' | 'success' = 'selection'
  ) => {
    const now = Date.now();
    if (now - lastHapticAt.current < 70) {
      return;
    }
    lastHapticAt.current = now;
    if (kind === 'selection') {
      void Haptics.selectionAsync().catch(() => {});
      return;
    }
    if (kind === 'success') {
      void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      return;
    }
    void Haptics.impactAsync(
      kind === 'light' ? Haptics.ImpactFeedbackStyle.Light : Haptics.ImpactFeedbackStyle.Medium
    ).catch(() => {});
  };

  useEffect(() => {
    if (flow.currentStepId !== 'pushUpTrial') {
      previousTrialPassed.current = false;
      return;
    }

    if (!previousTrialPassed.current && flow.answers.pushUpTestPassed) {
      triggerHaptic('success');
    }
    previousTrialPassed.current = flow.answers.pushUpTestPassed;
  }, [flow.answers.pushUpTestPassed, flow.currentStepId]);

  useEffect(() => {
    if (!flow.hydrated) {
      return;
    }

    if (nativeBootstrapDone.current) {
      return;
    }

    nativeBootstrapDone.current = true;

    let mounted = true;

    Promise.all([
      PushlyNative.getScreenTimeAuthorizationStatus(),
      PushlyNative.getStoredSelectionSummary(),
      PushlyNative.isPoseEngineAvailable()
    ])
      .then(async ([status, selection, poseReady]) => {
        if (!mounted) {
          return;
        }

        flow.setScreenTimeStatus(status);
        flow.setScreenTimeSelection(selection);
        if (selection.hasSelection) {
          flow.setShieldStatus('active');
        }
        setPoseEngineReady(poseReady);
        if (selection.hasSelection && status === 'approved') {
          await PushlyNative.startDeviceActivityMonitoring();
        }
      })
      .catch(() => {
        if (mounted) {
          setNativeMessage('Die native Basis wird geladen. Falls etwas blockiert, laeuft der Funnel trotzdem weiter.');
        }
      });

    return () => {
      mounted = false;
    };
  }, [flow]);

  if (!flow.hydrated) {
    return (
      <LinearGradient
        colors={[theme.colors.backgroundDeep, theme.colors.background, '#0E1305']}
        style={styles.root}
      >
        <SafeAreaView style={styles.centered}>
          <Image source={require('../../assets/images/logo_header.png')} style={styles.logo} resizeMode="contain" />
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Pushly bereitet dein Schutz-Onboarding vor ...
          </Text>
        </SafeAreaView>
      </LinearGradient>
    );
  }

  const diagnosisScore = getDiagnosisScore(flow.answers);
  const averageScore = getAverageComparison();
  const recommendedPushUps = getRecommendedPushUps(flow.answers);
  const monthlyHoursLost = getMonthlyHoursLost(flow.answers);
  const leadApp = getAppOption(flow.answers.protectedApps[0] ?? flow.answers.distractingApps[0] ?? 'instagram');
  const handlePrimaryAction = async () => {
    if (!flow.canContinue || isCompleting) {
      return;
    }

    if (flow.currentStepId === 'setupPreview') {
      triggerHaptic('success');
      setIsCompleting(true);
      await flow.complete();
      router.replace(routes.home as never);
      return;
    }

    triggerHaptic('light');
    flow.goNext();
  };

  const handleBackAction = () => {
    if (flow.isFirstStep) {
      return;
    }
    triggerHaptic('light');
    flow.goBack();
  };

  const withSelectionHaptic = <T extends string>(callback: (id: T) => void) => {
    return (id: T) => {
      triggerHaptic('selection');
      callback(id);
    };
  };

  const handleRequestScreenTime = async () => {
    setIsNativeBusy(true);
    setNativeMessage(null);

    try {
      const status = await PushlyNative.requestScreenTimeAuthorization();
      flow.setScreenTimeStatus(status);

      if (status !== 'approved') {
        setNativeMessage('Pushly braucht Family Controls, damit echte App-Sperren funktionieren.');
      }
    } catch {
      setNativeMessage('Die Screen-Time-Berechtigung konnte gerade nicht angefragt werden.');
    } finally {
      setIsNativeBusy(false);
    }
  };

  const handleChooseProtectedApps = async () => {
    setIsNativeBusy(true);
    setNativeMessage(null);

    try {
      const summary = await PushlyNative.presentFamilyActivityPicker();
      flow.setScreenTimeSelection(summary);

      if (summary.hasSelection) {
        const shieldStatus = await PushlyNative.applyStoredShield();
        flow.setShieldStatus(shieldStatus);
        await PushlyNative.startDeviceActivityMonitoring();
      } else {
        await PushlyNative.stopDeviceActivityMonitoring();
      }
    } catch {
      setNativeMessage('Die native App-Auswahl konnte nicht geoeffnet werden.');
    } finally {
      setIsNativeBusy(false);
    }
  };

  const handlePoseFrame = ({ nativeEvent }: { nativeEvent: PoseFrame }) => {
    setLatestPoseFrame(nativeEvent);
    flow.setPoseFrame(nativeEvent);
  };
  const isCameraFirstStep = flow.currentStepId === 'pushUpTrial';

  return (
    <LinearGradient
      colors={[theme.colors.backgroundDeep, theme.colors.background, '#0D1007']}
      style={styles.root}
    >
      <AmbientBackdrop pulse={backdropPulse} tone={tone} theme={theme} />
      <SafeAreaView style={styles.safeArea}>
        {flow.stepIndex >= 1 ? (
          <FlowHeader
            progress={flow.progress}
            onBack={handleBackAction}
            tone={tone}
            showProgress={flow.stepIndex >= 2}
            canGoBack={!flow.isFirstStep}
            stepLabel={stepLabelById[flow.currentStepId]}
            stepIndex={flow.stepIndex}
            stepCount={flow.stepCount}
          />
        ) : null}

        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.flex}>
          <ScrollView
            ref={scrollRef}
            style={styles.flex}
            contentContainerStyle={[styles.contentContainer, isCameraFirstStep && styles.contentContainerCameraFocus]}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <Animated.View
              style={[
                styles.stepContainer,
                isCameraFirstStep && styles.stepContainerCameraFocus,
                {
                  opacity: transition,
                  transform: [
                    {
                      translateY: transition.interpolate({
                        inputRange: [0, 1],
                        outputRange: [18, 0]
                      })
                    },
                    {
                      scale: transition.interpolate({
                        inputRange: [0, 1],
                        outputRange: [0.985, 1]
                      })
                    }
                  ]
                }
              ]}
            >
              {flow.currentStepId === 'hero' ? (
                <HeroStep
                  styles={styles}
                  theme={theme}
                  leadApp={leadApp}
                  recommendedPushUps={recommendedPushUps}
                />
              ) : null}

              {flow.currentStepId === 'quizIntro' ? <QuizIntroStep styles={styles} theme={theme} /> : null}

              {flow.currentStepId === 'name' ? (
                <NameStep
                  styles={styles}
                  theme={theme}
                  value={flow.answers.name}
                  onChangeText={flow.updateName}
                />
              ) : null}

              {flow.currentStepId === 'distractingApps' ? (
                <AppSelectionStep
                  styles={styles}
                  theme={theme}
                  title="Welche Apps ziehen dich rein?"
                  subtitle="Wähle bis zu 3 Trigger."
                  helper=""
                  options={DISTRACTING_APP_OPTIONS}
                  selectedIds={flow.answers.distractingApps}
                  onToggle={withSelectionHaptic(flow.toggleDistractingApp)}
                />
              ) : null}

              {flow.currentStepId === 'scrollMinutes' ? (
                <ScrollMinutesStep
                  styles={styles}
                  theme={theme}
                  value={flow.answers.dailyScrollMinutes}
                  onChange={flow.updateScrollMinutes}
                />
              ) : null}

              {flow.currentStepId === 'feelings' ? (
                <ListSelectionStep
                  styles={styles}
                  theme={theme}
                  title={flow.answers.name ? `Wie fühlst du dich danach, ${flow.answers.name}?` : 'Wie fühlst du dich danach?'}
                  subtitle="Wähle bis zu 2."
                  options={FEELING_OPTIONS}
                  selectedIds={flow.answers.feelings}
                  onToggle={withSelectionHaptic(flow.toggleFeeling)}
                />
              ) : null}

              {flow.currentStepId === 'attempts' ? (
                <ListSelectionStep
                  styles={styles}
                  theme={theme}
                  title="Was hast du schon versucht?"
                  subtitle="Wähle alles, was nicht hielt."
                  options={ATTEMPT_OPTIONS}
                  selectedIds={flow.answers.attempts}
                  onToggle={withSelectionHaptic(flow.toggleAttempt)}
                />
              ) : null}

              {flow.currentStepId === 'diagnosis' ? (
                <DiagnosisStep
                  styles={styles}
                  theme={theme}
                  name={flow.answers.name || 'Du'}
                  score={diagnosisScore}
                  average={averageScore}
                />
              ) : null}

              {flow.currentStepId === 'reframe' ? (
                <ReframeStep
                  styles={styles}
                  theme={theme}
                  minutes={flow.answers.dailyScrollMinutes}
                  pushUps={recommendedPushUps}
                  monthlyHoursLost={monthlyHoursLost}
                />
              ) : null}

              {flow.currentStepId === 'mechanic' ? (
                <MechanicStep
                  styles={styles}
                  theme={theme}
                  app={leadApp}
                  pushUps={recommendedPushUps}
                />
              ) : null}

              {flow.currentStepId === 'protectApps' ? (
                <AppSelectionStep
                  styles={styles}
                  theme={theme}
                  title="Welche Apps sperren wir zuerst?"
                  subtitle="Zugriff nur nach Reps."
                  helper=""
                  options={DISTRACTING_APP_OPTIONS}
                  selectedIds={flow.answers.protectedApps}
                  onToggle={withSelectionHaptic(flow.toggleProtectedApp)}
                />
              ) : null}

              {flow.currentStepId === 'trust' ? (
                <TrustStep styles={styles} theme={theme} />
              ) : null}

              {flow.currentStepId === 'paywall' ? (
                <PaywallStep
                  styles={styles}
                  theme={theme}
                  selectedPlanId={flow.answers.planId}
                  onSelectPlan={withSelectionHaptic(flow.selectPlan)}
                />
              ) : null}

              {flow.currentStepId === 'screenTimePermission' ? (
                <ScreenTimePermissionStep
                  styles={styles}
                  theme={theme}
                  status={flow.answers.screenTimeStatus}
                  selectionCount={
                    flow.answers.screenTimeSelection.appCount +
                    flow.answers.screenTimeSelection.categoryCount +
                    flow.answers.screenTimeSelection.webDomainCount
                  }
                  shieldStatus={flow.answers.shieldStatus}
                  isBusy={isNativeBusy}
                  message={nativeMessage}
                  onAuthorize={handleRequestScreenTime}
                  onChooseApps={handleChooseProtectedApps}
                />
              ) : null}

              {flow.currentStepId === 'cameraCalibration' ? (
                <CameraCalibrationStep styles={styles} theme={theme} poseEngineReady={poseEngineReady} />
              ) : null}

              {flow.currentStepId === 'pushUpTrial' ? (
                <PushUpTrialStep
                  styles={styles}
                  theme={theme}
                  leadApp={leadApp}
                  answers={flow.answers}
                  frame={latestPoseFrame}
                  onPoseFrame={handlePoseFrame}
                />
              ) : null}

              {flow.currentStepId === 'rating' ? (
                <RatingStep styles={styles} theme={theme} answers={flow.answers} />
              ) : null}

              {flow.currentStepId === 'auth' ? (
                <AuthStep
                  styles={styles}
                  theme={theme}
                  selectedMethod={flow.answers.authMethod}
                  onSelectMethod={withSelectionHaptic(flow.selectAuthMethod)}
                />
              ) : null}

              {flow.currentStepId === 'setupPreview' ? (
                <SetupPreviewStep styles={styles} theme={theme} app={leadApp} answers={flow.answers} />
              ) : null}
            </Animated.View>
          </ScrollView>

          <View style={[styles.footer, { paddingBottom: Math.max(18, insets.bottom + 10) }]}>
            {flow.currentStepId === 'paywall' ? (
              <View style={styles.legalRow}>
                {['Restore', 'Privacy', 'Terms'].map((item) => (
                  <Text key={item} variant="caption" style={{ color: theme.colors.textMuted }}>
                    {item}
                  </Text>
                ))}
              </View>
            ) : null}

            <GradientCta
              label={isCompleting ? 'Wird aktiviert ...' : ctaLabelByStep[flow.currentStepId]}
              onPress={handlePrimaryAction}
              disabled={!flow.canContinue || isCompleting}
              tone={tone}
              styles={styles}
              theme={theme}
            />
          </View>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </LinearGradient>
  );
}

function HeroStep({
  styles,
  theme,
  leadApp,
  recommendedPushUps
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  leadApp: AppSelectionOption;
  recommendedPushUps: number;
}) {
  return (
    <View style={styles.heroStep}>
      <Image source={require('../../assets/images/logo_header.png')} style={styles.heroLogo} resizeMode="contain" />

      <View style={styles.titleBlock}>
        <Text variant="title">Stoppe den Scroll-Reflex.</Text>
        <Text variant="body" style={{ color: theme.colors.textMuted, marginTop: 12 }}>
          Erst Reps. Dann Zugriff.
        </Text>
      </View>

      <View style={styles.heroVisual}>
        <FloatingBrand option={getAppOption('instagram')} styles={styles} position="leftTop" />
        <FloatingBrand option={getAppOption('tiktok')} styles={styles} position="rightTop" />
        <FloatingBrand option={getAppOption('youtube')} styles={styles} position="leftBottom" />
        <FloatingBrand option={getAppOption('x')} styles={styles} position="rightBottom" />

      <PhoneShell styles={styles} theme={theme}>
        <LinearGradient
          colors={['rgba(186,250,32,0.28)', 'rgba(0,0,0,0.1)', 'rgba(0,0,0,0.9)']}
          style={styles.phoneGlow}
        />
        <Image
          source={require('../../assets/mockups/protection-stack.png')}
          style={styles.heroMockupAsset}
          resizeMode="contain"
        />
        <View style={styles.lockPreviewTopRow}>
            <BrandBubble option={leadApp} size="large" theme={theme} />
            <View style={styles.lockPreviewStatus}>
              <Text variant="heading">Sperre bis Bewegung</Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                {leadApp.label} bleibt gesperrt.
              </Text>
            </View>
          </View>

          <BlurView intensity={30} tint="dark" style={styles.counterGlass}>
            <Ionicons name="barbell-outline" size={20} color={theme.colors.accent} />
            <View style={styles.counterCopy}>
              <Text variant="heading">{recommendedPushUps} Reps bis Zugriff</Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                Klare Sperre. Klare Regel.
              </Text>
            </View>
          </BlurView>

          <View style={styles.mockFeedRow}>
            <MockFeedCard label="Streak" value="04 Tage" accent />
            <MockFeedCard label="Fokus" value="+38 Min" />
          </View>
        </PhoneShell>
      </View>
    </View>
  );
}

function QuizIntroStep({
  styles,
  theme
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        PERSONALISIERTE ANALYSE
      </Text>
      <Text variant="title">6 Fragen bis zum Schutz.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Kurz durchziehen. Dann ist es aktiv.
      </Text>

      <View style={styles.quizVisual}>
        <View style={styles.quizOrbit} />
        <View style={styles.quizCore}>
          <Ionicons name="shield-checkmark-outline" size={36} color={theme.colors.accent} />
        </View>
        <View style={[styles.quizSatellite, styles.quizSatelliteLeft]}>
          <BrandBubble option={getAppOption('instagram')} size="small" theme={theme} />
        </View>
        <View style={[styles.quizSatellite, styles.quizSatelliteRight]}>
          <BrandBubble option={getAppOption('tiktok')} size="small" theme={theme} />
        </View>
        <View style={[styles.quizSatellite, styles.quizSatelliteBottom]}>
          <Ionicons name="barbell-outline" size={22} color={theme.colors.accent} />
        </View>
      </View>

    </View>
  );
}

function NameStep({
  styles,
  theme,
  value,
  onChangeText
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  value: string;
  onChangeText: (value: string) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        SCHRITT 1
      </Text>
      <Text variant="title">Wie sollen wir dich nennen?</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Dein Name macht es verbindlich.
      </Text>

      <BlurView intensity={20} tint="dark" style={styles.inputShell}>
        <Ionicons name="person-outline" size={20} color={theme.colors.accent} />
        <TextInput
          value={value}
          onChangeText={onChangeText}
          placeholder="Dein Name"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          autoFocus
          autoCapitalize="words"
          returnKeyType="done"
        />
      </BlurView>

    </View>
  );
}

function AppSelectionStep({
  styles,
  theme,
  title,
  subtitle,
  helper,
  options,
  selectedIds,
  onToggle
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  title: string;
  subtitle: string;
  helper?: string;
  options: AppSelectionOption[];
  selectedIds: string[];
  onToggle: (id: any) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        TRIGGER-AUSWAHL
      </Text>
      <Text variant="title">{title}</Text>
      <Text variant="body" style={styles.subtleCopy}>
        {subtitle}
      </Text>

      <View style={styles.selectionHintRow}>
        <Text variant="caption" style={{ color: theme.colors.textMuted }}>
          {selectedIds.length}/3 gewählt
        </Text>
      </View>

      <View style={styles.appGrid}>
        {options.map((option) => (
          <Pressable
            key={option.id}
            onPress={() => onToggle(option.id)}
            style={({ pressed }) => [
              styles.appCard,
              pressed && styles.touchPressed,
              selectedIds.includes(option.id) && {
                borderColor: theme.colors.accent,
                backgroundColor: 'rgba(186,250,32,0.14)'
              }
            ]}
          >
            <BrandBubble option={option} size="medium" theme={theme} />
            <Text variant="caption" style={styles.appCardLabel}>
              {option.label}
            </Text>
          </Pressable>
        ))}
      </View>

      {helper ? (
        <BlurView intensity={16} tint="dark" style={styles.helperCard}>
          <Ionicons name="lock-closed-outline" size={18} color={theme.colors.accent} />
          <Text variant="caption" style={{ color: theme.colors.textMuted, flex: 1 }}>
            {helper}
          </Text>
        </BlurView>
      ) : null}
    </View>
  );
}

function ScrollMinutesStep({
  styles,
  theme,
  value,
  onChange
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  value: number;
  onChange: (value: number) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        ZEITVERLUST
      </Text>
      <Text variant="title">Wie viel Zeit verlierst du?</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Ehrlich schätzen. Dann passt der Schutz.
      </Text>

      <View style={styles.minutesDisplay}>
        <Text style={[styles.minutesValue, { color: theme.colors.accent }]}>{value}</Text>
        <Text variant="heading" style={styles.minutesSuffix}>
          Minuten
        </Text>
      </View>

      <Slider
        minimumValue={15}
        maximumValue={240}
        step={1}
        value={value}
        onValueChange={(next) => onChange(Math.round(next))}
        onSlidingComplete={() => {
          void Haptics.selectionAsync().catch(() => {});
        }}
        minimumTrackTintColor={theme.colors.accent}
        maximumTrackTintColor="rgba(255,255,255,0.16)"
        thumbTintColor="#FFFFFF"
      />

      <StatPill label="Pro Woche" value={`${Math.round((value * 7) / 60)} Std`} theme={theme} styles={styles} />
    </View>
  );
}

function ListSelectionStep({
  styles,
  theme,
  title,
  subtitle,
  options,
  selectedIds,
  onToggle
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  title: string;
  subtitle: string;
  options: SelectionOption[];
  selectedIds: string[];
  onToggle: (id: any) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        PSYCHOLOGIE
      </Text>
      <Text variant="title">{title}</Text>
      <Text variant="body" style={styles.subtleCopy}>
        {subtitle}
      </Text>

      <View style={styles.listStack}>
        {options.map((option) => (
          <SelectionRow
            key={option.id}
            option={option}
            selected={selectedIds.includes(option.id)}
            onPress={() => onToggle(option.id)}
            styles={styles}
            theme={theme}
          />
        ))}
      </View>
    </View>
  );
}

function DiagnosisStep({
  styles,
  theme,
  name,
  score,
  average
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  name: string;
  score: number;
  average: number;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={[styles.eyebrow, { color: theme.colors.dangerSoft }]}>
        DIAGNOSE
      </Text>
      <Text variant="title">Gerade steuert der Reflex, {name}.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Dein Impuls ist schneller als dein Vorsatz.
      </Text>

      <LinearGradient colors={['rgba(255,122,26,0.22)', 'rgba(255,122,26,0.04)']} style={styles.diagnosisCard}>
        <View style={styles.barComparison}>
          <ScoreBar label="Dein Muster" value={score} tone="danger" styles={styles} theme={theme} />
          <ScoreBar label="Durchschnitt" value={average} tone="accent" styles={styles} theme={theme} />
        </View>

        <Text variant="heading">{score - average}% über dem Schnitt</Text>
      </LinearGradient>
    </View>
  );
}

function ReframeStep({
  styles,
  theme,
  minutes,
  pushUps,
  monthlyHoursLost
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  minutes: number;
  pushUps: number;
  monthlyHoursLost: number;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        REFRAME
      </Text>
      <Text variant="title">Aus Zeitverlust wird Schutz.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Reps setzen den Preis.
      </Text>

      <View style={styles.metricGrid}>
        <MetricCard label="Täglicher Verlust" value={`${minutes} Min`} detail="aktuell" styles={styles} theme={theme} />
        <MetricCard label="Erster Zugriff" value={`${pushUps} Reps`} detail="pro Sperre" styles={styles} theme={theme} accent />
        <MetricCard label="Monatlich zurück" value={`${monthlyHoursLost} Std`} detail="zurückgewonnene Zeit" styles={styles} theme={theme} />
      </View>
    </View>
  );
}

function MechanicStep({
  styles,
  theme,
  app,
  pushUps
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  app: AppSelectionOption;
  pushUps: number;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        PRODUKTMECHANIK
      </Text>
      <Text variant="title">Die Regel ist ganz einfach.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Öffnen. Block. Reps. Zugriff.
      </Text>

      <PhoneShell styles={styles} theme={theme}>
        <View style={styles.lockedAppShell}>
          <BrandBubble option={app} size="large" theme={theme} />
          <Text variant="heading" style={{ textAlign: 'center' }}>
            {app.label} ist gesperrt
          </Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
            Zugriff kostet {pushUps} Reps.
          </Text>

          <LinearGradient colors={[theme.colors.accent, theme.colors.accentSoft]} style={styles.unlockBadge}>
            <Ionicons name="barbell-outline" size={18} color="#101406" />
            <Text variant="caption" style={{ color: '#101406' }}>
              Noch {pushUps} offen
            </Text>
          </LinearGradient>
        </View>
      </PhoneShell>

      <View style={styles.mechanicSteps}>
        <MiniStep label="1" text="App öffnen. Sofort Sperre." styles={styles} theme={theme} />
        <MiniStep label="2" text="Reps machen. Zugriff zurück." styles={styles} theme={theme} />
      </View>
    </View>
  );
}

function ScreenTimePermissionStep({
  styles,
  theme,
  status,
  selectionCount,
  shieldStatus,
  isBusy,
  message,
  onAuthorize,
  onChooseApps
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  status: ScreenTimeAuthorizationStatus;
  selectionCount: number;
  shieldStatus: 'inactive' | 'active' | 'unsupported';
  isBusy: boolean;
  message: string | null;
  onAuthorize: () => Promise<void>;
  onChooseApps: () => Promise<void>;
}) {
  const approved = status === 'approved';

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        SCREEN TIME
      </Text>
      <Text variant="title">Ein Schritt zum echten Schutz.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Ohne Freigabe keine Sperre.
      </Text>

      <PhoneShell styles={styles} theme={theme}>
        <View style={styles.permissionScreen}>
          <Image
            source={require('../../assets/onboarding/permission-orb.png')}
            style={styles.permissionOrb}
            resizeMode="contain"
          />
          <Text variant="heading" style={{ textAlign: 'center' }}>
            Freigabe jetzt erteilen.
          </Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
            Danach Apps für die Sperre wählen.
          </Text>

          <View style={styles.permissionStatusRow}>
            <StatusChip
              label={approved ? 'Berechtigt' : 'Noch offen'}
              value={approved ? 'Family Controls an' : 'Berechtigung fehlt'}
              tone={approved ? 'accent' : 'danger'}
              styles={styles}
              theme={theme}
            />
            <StatusChip
              label="Auswahl"
              value={selectionCount > 0 ? `${selectionCount} Ziele` : 'Noch leer'}
              tone={selectionCount > 0 ? 'accent' : 'danger'}
              styles={styles}
              theme={theme}
            />
          </View>

          <View style={styles.permissionButtonStack}>
            <InlineActionButton
              label={approved ? 'Berechtigung aktiv' : 'Screen Time erlauben'}
              onPress={onAuthorize}
              disabled={approved || isBusy}
              styles={styles}
              theme={theme}
            />
            <InlineActionButton
              label={selectionCount > 0 ? 'Auswahl anpassen' : 'Geschützte Apps wählen'}
              onPress={onChooseApps}
              disabled={!approved || isBusy}
              styles={styles}
              theme={theme}
              variant="secondary"
            />
          </View>

          <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
            Schutz: {shieldStatus === 'active' ? 'aktiv' : shieldStatus === 'unsupported' ? 'nicht verfügbar' : 'offen'}
          </Text>
        </View>
      </PhoneShell>

      {message ? (
        <BlurView intensity={16} tint="dark" style={styles.helperCard}>
          <Ionicons name="information-circle-outline" size={18} color={theme.colors.accent} />
          <Text variant="caption" style={{ color: theme.colors.textMuted, flex: 1 }}>
            {message}
          </Text>
        </BlurView>
      ) : null}

      {isBusy ? (
        <View style={styles.nativeBusyRow}>
          <ActivityIndicator size="small" color={theme.colors.accent} />
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            Schutz wird verbunden ...
          </Text>
        </View>
      ) : null}
    </View>
  );
}

function CameraCalibrationStep({
  styles,
  theme,
  poseEngineReady
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  poseEngineReady: boolean;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        KAMERA SETUP
      </Text>
      <Text variant="title">Richte die Kamera kurz aus.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Dann zählen Reps zuverlässig.
      </Text>

      <View style={styles.tipStack}>
        <TipCard
          title="Ganzkörper sichtbar"
          body="Kopf bis Füße im Bild."
          icon="scan-outline"
          styles={styles}
          theme={theme}
        />
        <TipCard
          title="Helles, klares Licht"
          body="Mehr Licht, bessere Erkennung."
          icon="sunny-outline"
          styles={styles}
          theme={theme}
        />
      </View>

      <BlurView intensity={18} tint="dark" style={styles.posePreviewCard}>
        <Image
          source={require('../../assets/characters/pushup-athlete.png')}
          style={styles.poseAthlete}
          resizeMode="contain"
        />
        <Image
          source={require('../../assets/skeleton/neon-skeleton-hud.png')}
          style={styles.poseSkeleton}
          resizeMode="contain"
        />
      </BlurView>

      <StatPill label="Pose Engine" value={poseEngineReady ? 'bereit' : 'lädt ...'} theme={theme} styles={styles} />
    </View>
  );
}

function PushUpTrialStep({
  styles,
  theme,
  leadApp,
  answers,
  frame,
  onPoseFrame
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  leadApp: AppSelectionOption;
  answers: ReturnType<typeof useOnboardingFlow>['answers'];
  frame: PoseFrame | null;
  onPoseFrame: (event: { nativeEvent: PoseFrame }) => void;
}) {
  const showDebugPanel = __DEV__;
  const debug = frame?.pushupDebug;
  const repBlockedReasons = debug?.repBlockedReasons ?? frame?.diagnostics?.repBlockedReasons ?? frame?.repDebug?.blockedReasons ?? [];
  const compiledWithMediaPipe = debug?.compiledWithMediaPipe ?? frame?.compiledWithMediaPipe;
  const poseModelFound = debug?.poseModelFound ?? frame?.poseModelFound;
  const poseModelName = debug?.poseModelName ?? frame?.poseModelName;
  const poseModelPath = debug?.poseModelPath ?? frame?.poseModelPath;
  const poseLandmarkerInitStatus = debug?.poseLandmarkerInitStatus ?? frame?.poseLandmarkerInitStatus;
  const mediapipeInitReason = debug?.mediapipeInitReason ?? frame?.mediapipeInitReason;
  const mediaPipeWarning = resolveMediaPipeWarning(mediapipeInitReason);
  const mediaPipeIssue =
    (debug?.requestedBackend ?? frame?.requestedBackend) === 'mediapipe' &&
    ((debug?.mediapipeAvailable ?? frame?.mediapipeAvailable) === false ||
      Boolean(mediapipeInitReason) ||
      Boolean(debug?.fallbackReason ?? frame?.fallbackReason));

  return (
    <View style={[styles.standardStep, styles.cameraFirstStep]}>
      <Text variant="heading" numberOfLines={1} style={styles.cameraTrialHeadline}>
        Kamera-Test: {PUSHLY_TRIAL_REP_TARGET} saubere Reps für {leadApp.label}
      </Text>

      <View style={styles.cameraStage}>
        <PushlyCameraView
          isActive
          showSkeleton
          repTarget={999}
          poseBackendMode="auto"
          forceFullFrameProcessing={true}
          debugMode={false}
          onPoseFrame={onPoseFrame}
          style={styles.cameraSurface}
        />

        <View style={styles.cameraCounterWrap}>
          <BlurView intensity={22} tint="dark" style={styles.cameraCounterCircle}>
            <Text variant="heading" style={styles.cameraCounterValue}>
              {answers.pushUpRepCount}
            </Text>
          </BlurView>
        </View>
      </View>

      {showDebugPanel ? (
        <BlurView intensity={18} tint="dark" style={styles.cameraDebugPanel}>
          <Text variant="caption" style={styles.cameraDebugHeading}>
            Debug
          </Text>
          {mediaPipeIssue ? (
            <View style={styles.cameraDebugWarning}>
              <Text variant="caption" style={styles.cameraDebugWarningTitle}>
                MediaPipe nicht verfügbar
              </Text>
              <Text variant="caption" style={styles.cameraDebugWarningBody}>
                {mediaPipeWarning}
              </Text>
            </View>
          ) : null}
          {mediaPipeIssue ? (
            <Text variant="caption" style={styles.cameraDebugLine}>
              MediaPipe status: {(debug?.mediapipeAvailable ?? frame?.mediapipeAvailable) === false ? 'unavailable' : 'error'} ({mediapipeInitReason ?? debug?.fallbackReason ?? frame?.fallbackReason ?? 'unknown'})
            </Text>
          ) : null}
          <Text variant="caption" style={styles.cameraDebugLine}>
            compiledWithMediaPipe: {typeof compiledWithMediaPipe === 'boolean' ? (compiledWithMediaPipe ? 'yes' : 'no') : '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            poseModelFound: {typeof poseModelFound === 'boolean' ? (poseModelFound ? 'yes' : 'no') : '-'} | poseModelName: {poseModelName ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            poseModelPath: {poseModelPath ?? '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            poseLandmarkerInitStatus: {poseLandmarkerInitStatus ?? '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            mediapipeInitReason: {mediapipeInitReason ?? '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            state: {debug?.state ?? frame?.state ?? answers.pushUpState} | repCount: {debug?.repCount ?? answers.pushUpRepCount}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            backend req/active: {debug?.requestedBackend ?? frame?.requestedBackend ?? '-'} / {debug?.activeBackend ?? frame?.activeBackend ?? frame?.poseBackend ?? '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            mediapipeAvailable: {(debug?.mediapipeAvailable ?? frame?.mediapipeAvailable) ? 'yes' : 'no'} | fallbackReason: {debug?.fallbackReason ?? frame?.fallbackReason ?? '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            fallback allowed/used: {(debug?.fallbackAllowed ?? frame?.fallbackAllowed) ? 'yes' : 'no'} / {(debug?.fallbackUsed ?? frame?.fallbackUsed) ? 'yes' : 'no'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            trackingQuality: {formatDebugNumber(debug?.trackingQuality ?? frame?.trackingQuality)} | logicQuality: {formatDebugNumber(debug?.logicQuality ?? frame?.logicQuality)}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            upperBodyCoverage: {formatDebugNumber(debug?.upperBodyCoverage ?? frame?.upperBodyCoverage)} | wristRetention: {formatDebugNumber(debug?.wristRetention ?? frame?.wristRetention)}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            gate pass/block: {debug?.countGatePassed ? 'yes' : 'no'} / {debug?.countGateBlocked ? 'yes' : 'no'} ({debug?.countGateBlockReason ?? '-'})
          </Text>
          <Text variant="caption" numberOfLines={2} style={styles.cameraDebugLine}>
            repBlockedReasons: {repBlockedReasons.length > 0 ? repBlockedReasons.join(', ') : '-'}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            bottomReached: {debug?.bottomReached ? 'yes' : 'no'} | frames d/b/a: {debug?.descendingFrames ?? 0}/{debug?.bottomFrames ?? 0}/{debug?.ascendingFrames ?? 0}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            torsoDown: {formatDebugNumber(debug?.torsoDownTravel)} | torsoRecovery: {formatDebugNumber(debug?.torsoRecoveryToTop)}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            shoulderDown: {formatDebugNumber(debug?.shoulderDownTravel)} | shoulderRecovery: {formatDebugNumber(debug?.shoulderRecoveryToTop)}
          </Text>
          <Text variant="caption" style={styles.cameraDebugLine}>
            signals d/a: {debug?.descendingSignal ? '1' : '0'}/{debug?.ascendingSignal ? '1' : '0'} | cycle/strict/floor: {debug?.cycleCoreReady ? '1' : '0'}/{debug?.strictCycleReady ? '1' : '0'}/{debug?.floorFallbackCycleReady ? '1' : '0'}
          </Text>
        </BlurView>
      ) : null}
    </View>
  );
}

function formatDebugNumber(value: number | undefined): string {
  if (typeof value !== 'number' || Number.isNaN(value)) {
    return '-';
  }
  return value.toFixed(3);
}

function resolveMediaPipeWarning(reason?: string): string {
  switch (reason) {
    case 'pose_model_missing':
      return 'Modelldatei fehlt im iOS-Bundle. App neu bauen und pose_landmarker_*.task mitliefern.';
    case 'mediapipe_tasks_vision_not_compiled':
      return 'MediaPipe-Framework ist nicht im Build. iOS-Dependencies/Pods installieren und neu bauen.';
    default:
      return `Landmarker-Initialisierung fehlgeschlagen (${reason ?? 'unknown'}). App neu starten oder iOS-Build neu erstellen.`;
  }
}

function RatingStep({
  styles,
  theme,
  answers
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  answers: ReturnType<typeof useOnboardingFlow>['answers'];
}) {
  const days = Math.max(3, Math.round(answers.dailyScrollMinutes / 28));

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        SOCIAL PROOF
      </Text>
      <Text variant="title">Du bist damit nicht allein.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Die Methode wirkt bei vielen.
      </Text>

      <BlurView intensity={20} tint="dark" style={styles.ratingHero}>
        <Text variant="heading" style={{ textAlign: 'center' }}>
          4,8 / 5 aus der Beta-Community
        </Text>
      </BlurView>

      <View style={styles.timelineStack}>
        {[
          `Tag 1: Du stoppst Auto-Öffnen mit ${answers.pushUpRepCount || 1} Reps.`,
          `Tag ${days}: Der Zug der Trigger sinkt spürbar.`
        ].map((item, index) => (
          <BlurView key={item} intensity={16} tint="dark" style={styles.timelineCard}>
            <View style={styles.timelineBadge}>
              <Text variant="caption" style={{ color: '#0F1208' }}>
                0{index + 1}
              </Text>
            </View>
            <Text variant="caption" style={{ color: theme.colors.textMuted, flex: 1 }}>
              {item}
            </Text>
          </BlurView>
        ))}
      </View>
    </View>
  );
}

function AuthStep({
  styles,
  theme,
  selectedMethod,
  onSelectMethod
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedMethod: ReturnType<typeof useOnboardingFlow>['answers']['authMethod'];
  onSelectMethod: (method: ReturnType<typeof useOnboardingFlow>['answers']['authMethod']) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Image source={require('../../assets/images/logo_header.png')} style={styles.paywallLogo} resizeMode="contain" />
      <Text variant="title">Sichere deinen Fortschritt.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Noch ein Schritt, dann fertig.
      </Text>

      <View style={styles.authMethodStack}>
        {AUTH_METHOD_OPTIONS.map((option) => {
          const selected = selectedMethod === option.id;

          return (
            <Pressable
              key={option.id}
              onPress={() => onSelectMethod(option.id)}
              style={({ pressed }) => [
                styles.authMethodCard,
                pressed && styles.touchPressed,
                selected && {
                  borderColor: theme.colors.accent,
                  backgroundColor: 'rgba(186,250,32,0.1)'
                }
              ]}
            >
              <View style={[styles.selectionIconWrap, selected && { backgroundColor: 'rgba(186,250,32,0.16)' }]}>
                <Ionicons name={option.icon as keyof typeof Ionicons.glyphMap} size={20} color={selected ? theme.colors.accent : theme.colors.text} />
              </View>
              <View style={styles.selectionCopy}>
                <Text variant="heading">{option.label}</Text>
                <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                  {option.description}
                </Text>
              </View>
              <View style={[styles.selectionCheck, selected && { backgroundColor: theme.colors.accent }]}>
                {selected ? <Ionicons name="checkmark" size={14} color="#0F1208" /> : null}
              </View>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

function TrustStep({
  styles,
  theme
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        WARUM DAS FUNKTIONIERT
      </Text>
      <Text variant="title">Pushly setzt echte Reibung.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Genau im Moment des Impulses.
      </Text>

      <View style={styles.trustCards}>
        {TRUST_BULLETS.map((bullet, index) => (
          <BlurView key={bullet} intensity={18} tint="dark" style={styles.trustCard}>
            <View style={styles.trustCardIndex}>
              <Text variant="caption" style={{ color: '#0F1208' }}>
                0{index + 1}
              </Text>
            </View>
            <Text variant="body" style={{ flex: 1 }}>
              {bullet}
            </Text>
          </BlurView>
        ))}
      </View>

    </View>
  );
}

function PaywallStep({
  styles,
  theme,
  selectedPlanId,
  onSelectPlan
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedPlanId: 'yearly' | 'monthly';
  onSelectPlan: (id: 'yearly' | 'monthly') => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Image source={require('../../assets/images/logo_header.png')} style={styles.paywallLogo} resizeMode="contain" />
      <Text variant="title">Wähle deinen Zugang.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Du kaufst Schutz statt Willenskraft.
      </Text>

      <BlurView intensity={20} tint="dark" style={styles.quoteCard}>
        <Text variant="heading">Jeder Zugriff hat einen Preis.</Text>
      </BlurView>

      <View style={styles.planStack}>
        {PAYWALL_PLAN_OPTIONS.map((plan) => {
          const selected = selectedPlanId === plan.id;

          return (
            <Pressable
              key={plan.id}
              onPress={() => onSelectPlan(plan.id)}
              style={({ pressed }) => [
                styles.planCard,
                pressed && styles.touchPressed,
                selected && {
                  borderColor: theme.colors.accent,
                  backgroundColor: 'rgba(186,250,32,0.1)'
                }
              ]}
            >
              {plan.badge ? (
                <LinearGradient colors={[theme.colors.accent, theme.colors.accentSoft]} style={styles.planBadge}>
                  <Text variant="caption" style={{ color: '#0F1208' }}>
                    {plan.badge}
                  </Text>
                </LinearGradient>
              ) : null}

              <View style={styles.planRow}>
                <View style={styles.planCopy}>
                  <Text variant="heading">{plan.title}</Text>
                  <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                    {plan.subline}
                  </Text>
                </View>

                <View style={styles.planPriceBlock}>
                  <Text variant="heading">{plan.price}</Text>
                  <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                    {plan.monthlyEquivalent}
                  </Text>
                </View>
              </View>

              <View style={[styles.planCheck, selected && { backgroundColor: theme.colors.accent }]}>
                {selected ? <Ionicons name="checkmark" size={14} color="#0F1208" /> : null}
              </View>
            </Pressable>
          );
        })}
      </View>

      <View style={styles.featureColumn}>
        {['Sperre für deine Trigger', 'Reps für jeden Zugriff'].map((item) => (
          <View key={item} style={styles.featureRow}>
            <Ionicons name="checkmark-circle" size={18} color={theme.colors.accent} />
            <Text variant="caption" style={{ color: theme.colors.textMuted, flex: 1 }}>
              {item}
            </Text>
          </View>
        ))}
      </View>
    </View>
  );
}

function SetupPreviewStep({
  styles,
  theme,
  app,
  answers
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  app: AppSelectionOption;
  answers: ReturnType<typeof useOnboardingFlow>['answers'];
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        BEREIT
      </Text>
      <Text variant="title">Dein Schutz ist bereit.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Setup fertig. Du kannst loslegen.
      </Text>

      <PhoneShell styles={styles} theme={theme}>
        <View style={styles.setupPreviewScreen}>
          <BrandBubble option={app} size="medium" theme={theme} />
          <Text variant="heading">Erste Schutz-App: {app.label}</Text>
          <View style={styles.permissionStatusRow}>
            <StatusChip
              label="Reps erkannt"
              value={`${answers.pushUpRepCount}`}
              tone="accent"
              styles={styles}
              theme={theme}
            />
            <StatusChip
              label="Shield"
              value={answers.shieldStatus === 'active' ? 'aktiv' : 'bereit'}
              tone="accent"
              styles={styles}
              theme={theme}
            />
          </View>
          <View style={styles.setupList}>
            {SETUP_PREVIEW_STEPS.map((step, index) => (
              <View key={step} style={styles.setupRow}>
                <View style={styles.setupIndex}>
                  <Text variant="caption" style={{ color: '#0F1208' }}>
                    {index + 1}
                  </Text>
                </View>
                <Text variant="caption" style={{ color: theme.colors.textMuted, flex: 1 }}>
                  {step}
                </Text>
              </View>
            ))}
          </View>
        </View>
      </PhoneShell>
    </View>
  );
}

function FlowHeader({
  progress,
  onBack,
  tone,
  showProgress,
  canGoBack,
  stepLabel,
  stepIndex,
  stepCount
}: {
  progress: number;
  onBack: () => void;
  tone: 'accent' | 'danger';
  showProgress: boolean;
  canGoBack: boolean;
  stepLabel: string;
  stepIndex: number;
  stepCount: number;
}) {
  const { theme } = useTheme();
  const styles = createStyles(theme);

  return (
    <View style={styles.header}>
      <Pressable
        onPress={onBack}
        disabled={!canGoBack}
        style={({ pressed }) => [styles.backButton, pressed && canGoBack && styles.touchPressed]}
      >
        <Ionicons
          name="chevron-back"
          size={22}
          color={canGoBack ? theme.colors.text : theme.colors.textMuted}
        />
      </Pressable>

      {showProgress ? (
        <View style={styles.headerCenter}>
          <View style={styles.progressTrack}>
            <LinearGradient
              colors={
                tone === 'danger'
                  ? [theme.colors.danger, theme.colors.dangerSoft]
                  : [theme.colors.accent, theme.colors.accentSoft]
              }
              style={[styles.progressFill, { width: `${Math.max(progress * 100, 7)}%` }]}
            />
          </View>
          <Text variant="caption" style={styles.headerStepMeta}>
            {stepIndex + 1}/{stepCount} · {stepLabel}
          </Text>
        </View>
      ) : (
        <Text variant="caption" style={styles.headerHeroLabel}>
          Pushly Onboarding
        </Text>
      )}

      <View style={styles.headerSpacer} />
    </View>
  );
}

function AmbientBackdrop({
  pulse,
  tone,
  theme
}: {
  pulse: Animated.Value;
  tone: 'accent' | 'danger';
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  const color = tone === 'danger' ? theme.colors.danger : theme.colors.accent;

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <Image
        source={require('../../assets/backgrounds/limelight-haze.png')}
        style={backdropStyles.atmosphere}
        resizeMode="cover"
      />
      <Animated.View
        style={[
          backdropStyles.glowOne,
          {
            backgroundColor: color,
            opacity: 0.13,
            transform: [
              {
                scale: pulse.interpolate({
                  inputRange: [0, 1],
                  outputRange: [0.92, 1.14]
                })
              }
            ]
          }
        ]}
      />
      <Animated.View
        style={[
          backdropStyles.glowTwo,
          {
            backgroundColor: theme.colors.accentSoft,
            opacity: tone === 'danger' ? 0.05 : 0.1,
            transform: [
              {
                scale: pulse.interpolate({
                  inputRange: [0, 1],
                  outputRange: [1.04, 0.96]
                })
              }
            ]
          }
        ]}
      />
      {Array.from({ length: 22 }).map((_, index) => (
        <View
          key={index}
          style={[
            backdropStyles.star,
            {
              top: `${(index * 19) % 100}%`,
              left: `${(index * 31) % 100}%`,
              opacity: index % 3 === 0 ? 0.24 : 0.12
            }
          ]}
        />
      ))}
    </View>
  );
}

function GradientCta({
  label,
  onPress,
  disabled,
  tone,
  styles,
  theme
}: {
  label: string;
  onPress: () => void;
  disabled: boolean;
  tone: 'accent' | 'danger';
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  const [ctaWidth, setCtaWidth] = useState(0);
  const sheenProgress = useRef(new Animated.Value(0)).current;
  const sheenStart = -120;
  const sheenEnd = (ctaWidth || 260) + 120;
  const sheenCycle = sheenEnd - sheenStart;

  const firstSheenX = sheenProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [sheenStart, sheenEnd]
  });

  const secondSheenX = sheenProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [sheenStart - sheenCycle, sheenEnd - sheenCycle]
  });

  useEffect(() => {
    if (disabled) {
      sheenProgress.stopAnimation();
      sheenProgress.setValue(0);
      return undefined;
    }

    sheenProgress.setValue(0);
    const sheenLoop = Animated.loop(
      Animated.timing(sheenProgress, {
        toValue: 1,
        duration: 1650,
        easing: Easing.linear,
        useNativeDriver: true
      })
    );

    sheenLoop.start();

    return () => {
      sheenLoop.stop();
    };
  }, [disabled, sheenProgress]);

  const colors =
    tone === 'danger'
      ? ([theme.colors.danger, theme.colors.dangerSoft] as const)
      : ([theme.colors.accentStrong, theme.colors.accent] as const);

  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.ctaShell,
        disabled && styles.ctaDisabled,
        pressed && !disabled && styles.ctaPressed
      ]}
    >
      <LinearGradient
        colors={colors}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={styles.ctaGradient}
        onLayout={(event) => {
          const nextWidth = Math.round(event.nativeEvent.layout.width);
          if (nextWidth > 0 && nextWidth !== ctaWidth) {
            setCtaWidth(nextWidth);
          }
        }}
      >
        {!disabled ? (
          <>
            <Animated.View
              pointerEvents="none"
              style={[
                styles.ctaSheen,
                {
                  transform: [{ translateX: firstSheenX }, { rotate: '20deg' }]
                }
              ]}
            >
              <LinearGradient
                colors={['rgba(255,255,255,0)', 'rgba(255,255,255,0.45)', 'rgba(255,255,255,0)']}
                style={StyleSheet.absoluteFill}
              />
            </Animated.View>
            <Animated.View
              pointerEvents="none"
              style={[
                styles.ctaSheen,
                {
                  transform: [{ translateX: secondSheenX }, { rotate: '20deg' }]
                }
              ]}
            >
              <LinearGradient
                colors={['rgba(255,255,255,0)', 'rgba(255,255,255,0.45)', 'rgba(255,255,255,0)']}
                style={StyleSheet.absoluteFill}
              />
            </Animated.View>
          </>
        ) : null}

        <Text variant="heading" style={{ color: '#0F1208' }}>
          {label}
        </Text>
      </LinearGradient>
    </Pressable>
  );
}

function SelectionRow({
  option,
  selected,
  onPress,
  styles,
  theme
}: {
  option: SelectionOption;
  selected: boolean;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.selectionRow,
        pressed && styles.touchPressed,
        selected && {
          borderColor: theme.colors.accent,
          backgroundColor: 'rgba(186,250,32,0.1)'
        }
      ]}
    >
      <View style={[styles.selectionIconWrap, selected && { backgroundColor: 'rgba(186,250,32,0.16)' }]}>
        <Ionicons name={option.iconName as any} size={20} color={selected ? theme.colors.accent : theme.colors.text} />
      </View>

      <View style={styles.selectionCopy}>
        <Text variant="heading">{option.label}</Text>
        {option.description ? (
          <Text variant="caption" style={{ color: theme.colors.textMuted }}>
            {option.description}
          </Text>
        ) : null}
      </View>

      <View style={[styles.selectionCheck, selected && { backgroundColor: theme.colors.accent }]}>
        {selected ? <Ionicons name="checkmark" size={14} color="#0F1208" /> : null}
      </View>
    </Pressable>
  );
}

function PhoneShell({
  children,
  styles,
  theme
}: {
  children: React.ReactNode;
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <View style={styles.phoneFrame}>
      <View style={styles.phoneNotch} />
      <LinearGradient
        colors={['rgba(255,255,255,0.08)', 'rgba(255,255,255,0.02)']}
        style={styles.phoneInnerBorder}
      >
        <View style={[styles.phoneScreen, { backgroundColor: theme.colors.backgroundDeep }]}>{children}</View>
      </LinearGradient>
    </View>
  );
}

function BrandBubble({
  option,
  size,
  theme
}: {
  option: AppSelectionOption;
  size: 'small' | 'medium' | 'large';
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  const bubbleSize = size === 'small' ? 44 : size === 'medium' ? 58 : 74;
  const iconSize = size === 'small' ? 18 : size === 'medium' ? 22 : 28;

  return (
    <View
      style={{
        width: bubbleSize,
        height: bubbleSize,
        borderRadius: bubbleSize / 2,
        backgroundColor: 'rgba(255,255,255,0.06)',
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,0.1)',
        alignItems: 'center',
        justifyContent: 'center'
      }}
    >
      <FontAwesome6
        name={option.iconName as any}
        iconStyle={option.iconStyle === 'brand' ? 'brand' : 'solid'}
        size={iconSize}
        color={option.brandColor ?? theme.colors.text}
      />
    </View>
  );
}

function FloatingBrand({
  option,
  styles,
  position
}: {
  option: AppSelectionOption;
  styles: ReturnType<typeof createStyles>;
  position: 'leftTop' | 'rightTop' | 'leftBottom' | 'rightBottom';
}) {
  return (
    <View style={[styles.floatingBrand, styles[position]]}>
      <BrandBubble option={option} size="small" theme={useTheme().theme} />
    </View>
  );
}

function MockFeedCard({
  label,
  value,
  accent = false
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  const { theme } = useTheme();
  const styles = createStyles(theme);

  return (
    <BlurView intensity={18} tint="dark" style={[styles.feedCard, accent && styles.feedCardAccent]}>
      <Text variant="caption" style={{ color: accent ? '#0F1208' : theme.colors.textMuted }}>
        {label}
      </Text>
      <Text variant="heading" style={{ color: accent ? '#0F1208' : theme.colors.text }}>
        {value}
      </Text>
    </BlurView>
  );
}

function MetricCard({
  label,
  value,
  detail,
  styles,
  theme,
  accent = false
}: {
  label: string;
  value: string;
  detail: string;
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  accent?: boolean;
}) {
  return (
    <BlurView intensity={18} tint="dark" style={[styles.metricCard, accent && styles.metricCardAccent]}>
      <Text variant="caption" style={{ color: accent ? '#0F1208' : theme.colors.textMuted }}>
        {label}
      </Text>
      <Text variant="title" style={{ fontSize: 28, lineHeight: 30, color: accent ? '#0F1208' : theme.colors.text }}>
        {value}
      </Text>
      <Text variant="caption" style={{ color: accent ? '#1E260E' : theme.colors.textMuted }}>
        {detail}
      </Text>
    </BlurView>
  );
}

function ScoreBar({
  label,
  value,
  tone,
  styles,
  theme
}: {
  label: string;
  value: number;
  tone: 'danger' | 'accent';
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  const colors =
    tone === 'danger'
      ? ([theme.colors.danger, theme.colors.dangerSoft] as const)
      : ([theme.colors.accentStrong, theme.colors.accent] as const);

  return (
    <View style={styles.scoreColumn}>
      <View style={styles.scoreTrack}>
        <LinearGradient colors={colors} style={[styles.scoreFill, { height: `${value}%` }]}>
          <Text variant="caption" style={{ color: '#0F1208', fontFamily: theme.typography.bold }}>
            {value}%
          </Text>
        </LinearGradient>
      </View>
      <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
        {label}
      </Text>
    </View>
  );
}

function TipCard({
  title,
  body,
  icon,
  styles,
  theme
}: {
  title: string;
  body: string;
  icon: keyof typeof Ionicons.glyphMap;
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <BlurView intensity={18} tint="dark" style={styles.tipCard}>
      <View style={styles.tipIcon}>
        <Ionicons name={icon} size={20} color={theme.colors.accent} />
      </View>
      <View style={{ flex: 1 }}>
        <Text variant="heading">{title}</Text>
        <Text variant="caption" style={{ color: theme.colors.textMuted }}>
          {body}
        </Text>
      </View>
    </BlurView>
  );
}

function MiniStep({
  label,
  text,
  styles,
  theme
}: {
  label: string;
  text: string;
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <View style={styles.miniStep}>
      <View style={styles.miniStepBadge}>
        <Text variant="caption" style={{ color: '#0F1208' }}>
          {label}
        </Text>
      </View>
      <Text variant="caption" style={{ color: theme.colors.textMuted, flex: 1 }}>
        {text}
      </Text>
    </View>
  );
}

function StatPill({
  label,
  value,
  theme,
  styles
}: {
  label: string;
  value: string;
  theme: ReturnType<typeof useTheme>['theme'];
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <BlurView intensity={14} tint="dark" style={styles.statPill}>
      <Text variant="caption" style={{ color: theme.colors.textMuted }}>
        {label}
      </Text>
      <Text variant="caption" style={{ color: theme.colors.text }}>
        {value}
      </Text>
    </BlurView>
  );
}

function StatusChip({
  label,
  value,
  tone,
  styles,
  theme
}: {
  label: string;
  value: string;
  tone: 'accent' | 'danger';
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <BlurView
      intensity={18}
      tint="dark"
      style={[
        styles.statusChip,
        tone === 'accent'
          ? { borderColor: 'rgba(186,250,32,0.28)' }
          : { borderColor: 'rgba(255,122,26,0.28)' }
      ]}
    >
      <Text variant="caption" style={{ color: theme.colors.textMuted }}>
        {label}
      </Text>
      <Text variant="heading" style={{ color: tone === 'accent' ? theme.colors.accent : theme.colors.dangerSoft }}>
        {value}
      </Text>
    </BlurView>
  );
}

function InlineActionButton({
  label,
  onPress,
  disabled,
  styles,
  theme,
  variant = 'primary'
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  variant?: 'primary' | 'secondary';
}) {
  const handlePress = () => {
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
    onPress();
  };

  return (
    <Pressable
      onPress={handlePress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.inlineActionButton,
        variant === 'secondary' && styles.inlineActionButtonSecondary,
        disabled && { opacity: 0.45 },
        pressed && !disabled && styles.touchPressed
      ]}
    >
      <LinearGradient
        colors={
          variant === 'primary'
            ? [theme.colors.accentStrong, theme.colors.accent]
            : ['rgba(255,255,255,0.1)', 'rgba(255,255,255,0.03)']
        }
        style={styles.inlineActionGradient}
      >
        <Text variant="heading" style={{ color: variant === 'primary' ? '#0F1208' : theme.colors.text }}>
          {label}
        </Text>
      </LinearGradient>
    </Pressable>
  );
}

function createStyles(theme: ReturnType<typeof useTheme>['theme']) {
  return StyleSheet.create({
    root: {
      flex: 1
    },
    safeArea: {
      flex: 1
    },
    flex: {
      flex: 1
    },
    centered: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      gap: 16
    },
    logo: {
      width: 170,
      height: 52
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 20,
      paddingBottom: 8,
      paddingTop: 2,
      gap: 12
    },
    headerCenter: {
      flex: 1,
      gap: 6
    },
    headerStepMeta: {
      color: theme.colors.textMuted,
      textAlign: 'center'
    },
    headerHeroLabel: {
      color: theme.colors.textMuted,
      flex: 1,
      textAlign: 'center'
    },
    backButton: {
      width: 36,
      height: 36,
      borderRadius: 18,
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: 'rgba(255,255,255,0.04)'
    },
    progressTrack: {
      flex: 1,
      height: 8,
      borderRadius: 999,
      overflow: 'hidden',
      backgroundColor: 'rgba(255,255,255,0.08)'
    },
    progressFill: {
      height: '100%',
      borderRadius: 999
    },
    headerSpacer: {
      width: 36
    },
    contentContainer: {
      paddingHorizontal: 20,
      paddingBottom: 32,
      alignItems: 'center',
      flexGrow: 1
    },
    contentContainerCameraFocus: {
      paddingBottom: 8
    },
    stepContainer: {
      flex: 1,
      gap: 24,
      width: '100%',
      maxWidth: 560
    },
    stepContainerCameraFocus: {
      gap: 10
    },
    heroStep: {
      gap: 22,
      paddingTop: 18
    },
    heroLogo: {
      width: 170,
      height: 52
    },
    titleBlock: {
      gap: 4
    },
    testReadyCard: {
      borderRadius: 20,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      backgroundColor: 'rgba(255,255,255,0.03)',
      padding: 14,
      gap: 10
    },
    testReadyRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10
    },
    testReadyDot: {
      width: 9,
      height: 9,
      borderRadius: 999
    },
    testReadyDotOn: {
      backgroundColor: theme.colors.accent
    },
    testReadyDotOff: {
      backgroundColor: 'rgba(255,255,255,0.22)'
    },
    heroVisual: {
      position: 'relative',
      alignItems: 'center',
      paddingVertical: 18
    },
    heroMockupAsset: {
      position: 'absolute',
      width: 220,
      height: 220,
      top: 106,
      opacity: 0.26
    },
    floatingBrand: {
      position: 'absolute',
      zIndex: 2
    },
    leftTop: {
      top: 18,
      left: 6
    },
    rightTop: {
      top: 4,
      right: 10
    },
    leftBottom: {
      bottom: 18,
      left: 0
    },
    rightBottom: {
      bottom: 34,
      right: 0
    },
    phoneFrame: {
      width: '82%',
      maxWidth: 320,
      borderRadius: 34,
      borderWidth: 1.5,
      borderColor: 'rgba(255,255,255,0.18)',
      backgroundColor: '#030402',
      padding: 7,
      shadowColor: theme.colors.accent,
      shadowOpacity: 0.18,
      shadowRadius: 28,
      shadowOffset: { width: 0, height: 18 },
      elevation: 12
    },
    phoneNotch: {
      position: 'absolute',
      top: 12,
      left: '34%',
      right: '34%',
      height: 18,
      borderBottomLeftRadius: 14,
      borderBottomRightRadius: 14,
      backgroundColor: '#030402',
      zIndex: 3
    },
    phoneInnerBorder: {
      borderRadius: 28,
      padding: 1
    },
    phoneScreen: {
      minHeight: 430,
      borderRadius: 27,
      overflow: 'hidden',
      padding: 18,
      justifyContent: 'space-between'
    },
    phoneGlow: {
      ...StyleSheet.absoluteFillObject
    },
    lockPreviewTopRow: {
      gap: 14,
      alignItems: 'center',
      marginTop: 24
    },
    lockPreviewStatus: {
      gap: 6,
      alignItems: 'center'
    },
    counterGlass: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      marginTop: 8,
      padding: 16,
      borderRadius: 22,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    counterCopy: {
      flex: 1,
      gap: 4
    },
    mockFeedRow: {
      flexDirection: 'row',
      gap: 10
    },
    feedCard: {
      flex: 1,
      padding: 14,
      borderRadius: 18,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      gap: 2
    },
    feedCardAccent: {
      backgroundColor: theme.colors.accent
    },
    standardStep: {
      gap: 18,
      paddingTop: 8
    },
    eyebrow: {
      color: theme.colors.accent,
      fontFamily: theme.typography.bold,
      letterSpacing: 1.2
    },
    subtleCopy: {
      color: theme.colors.textMuted,
      marginTop: -8
    },
    quizVisual: {
      height: 250,
      alignItems: 'center',
      justifyContent: 'center'
    },
    quizOrbit: {
      position: 'absolute',
      width: 220,
      height: 220,
      borderRadius: 110,
      borderWidth: 1,
      borderColor: 'rgba(186,250,32,0.2)'
    },
    quizCore: {
      width: 110,
      height: 110,
      borderRadius: 55,
      backgroundColor: 'rgba(186,250,32,0.08)',
      borderWidth: 1,
      borderColor: 'rgba(186,250,32,0.26)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    quizSatellite: {
      position: 'absolute'
    },
    quizSatelliteLeft: {
      left: 44,
      top: 76
    },
    quizSatelliteRight: {
      right: 44,
      top: 76
    },
    quizSatelliteBottom: {
      bottom: 38,
      width: 50,
      height: 50,
      borderRadius: 25,
      backgroundColor: 'rgba(255,255,255,0.04)',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    infoPanel: {
      padding: 18,
      borderRadius: 24,
      overflow: 'hidden',
      gap: 8,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    inputShell: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      paddingHorizontal: 16,
      paddingVertical: 16,
      borderRadius: 22,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    input: {
      flex: 1,
      color: theme.colors.text,
      fontFamily: theme.typography.medium,
      fontSize: 18
    },
    inlineMetricRow: {
      flexDirection: 'row',
      gap: 10
    },
    statPill: {
      flex: 1,
      paddingVertical: 12,
      paddingHorizontal: 14,
      borderRadius: 18,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      gap: 4
    },
    selectionHintRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center'
    },
    appGrid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 12
    },
    appCard: {
      width: '30.5%',
      minWidth: 94,
      aspectRatio: 0.9,
      borderRadius: 22,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      backgroundColor: 'rgba(255,255,255,0.03)',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 12
    },
    appCardLabel: {
      textAlign: 'center'
    },
    helperCard: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      padding: 14,
      borderRadius: 18,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.06)'
    },
    minutesDisplay: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      gap: 10
    },
    minutesValue: {
      fontFamily: theme.typography.heavy,
      fontSize: 68,
      lineHeight: 68,
      letterSpacing: -2
    },
    minutesSuffix: {
      marginBottom: 10
    },
    listStack: {
      gap: 12
    },
    selectionRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      borderRadius: 24,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      backgroundColor: 'rgba(255,255,255,0.03)',
      padding: 14
    },
    selectionIconWrap: {
      width: 42,
      height: 42,
      borderRadius: 21,
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: 'rgba(255,255,255,0.04)'
    },
    selectionCopy: {
      flex: 1,
      gap: 3
    },
    selectionCheck: {
      width: 24,
      height: 24,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.18)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    diagnosisCard: {
      padding: 18,
      borderRadius: 28,
      gap: 18,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    barComparison: {
      flexDirection: 'row',
      justifyContent: 'space-around',
      alignItems: 'flex-end',
      gap: 24
    },
    scoreColumn: {
      flex: 1,
      alignItems: 'center',
      gap: 12
    },
    scoreTrack: {
      width: '100%',
      height: 220,
      borderRadius: 28,
      backgroundColor: 'rgba(255,255,255,0.05)',
      justifyContent: 'flex-end',
      overflow: 'hidden',
      padding: 10
    },
    scoreFill: {
      width: '100%',
      borderRadius: 20,
      alignItems: 'center',
      justifyContent: 'flex-start',
      paddingTop: 10
    },
    metricGrid: {
      gap: 12
    },
    metricCard: {
      padding: 18,
      borderRadius: 24,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      gap: 6
    },
    metricCardAccent: {
      backgroundColor: theme.colors.accent
    },
    lockedAppShell: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      gap: 14
    },
    unlockBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      borderRadius: 999,
      paddingHorizontal: 16,
      paddingVertical: 10
    },
    mechanicSteps: {
      gap: 10
    },
    miniStep: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      padding: 14,
      borderRadius: 18,
      backgroundColor: 'rgba(255,255,255,0.03)',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.06)'
    },
    miniStepBadge: {
      width: 28,
      height: 28,
      borderRadius: 14,
      backgroundColor: theme.colors.accent,
      alignItems: 'center',
      justifyContent: 'center'
    },
    tipStack: {
      gap: 12
    },
    tipCard: {
      flexDirection: 'row',
      alignItems: 'flex-start',
      gap: 12,
      padding: 16,
      borderRadius: 22,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    tipIcon: {
      width: 44,
      height: 44,
      borderRadius: 22,
      backgroundColor: 'rgba(186,250,32,0.1)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    trustCards: {
      gap: 12
    },
    trustCard: {
      flexDirection: 'row',
      gap: 12,
      alignItems: 'center',
      padding: 16,
      borderRadius: 22,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    trustCardIndex: {
      width: 34,
      height: 34,
      borderRadius: 17,
      backgroundColor: theme.colors.accent,
      alignItems: 'center',
      justifyContent: 'center'
    },
    paywallLogo: {
      width: 152,
      height: 48,
      marginBottom: 4
    },
    quoteCard: {
      padding: 18,
      borderRadius: 24,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      gap: 8
    },
    planStack: {
      gap: 12
    },
    planCard: {
      position: 'relative',
      borderRadius: 26,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      backgroundColor: 'rgba(255,255,255,0.03)',
      padding: 18,
      gap: 12
    },
    planBadge: {
      alignSelf: 'flex-start',
      borderRadius: 999,
      paddingHorizontal: 12,
      paddingVertical: 6
    },
    planRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      gap: 12
    },
    planCopy: {
      gap: 4,
      flex: 1
    },
    planPriceBlock: {
      alignItems: 'flex-end',
      gap: 4
    },
    planCheck: {
      position: 'absolute',
      right: 16,
      top: 16,
      width: 24,
      height: 24,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.18)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    featureColumn: {
      gap: 10
    },
    featureRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10
    },
    permissionScreen: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      gap: 16
    },
    permissionOrb: {
      width: 132,
      height: 132
    },
    permissionStatusRow: {
      flexDirection: 'row',
      gap: 10,
      width: '100%'
    },
    permissionButtonStack: {
      width: '100%',
      gap: 10
    },
    nativeBusyRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10
    },
    statusChip: {
      flex: 1,
      padding: 14,
      borderRadius: 18,
      overflow: 'hidden',
      borderWidth: 1,
      backgroundColor: 'rgba(255,255,255,0.04)',
      gap: 6
    },
    inlineActionButton: {
      borderRadius: 20,
      overflow: 'hidden'
    },
    inlineActionButtonSecondary: {
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    inlineActionGradient: {
      minHeight: 56,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 18
    },
    posePreviewCard: {
      position: 'relative',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: 290,
      borderRadius: 26,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      backgroundColor: 'rgba(255,255,255,0.04)'
    },
    poseAthlete: {
      width: '100%',
      height: 290
    },
    poseSkeleton: {
      position: 'absolute',
      width: '100%',
      height: 290
    },
    cameraSurface: {
      flex: 1,
      minHeight: 520,
      width: '100%'
    },
    cameraFirstStep: {
      flex: 1,
      gap: 10,
      paddingTop: 0
    },
    cameraTrialHeadline: {
      color: theme.colors.text
    },
    cameraStage: {
      flex: 1,
      minHeight: 520,
      borderRadius: 24,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      backgroundColor: 'rgba(255,255,255,0.03)'
    },
    cameraCounterWrap: {
      position: 'absolute',
      left: 0,
      right: 0,
      bottom: 12,
      alignItems: 'center',
      justifyContent: 'center'
    },
    cameraCounterCircle: {
      width: 88,
      height: 88,
      borderRadius: 44,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.2)',
      backgroundColor: 'rgba(0,0,0,0.38)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    cameraCounterValue: {
      color: theme.colors.text
    },
    cameraDebugPanel: {
      borderRadius: 14,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.14)',
      backgroundColor: 'rgba(8,10,8,0.58)',
      paddingHorizontal: 10,
      paddingVertical: 8,
      gap: 2
    },
    cameraDebugHeading: {
      color: theme.colors.accent
    },
    cameraDebugLine: {
      color: theme.colors.textMuted
    },
    cameraDebugWarning: {
      borderRadius: 10,
      borderWidth: 1,
      borderColor: 'rgba(255,109,91,0.55)',
      backgroundColor: 'rgba(76,18,14,0.55)',
      paddingHorizontal: 10,
      paddingVertical: 8,
      marginBottom: 4
    },
    cameraDebugWarningTitle: {
      color: '#FFB3A9'
    },
    cameraDebugWarningBody: {
      color: '#FFD6D0'
    },
    timelineStack: {
      gap: 12
    },
    timelineCard: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      padding: 16,
      borderRadius: 22,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    timelineBadge: {
      width: 34,
      height: 34,
      borderRadius: 17,
      backgroundColor: theme.colors.accent,
      alignItems: 'center',
      justifyContent: 'center'
    },
    ratingHero: {
      padding: 22,
      borderRadius: 28,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      gap: 10
    },
    authMethodStack: {
      gap: 12
    },
    authMethodCard: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 14,
      borderRadius: 22,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      padding: 16,
      backgroundColor: 'rgba(255,255,255,0.03)'
    },
    setupPreviewScreen: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      gap: 18
    },
    setupList: {
      width: '100%',
      gap: 10
    },
    setupRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      borderRadius: 18,
      padding: 12,
      backgroundColor: 'rgba(255,255,255,0.04)'
    },
    setupIndex: {
      width: 28,
      height: 28,
      borderRadius: 14,
      backgroundColor: theme.colors.accent,
      alignItems: 'center',
      justifyContent: 'center'
    },
    footer: {
      paddingHorizontal: 20,
      paddingBottom: 14,
      gap: 12,
      width: '100%',
      alignSelf: 'center',
      maxWidth: 560
    },
    legalRow: {
      flexDirection: 'row',
      justifyContent: 'center',
      gap: 16
    },
    ctaShell: {
      borderRadius: 24,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)'
    },
    ctaDisabled: {
      opacity: 0.46
    },
    ctaPressed: {
      transform: [{ scale: 0.992 }]
    },
    ctaGradient: {
      minHeight: 62,
      alignItems: 'center',
      justifyContent: 'center'
    },
    ctaSheen: {
      position: 'absolute',
      width: 90,
      top: -16,
      bottom: -16
    },
    touchPressed: {
      opacity: 0.84,
      transform: [{ scale: 0.992 }]
    }
  });
}

const backdropStyles = StyleSheet.create({
  atmosphere: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.18
  },
  glowOne: {
    position: 'absolute',
    width: 300,
    height: 300,
    borderRadius: 150,
    top: -80,
    right: -110
  },
  glowTwo: {
    position: 'absolute',
    width: 260,
    height: 260,
    borderRadius: 130,
    bottom: -90,
    left: -100
  },
  star: {
    position: 'absolute',
    width: 2,
    height: 2,
    borderRadius: 1,
    backgroundColor: '#FFFFFF'
  }
});
