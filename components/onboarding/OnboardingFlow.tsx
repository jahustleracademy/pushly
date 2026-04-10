import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Animated,
  Easing,
  Image,
  KeyboardAvoidingView,
  Linking,
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
  AGE_RANGE_OPTIONS,
  ATTEMPT_OPTIONS,
  DISTRACTING_APP_OPTIONS,
  EXERCISE_TYPE_OPTIONS,
  FEELING_OPTIONS,
  GOAL_OPTIONS,
  getAppOption,
  getProjectedDaysPerYear,
  REMINDER_SLOT_OPTIONS,
  getRecommendedPushUps,
  ONBOARDING_STEP_ORDER,
  PAYWALL_PLAN_OPTIONS,
  AUTH_METHOD_OPTIONS,
  PUSHLY_TRIAL_REP_TARGET
} from '@/features/onboarding/data';
import { useOnboardingFlow } from '@/features/onboarding/useOnboardingFlow';
import type { AppSelectionOption, OnboardingStepId, SelectionOption } from '@/features/onboarding/types';
import {
  PushlyCameraView,
  PushlyNative,
  type PoseFrame,
  type ScreenTimeAuthorizationStatus
} from '@/lib/native/pushly-native';
import { restorePurchases } from '@/lib/revenuecat/client';

const toneByStep: Partial<Record<(typeof ONBOARDING_STEP_ORDER)[number], 'accent' | 'danger'>> = {};

const ctaLabelByStep: Record<(typeof ONBOARDING_STEP_ORDER)[number], string> = {
  hero: 'Start',
  quizIntro: 'Weiter',
  name: 'Weiter',
  goals: 'Weiter',
  distractingApps: 'Weiter',
  scrollMinutes: 'Weiter',
  targetMinutes: 'Weiter',
  feelings: 'Weiter',
  ageRange: 'Weiter',
  attempts: 'Weiter',
  diagnosis: 'Weiter',
  reframe: 'Weiter',
  reframeGain: 'Weiter',
  mechanic: 'Weiter',
  reminderTime: 'Weiter',
  exerciseChoice: 'Weiter',
  setupBridge: 'Weiter',
  journey: 'Weiter',
  protectApps: 'Weiter',
  trust: 'Weiter',
  trustRating: 'Weiter',
  rating: 'Weiter',
  paywall: 'Weiter',
  screenTimePermission: 'Weiter',
  cameraCalibration: 'Kamera testen',
  pushUpTrial: 'Weiter',
  auth: 'Setup abschliessen',
  setupPreview: 'Schutz starten'
};

const stepLabelById: Record<(typeof ONBOARDING_STEP_ORDER)[number], string> = {
  hero: 'Start',
  quizIntro: 'Analyse',
  name: 'Profil',
  goals: 'Ziele',
  distractingApps: 'Trigger',
  scrollMinutes: 'Zeit',
  targetMinutes: 'Ziel',
  feelings: 'Gefühl',
  ageRange: 'Alter',
  attempts: 'Versuche',
  diagnosis: 'Diagnose',
  reframe: 'Reframe',
  reframeGain: 'Gewinn',
  mechanic: 'Mechanik',
  reminderTime: 'Reminder',
  exerciseChoice: 'Übung',
  setupBridge: 'Setup',
  journey: 'Journey',
  protectApps: 'Schutz',
  trust: 'Vertrauen',
  trustRating: 'Erfahrungen',
  rating: 'Erfahrungen',
  paywall: 'Zugang',
  screenTimePermission: 'Berechtigung',
  cameraCalibration: 'Kamera',
  pushUpTrial: 'Trial',
  auth: 'Login',
  setupPreview: 'Fertig'
};

const NON_QUESTION_STEPS = new Set<OnboardingStepId>([
  'hero',
  'quizIntro',
  'diagnosis',
  'reframe',
  'reframeGain',
  'mechanic',
  'screenTimePermission',
  'cameraCalibration',
  'pushUpTrial',
  'setupBridge',
  'rating',
  'journey',
  'setupPreview'
]);

export function OnboardingFlow() {
  const router = useRouter();
  const { theme } = useTheme();
  const insets = useSafeAreaInsets();
  const flow = useOnboardingFlow();
  const [isCompleting, setIsCompleting] = useState(false);
  const [isNativeBusy, setIsNativeBusy] = useState(false);
  const [isRestoreBusy, setIsRestoreBusy] = useState(false);
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

  const recommendedPushUps = getRecommendedPushUps(flow.answers);
  const projectedDaysPerYear = getProjectedDaysPerYear(flow.answers);
  const leadApp = getAppOption(flow.answers.distractingApps[0] ?? 'instagram');
  const handlePrimaryAction = async () => {
    if (!flow.canContinue || isCompleting) {
      return;
    }

    if (flow.currentStepId === 'auth') {
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

  const openLegalUrl = async (path: 'privacy.html' | 'terms.html') => {
    const url = `https://a-two.de/pushly/${path}`;
    const supported = await Linking.canOpenURL(url);
    if (!supported) {
      Alert.alert('Link nicht verfügbar', 'Bitte später erneut versuchen.');
      return;
    }
    await Linking.openURL(url);
  };

  const handleRestorePurchases = async () => {
    if (isRestoreBusy) {
      return;
    }
    setIsRestoreBusy(true);
    try {
      const restored = await restorePurchases();
      if (restored) {
        Alert.alert('Wiederhergestellt', 'Deine Käufe wurden erfolgreich wiederhergestellt.');
      } else {
        Alert.alert('Keine Käufe gefunden', 'Für diese Apple-ID wurden keine aktiven Käufe gefunden.');
      }
    } catch {
      Alert.alert('Wiederherstellung fehlgeschlagen', 'Bitte versuche es in ein paar Minuten erneut.');
    } finally {
      setIsRestoreBusy(false);
    }
  };

  const handleRequestScreenTime = async () => {
    setIsNativeBusy(true);
    setNativeMessage(null);

    try {
      const status = await PushlyNative.requestScreenTimeAuthorization();
      flow.setScreenTimeStatus(status);

      if (status !== 'approved') {
        setNativeMessage('Ohne Freigabe kann Pushly keine App-Sperre setzen.');
      }
    } catch {
      setNativeMessage('Die Freigabe konnte gerade nicht geöffnet werden. Versuch es bitte noch einmal.');
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
      setNativeMessage('Die App-Auswahl konnte gerade nicht geöffnet werden. Versuch es bitte noch einmal.');
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
      <AmbientBackdrop pulse={backdropPulse} tone={tone} theme={theme} currentStepId={flow.currentStepId} />
      <SafeAreaView style={styles.safeArea}>
        {flow.stepIndex >= 1 ? (
          <FlowHeader
            onBack={handleBackAction}
            tone={tone}
            showProgress={flow.stepIndex >= 2}
            canGoBack={!flow.isFirstStep}
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

              {flow.currentStepId === 'quizIntro' ? (
                <QuizIntroStep
                  styles={styles}
                  theme={theme}
                />
              ) : null}

              {flow.currentStepId === 'name' ? (
                <NameStep
                  styles={styles}
                  theme={theme}
                  value={flow.answers.name}
                  onChangeText={flow.updateName}
                />
              ) : null}

              {flow.currentStepId === 'goals' ? (
                <GoalStep
                  styles={styles}
                  theme={theme}
                  selectedGoal={flow.answers.goalId}
                  onSelectGoal={withSelectionHaptic(flow.selectGoal)}
                  name={flow.answers.name}
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

              {flow.currentStepId === 'targetMinutes' ? (
                <TargetMinutesStep
                  styles={styles}
                  theme={theme}
                  currentValue={flow.answers.dailyScrollMinutes}
                  targetValue={flow.answers.targetScrollMinutes}
                  onChange={flow.updateTargetMinutes}
                />
              ) : null}

              {flow.currentStepId === 'distractingApps' ? (
                <AppSelectionStep
                  styles={styles}
                  theme={theme}
                  title="Bei welchen Apps wünschst du dir Unterstützung?"
                  subtitle=""
                  options={DISTRACTING_APP_OPTIONS}
                  selectedIds={flow.answers.distractingApps}
                  onToggle={withSelectionHaptic(flow.toggleDistractingApp)}
                />
              ) : null}

              {flow.currentStepId === 'feelings' ? (
                <ListSelectionStep
                  styles={styles}
                  theme={theme}
                  title="Wie fühlst du dich, wenn du zu lange drin hängst?"
                  subtitle=""
                  options={FEELING_OPTIONS}
                  selectedIds={flow.answers.feelings}
                  onToggle={withSelectionHaptic(flow.toggleFeeling)}
                />
              ) : null}

              {flow.currentStepId === 'ageRange' ? (
                <AgeRangeStep
                  styles={styles}
                  theme={theme}
                  selectedAgeRange={flow.answers.ageRange}
                  onSelectAgeRange={withSelectionHaptic(flow.selectAgeRange)}
                />
              ) : null}

              {flow.currentStepId === 'attempts' ? (
                <ListSelectionStep
                  styles={styles}
                  theme={theme}
                  title="Was hast du schon ausprobiert?"
                  subtitle="Wähle alles, was für dich nicht dauerhaft funktioniert hat."
                  options={ATTEMPT_OPTIONS}
                  selectedIds={flow.answers.attempts}
                  onToggle={withSelectionHaptic(flow.toggleAttempt)}
                />
              ) : null}

              {flow.currentStepId === 'diagnosis' ? (
                <DiagnosisStep
                  styles={styles}
                  theme={theme}
                  dailyScrollMinutes={flow.answers.dailyScrollMinutes}
                  targetScrollMinutes={flow.answers.targetScrollMinutes}
                />
              ) : null}

              {flow.currentStepId === 'reframe' ? (
                <ReframeLossStep
                  styles={styles}
                  theme={theme}
                  currentMinutes={flow.answers.dailyScrollMinutes}
                />
              ) : null}

              {flow.currentStepId === 'reframeGain' ? (
                <ReframeGainStep
                  styles={styles}
                  theme={theme}
                  currentMinutes={flow.answers.dailyScrollMinutes}
                  targetMinutes={flow.answers.targetScrollMinutes}
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

              {flow.currentStepId === 'reminderTime' ? (
                <ReminderSlotStep
                  styles={styles}
                  theme={theme}
                  selectedSlot={flow.answers.reminderSlot}
                  onSelectSlot={withSelectionHaptic(flow.selectReminderSlot)}
                />
              ) : null}

              {flow.currentStepId === 'exerciseChoice' ? (
                <ExerciseChoiceStep
                  styles={styles}
                  theme={theme}
                  selectedExercise={flow.answers.exerciseType}
                  onSelectExercise={withSelectionHaptic(flow.selectExerciseType)}
                />
              ) : null}

              {flow.currentStepId === 'paywall' ? (
                <PaywallStep
                  styles={styles}
                  theme={theme}
                  selectedPlanId={flow.answers.planId}
                  onSelectPlan={withSelectionHaptic(flow.selectPlan)}
                  onRestore={handleRestorePurchases}
                  onOpenPrivacy={() => {
                    void openLegalUrl('privacy.html');
                  }}
                  onOpenTerms={() => {
                    void openLegalUrl('terms.html');
                  }}
                  isRestoreBusy={isRestoreBusy}
                />
              ) : null}

              {flow.currentStepId === 'screenTimePermission' ? (
                <ScreenTimePermissionStep
                  styles={styles}
                  theme={theme}
                  status={flow.answers.screenTimeStatus}
                  hasSelection={flow.answers.screenTimeSelection.hasSelection}
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
                  answers={flow.answers}
                  frame={latestPoseFrame}
                  onPoseFrame={handlePoseFrame}
                />
              ) : null}

              {flow.currentStepId === 'setupBridge' ? (
                <SetupBridgeStep
                  styles={styles}
                  theme={theme}
                  name={flow.answers.name}
                />
              ) : null}

              {flow.currentStepId === 'rating' ? (
                <RatingStep styles={styles} theme={theme} />
              ) : null}

              {flow.currentStepId === 'journey' ? (
                <JourneyStep
                  styles={styles}
                  theme={theme}
                  projectedDaysPerYear={projectedDaysPerYear}
                />
              ) : null}

              {flow.currentStepId === 'auth' ? (
                <AuthStep
                  styles={styles}
                  theme={theme}
                  selectedMethod={flow.answers.authMethod}
                  onSelectMethod={withSelectionHaptic(flow.selectAuthMethod)}
                />
              ) : null}
            </Animated.View>
          </ScrollView>

          <View style={[styles.footer, { paddingBottom: Math.max(18, insets.bottom + 10) }]}>
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
        <Text variant="title" style={styles.stepTitle}>Nicht mehr direkt in der App landen.</Text>
        <Text variant="body" style={[styles.stepBody, { color: theme.colors.textMuted, marginTop: 12 }]}>
          Pushly stoppt den ersten Impuls für einen Moment.
        </Text>
      </View>

      <View style={styles.heroVisual}>
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
          <View style={styles.heroPhoneContent}>
            <View style={styles.lockPreviewTopRow}>
              <BrandBubble option={leadApp} size="large" theme={theme} />
              <View style={styles.lockPreviewStatus}>
                <Text variant="heading">Kurz stoppen, dann bewusst öffnen</Text>
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
                  Klare Regel, klarer Ablauf.
                </Text>
              </View>
            </BlurView>
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
      <Text variant="title" style={styles.stepTitle}>Wir richten deinen Schutz jetzt gemeinsam ein.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Ein paar kurze Schritte, dann ist alles startklar.
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
        ZU DIR
      </Text>
      <Text variant="title" style={styles.stepTitle}>Wie heißt du?</Text>

      <BlurView intensity={20} tint="dark" style={styles.inputShell}>
        <Ionicons name="person-outline" size={20} color={theme.colors.accent} />
        <TextInput
          value={value}
          onChangeText={onChangeText}
          placeholder="Dein Vorname"
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

function GoalStep({
  styles,
  theme,
  selectedGoal,
  onSelectGoal,
  name
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedGoal: ReturnType<typeof useOnboardingFlow>['answers']['goalId'];
  onSelectGoal: (goalId: ReturnType<typeof useOnboardingFlow>['answers']['goalId']) => void;
  name: string;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        ZIELBILD
      </Text>
      <Text variant="title" style={styles.stepTitle}>
        {name ? `Was willst du mit Pushly erreichen, ${name}?` : 'Was willst du mit Pushly erreichen?'}
      </Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Wähle ein Hauptziel. Das hilft uns beim Setup.
      </Text>

      <View style={styles.listStack}>
        {GOAL_OPTIONS.map((goal) => (
          <Pressable
            key={goal.id}
            onPress={() => onSelectGoal(goal.id)}
            style={({ pressed }) => [
              styles.selectionRow,
              pressed && styles.touchPressed,
              selectedGoal === goal.id && {
                borderColor: theme.colors.accent,
                backgroundColor: 'rgba(186,250,32,0.1)'
              }
            ]}
          >
            <View style={[styles.selectionIconWrap, selectedGoal === goal.id && { backgroundColor: 'rgba(186,250,32,0.16)' }]}>
                <Ionicons name={goal.icon as keyof typeof Ionicons.glyphMap} size={20} color={selectedGoal === goal.id ? theme.colors.accent : theme.colors.text} />
            </View>
            <View style={styles.selectionCopy}>
              <Text variant="heading">{goal.title}</Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                {goal.subtitle}
              </Text>
            </View>
            <View style={[styles.selectionCheck, selectedGoal === goal.id && { backgroundColor: theme.colors.accent }]}>
              {selectedGoal === goal.id ? <Ionicons name="checkmark" size={14} color="#0F1208" /> : null}
            </View>
          </Pressable>
        ))}
      </View>
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
  const showSubtitle = subtitle.trim().length > 0;

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        TRIGGER-AUSWAHL
      </Text>
      <Text variant="title" style={styles.stepTitle}>{title}</Text>
      {showSubtitle ? (
        <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
          {subtitle}
        </Text>
      ) : null}

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
            <BrandBubble option={option} size="small" theme={theme} />
            <Text
              variant="body"
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.72}
              style={styles.appCardLabel}
            >
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
  const valueHours = Math.max(1, Math.min(16, Math.round(value / 60)));

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        ZEIT-CHECK
      </Text>
      <Text variant="title" style={styles.stepTitle}>Und wie viel Zeit geht dafür pro Tag drauf?</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Eine grobe Schätzung reicht völlig.
      </Text>

      <View style={styles.minutesDisplay}>
        <Text style={[styles.minutesValue, { color: theme.colors.accent }]}>{valueHours}</Text>
        <Text variant="heading" style={styles.minutesSuffix}>
          Stunden
        </Text>
      </View>

      <Slider
        minimumValue={1}
        maximumValue={16}
        step={1}
        value={valueHours}
        onValueChange={(next) => onChange(Math.round(next) * 60)}
        onSlidingComplete={() => {
          void Haptics.selectionAsync().catch(() => {});
        }}
        minimumTrackTintColor={theme.colors.accent}
        maximumTrackTintColor="rgba(255,255,255,0.16)"
        thumbTintColor="#FFFFFF"
      />
    </View>
  );
}

function TargetMinutesStep({
  styles,
  theme,
  currentValue,
  targetValue,
  onChange
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  currentValue: number;
  targetValue: number;
  onChange: (value: number) => void;
}) {
  const targetHours = Math.max(1, Math.min(16, Math.round(targetValue / 60)));

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        ZIEL-ZEIT
      </Text>
      <Text variant="title" style={styles.stepTitle}>Wie viel möchtest du stattdessen pro Tag nutzen?</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Realistisches Ziel schlagen wir am stärksten im Verhalten durch.
      </Text>

      <View style={styles.minutesDisplay}>
        <Text style={[styles.minutesValue, { color: theme.colors.accent }]}>{targetHours}</Text>
        <Text variant="heading" style={styles.minutesSuffix}>
          Stunden
        </Text>
      </View>

      <Slider
        minimumValue={1}
        maximumValue={16}
        step={1}
        value={targetHours}
        onValueChange={(next) => onChange(Math.round(next) * 60)}
        onSlidingComplete={() => {
          void Haptics.selectionAsync().catch(() => {});
        }}
        minimumTrackTintColor={theme.colors.accent}
        maximumTrackTintColor="rgba(255,255,255,0.16)"
        thumbTintColor="#FFFFFF"
      />
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
  const showSubtitle = subtitle.trim().length > 0;

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        PSYCHOLOGIE
      </Text>
      <Text variant="title" style={styles.stepTitle}>{title}</Text>
      {showSubtitle ? (
        <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
          {subtitle}
        </Text>
      ) : null}

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

function AgeRangeStep({
  styles,
  theme,
  selectedAgeRange,
  onSelectAgeRange
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedAgeRange: ReturnType<typeof useOnboardingFlow>['answers']['ageRange'];
  onSelectAgeRange: (ageRange: ReturnType<typeof useOnboardingFlow>['answers']['ageRange']) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        KURZER KONTEXT
      </Text>
      <Text variant="title" style={styles.stepTitle}>Wie alt bist du?</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Hilft uns, den Einstieg passender zu takten.
      </Text>

      <View style={styles.listStack}>
        {AGE_RANGE_OPTIONS.map((option) => {
          const selected = selectedAgeRange === option.id;
          return (
            <Pressable
              key={option.id}
              onPress={() => onSelectAgeRange(option.id)}
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
                <Ionicons name={option.icon as keyof typeof Ionicons.glyphMap} size={20} color={selected ? theme.colors.accent : theme.colors.text} />
              </View>
              <View style={styles.selectionCopy}>
                <Text variant="heading">{option.title}</Text>
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

function DiagnosisStep({
  styles,
  theme,
  dailyScrollMinutes,
  targetScrollMinutes
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  dailyScrollMinutes: number;
  targetScrollMinutes: number;
}) {
  const currentHours = Math.max(1, Math.min(16, Math.round(dailyScrollMinutes / 60)));
  const targetHours = Math.max(1, Math.min(16, Math.round(targetScrollMinutes / 60)));
  const currentAsPercentOfWakeTime = Math.round((currentHours / 16) * 100);
  const targetAsPercentOfWakeTime = Math.round((targetHours / 16) * 100);
  const yearlyHoursCurrent = currentHours * 365;
  const yearlyDaysCurrent = Math.round(yearlyHoursCurrent / 24);

  return (
    <View style={styles.standardStep}>
      <Text variant="title" style={styles.stepTitle}>Im Moment passiert bei dir noch viel automatisch.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Meta-Analysen zeigen: Mehr tägliche Screen-Time hängt mit höherem Stress und schlechterem Schlaf zusammen.
      </Text>

      <LinearGradient colors={['rgba(186,250,32,0.2)', 'rgba(186,250,32,0.04)']} style={styles.diagnosisCard}>
        <View style={styles.barComparison}>
          <ScoreBar label="Heute" value={currentAsPercentOfWakeTime} tone="accent" styles={styles} theme={theme} />
          <ScoreBar label="Dein Ziel" value={targetAsPercentOfWakeTime} tone="accent" styles={styles} theme={theme} />
        </View>

        <Text variant="heading" style={{ textAlign: 'center' }}>
          Das sind ca. {yearlyHoursCurrent.toLocaleString('de-DE')} Stunden oder {yearlyDaysCurrent} volle Tage pro Jahr.
        </Text>
      </LinearGradient>
    </View>
  );
}

function ReframeLossStep({
  styles,
  theme,
  currentMinutes
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  currentMinutes: number;
}) {
  const currentHours = Math.max(1, Math.min(16, Math.round(currentMinutes / 60)));
  const daysOnPhonePerYear = Math.round((currentHours / 16) * 365);
  const yearsLookingDown = Math.round((currentHours / 16) * 85);

  return (
    <View style={[styles.standardStep, styles.projectionScreen]}>
      <Text variant="caption" style={styles.projectionKicker}>
        WENN ALLES SO BLEIBT
      </Text>
      <Text variant="heading" style={styles.projectionLead}>
        Bei deinem aktuellen Muster:
      </Text>

      <LinearGradient
        colors={['rgba(244,177,94,0.24)', 'rgba(244,177,94,0.08)']}
        style={styles.projectionHeroWrap}
      >
        <Text style={styles.projectionHeroDanger}>{yearsLookingDown} Jahre</Text>
        <Text variant="heading" style={styles.projectionHeroSubline}>
          deines Lebens am Handy.
        </Text>
      </LinearGradient>

      <View style={styles.projectionPill}>
        <Text variant="heading" style={{ color: '#F4B15E' }}>
          {daysOnPhonePerYear} Tage
        </Text>
        <Text variant="caption" style={{ color: theme.colors.textMuted }}>
          pro Jahr am Bildschirm
        </Text>
      </View>
    </View>
  );
}

function ReframeGainStep({
  styles,
  theme,
  currentMinutes,
  targetMinutes
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  currentMinutes: number;
  targetMinutes: number;
}) {
  const currentHours = Math.max(1, Math.min(16, Math.round(currentMinutes / 60)));
  const targetHours = Math.max(1, Math.min(16, Math.round(targetMinutes / 60)));
  const yearsBack = Math.max(0, Math.round(((currentHours - targetHours) / 16) * 85));

  return (
    <View style={[styles.standardStep, styles.projectionScreen]}>
      <Text variant="caption" style={styles.projectionKicker}>
        DIE GUTE NACHRICHT
      </Text>
      <Text variant="heading" style={styles.projectionLead}>
        Mit deinem Ziel bekommst du zurück:
      </Text>

      <LinearGradient
        colors={['rgba(36,212,255,0.22)', 'rgba(36,212,255,0.06)']}
        style={styles.projectionHeroWrap}
      >
        <Text style={styles.projectionHeroAccent}>{yearsBack}+ Jahre</Text>
        <Text variant="heading" style={styles.projectionHeroSubline}>
          mehr Leben ohne Dauer-Ablenkung.
        </Text>
      </LinearGradient>

      <View style={styles.projectionPill}>
        <Text variant="heading" style={{ color: theme.colors.accent }}>
          {targetHours} Stunden
        </Text>
        <Text variant="caption" style={{ color: theme.colors.textMuted }}>
          dein neues Tagesziel
        </Text>
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
        SO FUNKTIONIERT'S
      </Text>
      <Text variant="title" style={styles.stepTitle}>Wenn der Impuls kommt, greift kurz die Sperre.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Nach deinen Reps geht die App wieder auf.
      </Text>

      <View style={styles.centerPhoneWrap}>
        <PhoneShell styles={styles} theme={theme}>
          <View style={styles.lockedAppShell}>
            <BrandBubble option={app} size="large" theme={theme} />
            <Text variant="heading" style={{ textAlign: 'center' }}>
              {app.label} ist gerade gesperrt
            </Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
              Zum Entsperren: {pushUps} Reps.
            </Text>

          </View>
        </PhoneShell>
      </View>
    </View>
  );
}

function ReminderSlotStep({
  styles,
  theme,
  selectedSlot,
  onSelectSlot
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedSlot: ReturnType<typeof useOnboardingFlow>['answers']['reminderSlot'];
  onSelectSlot: (slot: ReturnType<typeof useOnboardingFlow>['answers']['reminderSlot']) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        REMINDER
      </Text>
      <Text variant="title" style={styles.stepTitle}>Wann sollen wir dich am besten erinnern?</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Erinnerungen erhöhen die Chance, dass neue Gewohnheiten halten.
      </Text>

      <View style={styles.listStack}>
        {REMINDER_SLOT_OPTIONS.map((slot) => {
          const selected = selectedSlot === slot.id;
          return (
            <Pressable
              key={slot.id}
              onPress={() => onSelectSlot(slot.id)}
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
                <Ionicons name={slot.icon as keyof typeof Ionicons.glyphMap} size={20} color={selected ? theme.colors.accent : theme.colors.text} />
              </View>
              <View style={styles.selectionCopy}>
                <Text variant="heading">{slot.title}</Text>
                <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                  {slot.subtitle}
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

function ExerciseChoiceStep({
  styles,
  theme,
  selectedExercise,
  onSelectExercise
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedExercise: ReturnType<typeof useOnboardingFlow>['answers']['exerciseType'];
  onSelectExercise: (exerciseType: ReturnType<typeof useOnboardingFlow>['answers']['exerciseType']) => void;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        EXERCISE WAHL
      </Text>
      <Text variant="title" style={styles.stepTitle}>Welche Übung passt für deinen Start?</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Du kannst das später jederzeit ändern.
      </Text>

      <View style={styles.listStack}>
        {EXERCISE_TYPE_OPTIONS.map((option) => {
          const selected = selectedExercise === option.id;
          return (
            <Pressable
              key={option.id}
              onPress={() => onSelectExercise(option.id)}
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
                <Ionicons name={option.icon as keyof typeof Ionicons.glyphMap} size={20} color={selected ? theme.colors.accent : theme.colors.text} />
              </View>
              <View style={styles.selectionCopy}>
                <Text variant="heading">{option.title}</Text>
                <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                  {option.subtitle}
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

function ScreenTimePermissionStep({
  styles,
  theme,
  status,
  hasSelection,
  isBusy,
  message,
  onAuthorize,
  onChooseApps
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  status: ScreenTimeAuthorizationStatus;
  hasSelection: boolean;
  isBusy: boolean;
  message: string | null;
  onAuthorize: () => Promise<void>;
  onChooseApps: () => Promise<void>;
}) {
  const approved = status === 'approved';

  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        SYSTEMFREIGABE
      </Text>
      <Text variant="title" style={styles.stepTitle}>Aktiviere jetzt den Schutz auf deinem iPhone.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Einmal freigeben, dann greift der Schutz zuverlässig.
      </Text>

      <View style={styles.centerPhoneWrap}>
        <PhoneShell styles={styles} theme={theme}>
          <View style={styles.permissionScreen}>
            <Image
              source={require('../../assets/onboarding/permission-orb.png')}
              style={styles.permissionOrb}
              resizeMode="contain"
            />
            <Text variant="heading" style={{ textAlign: 'center' }}>
              Freigabe erteilen
            </Text>
            <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
              Danach wählst du die Apps, die geschützt werden sollen.
            </Text>

            <View style={styles.permissionButtonStack}>
              <InlineActionButton
                label={approved ? 'Freigabe aktiv' : 'Screen Time freigeben'}
                onPress={onAuthorize}
                disabled={approved || isBusy}
                styles={styles}
                theme={theme}
              />
              {approved ? (
                <InlineActionButton
                  label="Apps auswählen"
                  onPress={onChooseApps}
                  disabled={isBusy}
                  styles={styles}
                  theme={theme}
                  variant="secondary"
                />
              ) : null}
            </View>

            {approved ? (
              <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
                {hasSelection ? 'Auswahl erledigt.' : 'Auswahl noch offen.'}
              </Text>
            ) : null}
          </View>
        </PhoneShell>
      </View>

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
            Verbindung wird eingerichtet ...
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
        KAMERA-CHECK
      </Text>
      <Text variant="title" style={styles.stepTitle}>Richte die Kamera einmal kurz ein.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        So werden Reps stabil erkannt.
      </Text>

      <View style={styles.tipStack}>
        <TipCard
          title="Gut sichtbar im Bild"
          body="Am besten von Kopf bis Hüfte."
          icon="scan-outline"
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

      <StatPill label="Erkennung" value={poseEngineReady ? 'bereit' : 'wird vorbereitet ...'} theme={theme} styles={styles} />
    </View>
  );
}

function PushUpTrialStep({
  styles,
  theme,
  answers,
  frame,
  onPoseFrame
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
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
        Optionaler Kurztest: 1 bis {PUSHLY_TRIAL_REP_TARGET} Reps.
      </Text>
      <Text variant="caption" style={styles.subtleCopy}>
        Wenn du magst, teste kurz. Du kannst auch direkt weiter.
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
              <Text variant="caption" numberOfLines={1} style={styles.cameraDebugWarningBody}>
                {mediaPipeWarning}
              </Text>
            </View>
          ) : null}
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            st:{debug?.repStateMachineState ?? debug?.state ?? frame?.state ?? answers.pushUpState} | rep:{debug?.repCount ?? answers.pushUpRepCount} | f:{debug?.frameIndex ?? '-'} t:{formatDebugNumber(debug?.timestampSeconds)}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            why:{debug?.whyRepDidNotCount ?? '-'} | fail/succ:{debug?.lastFailedGate ?? '-'}/{debug?.lastSuccessfulGate ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            v1 t/d/b/a/tr/c/r:{debug?.topReady ? '1' : '0'}/{debug?.descendingStarted ? '1' : '0'}/{debug?.bottomLatched ? '1' : '0'}/{debug?.ascendingStarted ? '1' : '0'}/{debug?.topRecovered ? '1' : '0'}/{debug?.repCommitted ? '1' : '0'}/{debug?.rearmReady ? '1' : '0'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            reset:{debug?.resetReason ?? '-'} | block:{debug?.commitBlockedBy ?? '-'} | abort:{debug?.timeoutOrAbortReason ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            gates b/q/l/m/b/a/t/r/c:{debug?.bodyFound ? '1' : '0'}/{debug?.trackingQualityPass ? '1' : '0'}/{debug?.logicQualityPass ? '1' : '0'}/{debug?.motionTravelGate ? '1' : '0'}/{debug?.bottomGate ? '1' : '0'}/{debug?.ascentGate ? '1' : '0'}/{debug?.topRecoveryGate ? '1' : '0'}/{debug?.rearmGate ? '1' : '0'}/{debug?.countCommitReady ? '1' : '0'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            ph d/bc/bf/a/tr:{debug?.descendingFrames ?? 0}/{debug?.bottomCandidateFrames ?? debug?.bottomFrames ?? 0}/{debug?.bottomConfirmedFrames ?? 0}/{debug?.ascendingFrames ?? 0}/{debug?.topRecoveryFrames ?? 0}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            min d/b/a/tr:{debug?.minDescendingFramesRequired ?? 0}/{debug?.minBottomFramesRequired ?? 0}/{debug?.minAscendingFramesRequired ?? 0}/{debug?.minTopRecoveryFramesRequired ?? 0} | nearBottom:{debug?.bottomNearMiss ? '1' : '0'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            raw y s/t:{formatDebugNumber(debug?.rawShoulderY)}/{formatDebugNumber(debug?.rawTorsoY)} | sm y s/t:{formatDebugNumber(debug?.smoothedShoulderY)}/{formatDebugNumber(debug?.smoothedTorsoY)}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            raw v s/t:{formatDebugNumber(debug?.rawShoulderVelocity)}/{formatDebugNumber(debug?.rawTorsoVelocity)} | sm v s/t:{formatDebugNumber(debug?.smoothedShoulderVelocity)}/{formatDebugNumber(debug?.smoothedTorsoVelocity)}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            travel t/s d:{formatDebugNumber(debug?.torsoDownTravel)}/{formatDebugNumber(debug?.shoulderDownTravel)} r:{formatDebugNumber(debug?.torsoRecoveryToTop)}/{formatDebugNumber(debug?.shoulderRecoveryToTop)}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            lm weakest:{debug?.weakestLandmark ?? '-'} | rearm p/f/prog:{debug?.repRearmPending ? '1' : '0'}/{debug?.framesUntilRearm ?? 0}/{formatDebugNumber(debug?.rearmConfirmProgress)} ({debug?.rearmBlockedReason ?? '-'})
          </Text>
          {/* Bottom/fallback stability line: hold/reacquire/grace + anchor support diagnostics. */}
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            bottom hold/reacq/gr:{debug?.bottomHoldActive ? '1' : '0'}/{debug?.bottomReacquireState ?? '-'}/{debug?.trackingLossGraceFramesRemaining ?? 0} | sup:{(debug?.bottomSupportAnchors ?? []).join('+') || '-'} | blk:{debug?.bottomBlockedReason ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            sess att/ok:{debug?.repsAttemptedEstimate ?? 0}/{debug?.repsCommitted ?? 0} | blk b/t/r/trk/trv/q:{debug?.repsBlockedByBottom ?? 0}/{debug?.repsBlockedByTopRecovery ?? 0}/{debug?.repsBlockedByRearm ?? 0}/{debug?.repsBlockedByTrackingLoss ?? 0}/{debug?.repsBlockedByTravel ?? 0}/{debug?.repsBlockedByQuality ?? 0}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            block:{repBlockedReasons.length > 0 ? repBlockedReasons.join(', ') : '-'} | trans:{debug?.repStateTransitionEvent ?? debug?.stateTransitionEvent ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            q track/logic:{formatDebugNumber(debug?.trackingQuality ?? frame?.trackingQuality)}/{formatDebugNumber(debug?.logicQuality ?? frame?.logicQuality)} | cov/wrist:{formatDebugNumber(debug?.upperBodyCoverage ?? frame?.upperBodyCoverage)}/{formatDebugNumber(debug?.wristRetention ?? frame?.wristRetention)}
          </Text>
          {/* Vision fallback stability line: anchor coverage/strength + weakest required landmark + hysteresis state. */}
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            fb cov/anch:{formatDebugNumber(debug?.fallbackCoverage?.requiredAnchors)}/{formatDebugNumber(debug?.fallbackAnchorStrength)} | weakReq:{debug?.weakestRequiredLandmark ?? '-'} ({formatDebugNumber(debug?.weakestRequiredLandmarkConfidence)}) | hyst:{debug?.visibilityHysteresisState?.requiredVisibleCount ?? '-'}/{debug?.visibilityHysteresisState?.requiredTotal ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            backend req/act:{debug?.requestedBackend ?? frame?.requestedBackend ?? '-'} / {debug?.activeBackend ?? frame?.activeBackend ?? frame?.poseBackend ?? '-'} | fb a/u:{(debug?.fallbackAllowed ?? frame?.fallbackAllowed) ? '1' : '0'}/{(debug?.fallbackUsed ?? frame?.fallbackUsed) ? '1' : '0'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            mp avail:{(debug?.mediapipeAvailable ?? frame?.mediapipeAvailable) ? 'yes' : 'no'} | reason:{mediapipeInitReason ?? debug?.fallbackReason ?? frame?.fallbackReason ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            mp build/model:{typeof compiledWithMediaPipe === 'boolean' ? (compiledWithMediaPipe ? 'yes' : 'no') : '-'} / {typeof poseModelFound === 'boolean' ? (poseModelFound ? 'yes' : 'no') : '-'} ({poseModelName ?? '-'})
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            modelPath:{poseModelPath ?? '-'}
          </Text>
          <Text variant="caption" numberOfLines={1} style={styles.cameraDebugLine}>
            initStatus:{poseLandmarkerInitStatus ?? '-'}
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

function SetupBridgeStep({
  styles,
  theme,
  name
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  name: string;
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        FAST FERTIG
      </Text>
      <Text variant="title" style={styles.stepTitle}>
        {name ? `${name}, jetzt setzen wir den Schutz live.` : 'Jetzt setzen wir den Schutz live.'}
      </Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Noch ein kurzer Check, dann ist dein Onboarding abgeschlossen.
      </Text>

      <BlurView intensity={18} tint="dark" style={styles.ratingHero}>
        <Text variant="heading" style={{ textAlign: 'center' }}>
          Dein Plan wird auf Basis deiner Antworten vorbereitet.
        </Text>
        <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
          Erst Reps, dann bewusster Zugriff.
        </Text>
      </BlurView>
    </View>
  );
}

function RatingStep({
  styles,
  theme
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <View style={[styles.standardStep, styles.ratingImpactScreen]}>
      <Image
        source={require('../../assets/onboarding/rating-stars.png')}
        style={styles.ratingStarsImage}
        resizeMode="contain"
      />

      <View style={styles.ratingImpactBlock}>
        <Text variant="title" style={styles.ratingImpactTitle}>
          Wir wissen:
        </Text>
        <Text variant="title" style={[styles.ratingImpactTitle, styles.ratingImpactWarm]}>
          Aufhören ist hart.
        </Text>
      </View>

      <View style={styles.ratingImpactBlock}>
        <Text variant="heading" style={styles.ratingImpactBody}>
          Wissenschaft ist klar:
        </Text>
        <Text variant="heading" style={[styles.ratingImpactBody, styles.ratingImpactCool]}>
          Ersetzen wirkt besser als Verzicht.
        </Text>
      </View>

      <View style={styles.ratingImpactBlock}>
        <Text variant="heading" style={styles.ratingImpactBody}>
          Genau deshalb ersetzt Pushly
        </Text>
        <Text variant="heading" style={[styles.ratingImpactBody, styles.ratingImpactCool]}>
          Scrollen durch Bewegung.
        </Text>
      </View>

      <Text variant="caption" style={styles.ratingImpactFootnote}>
        Basierend auf Behavioral-Science zu Habit-Replacement und Reizunterbrechung.
      </Text>
    </View>
  );
}

function JourneyStep({
  styles,
  theme,
  projectedDaysPerYear
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  projectedDaysPerYear: number;
}) {
  const painPoints = [
    {
      title: 'Zeitverlust im Alltag',
      body: 'Viele kurze Checks fühlen sich harmlos an, kosten dich am Ende aber richtig viel Zeit.'
    },
    {
      title: 'Fokus-Brüche',
      body: 'Jeder Impuls-Klick reißt dich raus, egal ob bei Arbeit, Training oder im Gespräch.'
    },
    {
      title: 'Weniger Kontrolle',
      body: 'Wenn alles automatisch passiert, fühlt es sich irgendwann nicht mehr nach deiner Entscheidung an.'
    }
  ];

  return (
    <View style={[styles.standardStep, styles.journeyScreen]}>
      <Text variant="caption" style={styles.eyebrow}>
        7-TAGE JOURNEY
      </Text>
      <Text variant="title" style={styles.stepTitle}>Dein Einstieg startet jetzt.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Lass uns einmal ehrlich draufschauen, was dich das aktuell kostet.
      </Text>

      <BlurView intensity={20} tint="dark" style={styles.journeyPainHero}>
        <Text variant="caption" style={styles.journeyPainHeroLabel}>
          WAS DICH DAS JETZT KOSTET
        </Text>
        <Text variant="title" style={styles.journeyPainHeroValue}>
          {projectedDaysPerYear}
        </Text>
        <Text variant="heading" style={styles.journeyPainHeroUnit}>
          Tage im Jahr am Handy
        </Text>
        <Text variant="caption" style={styles.journeyPainHeroFootnote}>
          Wenn alles so bleibt wie jetzt, ist das dein Standard.
        </Text>
      </BlurView>

      <View style={styles.journeyPainStack}>
        {painPoints.map((item) => (
          <BlurView key={item.title} intensity={16} tint="dark" style={styles.painPointCard}>
            <View style={styles.painPointIconWrap}>
              <Ionicons name="warning" size={14} color="#2B130E" />
            </View>
            <View style={{ flex: 1, gap: 2 }}>
              <Text variant="heading">{item.title}</Text>
              <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                {item.body}
              </Text>
            </View>
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
      <Text variant="title" style={styles.stepTitle}>Willst du deinen Fortschritt sichern?</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Such dir einfach eine Option aus. Danach fehlt nur noch ein letzter Tap.
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

function TrustRatingStep({
  styles,
  theme
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
}) {
  return (
    <View style={styles.standardStep}>
      <Text variant="caption" style={styles.eyebrow}>
        ERFAHRUNGEN
      </Text>
      <Text variant="title" style={styles.stepTitle}>Du bist damit nicht allein.</Text>
      <Text variant="body" style={[styles.subtleCopy, styles.stepBody]}>
        Die Regel hilft, den ersten Impuls zu stoppen.
      </Text>

      <BlurView intensity={20} tint="dark" style={styles.ratingHero}>
        <Text variant="heading" style={{ textAlign: 'center' }}>
          Rückmeldungen aus der Beta: 4,8 / 5
        </Text>
      </BlurView>

    </View>
  );
}

function PaywallStep({
  styles,
  theme,
  selectedPlanId,
  onSelectPlan,
  onRestore,
  onOpenPrivacy,
  onOpenTerms,
  isRestoreBusy
}: {
  styles: ReturnType<typeof createStyles>;
  theme: ReturnType<typeof useTheme>['theme'];
  selectedPlanId: 'yearly' | 'monthly';
  onSelectPlan: (id: 'yearly' | 'monthly') => void;
  onRestore: () => Promise<void>;
  onOpenPrivacy: () => void;
  onOpenTerms: () => void;
  isRestoreBusy: boolean;
}) {
  return (
    <View style={styles.standardStep}>
      <View style={styles.paywallTopLinks}>
        <Pressable onPress={onOpenPrivacy}>
          <Text variant="caption" style={styles.paywallLinkText}>Privacy</Text>
        </Pressable>
        <Pressable onPress={onRestore} disabled={isRestoreBusy}>
          <Text variant="caption" style={styles.paywallLinkText}>
            {isRestoreBusy ? 'Restoring ...' : 'Restore'}
          </Text>
        </Pressable>
        <Pressable onPress={onOpenTerms}>
          <Text variant="caption" style={styles.paywallLinkText}>Terms</Text>
        </Pressable>
      </View>

      <View style={styles.paywallHero}>
        <View style={styles.paywallHeroApps}>
          {[getAppOption('instagram'), getAppOption('tiktok'), getAppOption('youtube')].map((app) => (
            <View key={app.id} style={styles.paywallHeroAppBubble}>
              <BrandBubble option={app} size="medium" theme={theme} />
              <Ionicons name="lock-closed" size={12} color={theme.colors.accent} style={styles.paywallHeroLock} />
            </View>
          ))}
        </View>
        <Text variant="title" style={styles.stepTitle}>Choose your plan</Text>
        <BlurView intensity={18} tint="dark" style={styles.paywallQuoteCard}>
          <Text variant="heading" style={styles.paywallStars}>★★★★★</Text>
          <Text variant="caption" style={{ color: theme.colors.textMuted, textAlign: 'center' }}>
            „Pushly fühlt sich nicht nach Strafe an, sondern wie ein Coach.“
          </Text>
        </BlurView>
      </View>

      <View style={styles.planStack}>
        {PAYWALL_PLAN_OPTIONS.map((plan) => {
          const selected = selectedPlanId === plan.id;
          const planLengthLabel = plan.id === 'yearly' ? '12 Monate' : '1 Monat';
          const billingCycleLabel = plan.id === 'yearly' ? 'jährlich berechnet' : 'monatlich berechnet';

          return (
            <Pressable
              key={plan.id}
              onPress={() => onSelectPlan(plan.id)}
              style={({ pressed }) => [
                styles.planCard,
                pressed && styles.touchPressed,
                selected && {
                  borderColor: theme.colors.accent,
                  backgroundColor: 'rgba(186,250,32,0.12)'
                }
              ]}
            >
              {plan.badge ? (
                <LinearGradient colors={[theme.colors.accent, theme.colors.accentSoft]} style={styles.planBadge}>
                  <Text variant="caption" style={{ color: '#0F1208' }}>
                    {plan.badge}
                  </Text>
                </LinearGradient>
              ) : (
                <View style={styles.planBadgePlaceholder} />
              )}

              <View style={styles.planRow}>
                <View style={styles.planCopy}>
                  <Text variant="heading">{plan.title}</Text>
                  <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                    {`${planLengthLabel} · ${plan.price}`}
                  </Text>
                </View>

                <View style={styles.planPriceBlock}>
                  <Text variant="heading">{plan.monthlyEquivalent.replace('/ Monat', '/ mo')}</Text>
                  <Text variant="caption" style={{ color: theme.colors.textMuted }}>
                    {billingCycleLabel}
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
      <Text variant="caption" style={styles.paywallLegalNote}>
        Zahlung über deinen App Store Account. Auto-renewing subscription, jederzeit kündbar.
      </Text>
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
      <Text variant="title">Dein Schutz ist eingerichtet.</Text>
      <Text variant="body" style={styles.subtleCopy}>
        Perfekt. Du kannst jetzt direkt loslegen.
      </Text>

      <PhoneShell styles={styles} theme={theme}>
        <View style={styles.setupPreviewScreen}>
          <BrandBubble option={app} size="medium" theme={theme} />
          <Text variant="heading">Erste Schutz-App: {app.label}</Text>
          <View style={styles.permissionStatusRow}>
            <StatusChip
              label="Schutz"
              value={answers.shieldStatus === 'active' ? 'aktiv' : 'bereit'}
              tone="accent"
              styles={styles}
              theme={theme}
            />
          </View>
        </View>
      </PhoneShell>
    </View>
  );
}

function FlowHeader({
  onBack,
  tone,
  showProgress,
  canGoBack,
  stepIndex,
  stepCount
}: {
  onBack: () => void;
  tone: 'accent' | 'danger';
  showProgress: boolean;
  canGoBack: boolean;
  stepIndex: number;
  stepCount: number;
}) {
  const { theme } = useTheme();
  const styles = createStyles(theme);

  return (
    <View style={styles.header}>
      <Image source={require('../../assets/images/logo_header.png')} style={styles.headerLogo} resizeMode="contain" />

      <View style={styles.headerRow}>
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
            <View style={styles.segmentedTrack}>
              {Array.from({ length: Math.max(stepCount, 1) }).map((_, index) => {
                const maxIndex = Math.max(0, stepCount - 1);
                const activeIndex = Math.max(0, Math.min(stepIndex, maxIndex));
                const isActive = index === activeIndex;

                return (
                  <View
                    key={`segment-${index}`}
                    style={[
                      styles.segmentedStep,
                      isActive && {
                        backgroundColor: tone === 'danger' ? theme.colors.danger : theme.colors.accent
                      }
                    ]}
                  />
                );
              })}
            </View>
          </View>
        ) : (
          <View style={styles.headerHeroLabel} />
        )}

        {!showProgress ? <View style={styles.headerSpacer} /> : null}
      </View>
    </View>
  );
}

function AmbientBackdrop({
  pulse,
  tone,
  theme,
  currentStepId
}: {
  pulse: Animated.Value;
  tone: 'accent' | 'danger';
  theme: ReturnType<typeof useTheme>['theme'];
  currentStepId: OnboardingStepId;
}) {
  const isNonQuestionStep = NON_QUESTION_STEPS.has(currentStepId);
  const atmosphereOpacity =
    currentStepId === 'quizIntro' ||
    currentStepId === 'diagnosis' ||
    currentStepId === 'reframe' ||
    currentStepId === 'reframeGain'
      ? 0.3
      : 0.6;
  const backgroundSource = isNonQuestionStep
    ? require('../../assets/onboarding/onboarding_full_green.png')
    : require('../../assets/onboarding/onboarding_corner_green.png');

  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, backdropStyles.container]}>
      <View
        style={[
          backdropStyles.baseFill,
          { backgroundColor: '#060706' }
        ]}
      />
      <Image
        source={backgroundSource}
        style={[backdropStyles.atmosphere, { opacity: atmosphereOpacity }]}
        resizeMode="cover"
      />
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
  const glyphMap = (FontAwesome6 as unknown as { glyphMap?: Record<string, number> }).glyphMap ?? {};
  const hasFontAwesomeGlyph = Object.prototype.hasOwnProperty.call(glyphMap, option.iconName);

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
      {hasFontAwesomeGlyph ? (
        <FontAwesome6
          name={option.iconName as any}
          iconStyle={option.iconStyle === 'brand' ? 'brand' : 'solid'}
          size={iconSize}
          color={option.brandColor ?? theme.colors.text}
        />
      ) : (
        <Ionicons
          name="apps-outline"
          size={iconSize}
          color={theme.colors.text}
        />
      )}
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
      paddingTop: 2,
      paddingBottom: 8,
      gap: 8
    },
    headerLogo: {
      width: 158,
      height: 48,
      alignSelf: 'center'
    },
    headerRow: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 20,
      gap: 12
    },
    headerCenter: {
      flex: 1
    },
    headerHeroLabel: {
      flex: 1
    },
    backButton: {
      width: 36,
      height: 36,
      borderRadius: 18,
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: 'rgba(255,255,255,0.04)'
    },
    segmentedTrack: {
      flex: 1,
      height: 8,
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6
    },
    segmentedStep: {
      flex: 1,
      height: 8,
      borderRadius: 999,
      backgroundColor: 'rgba(255,255,255,0.42)'
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
      paddingTop: 18,
      alignItems: 'center'
    },
    heroLogo: {
      width: 170,
      height: 52
    },
    titleBlock: {
      gap: 4,
      maxWidth: 500,
      alignItems: 'center'
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
      alignItems: 'center'
    },
    heroPhoneContent: {
      flex: 1,
      width: '100%',
      justifyContent: 'center',
      alignItems: 'center',
      gap: 14
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
      paddingTop: 8,
      width: '100%',
      alignSelf: 'center'
    },
    stepTitle: {
      textAlign: 'center'
    },
    stepBody: {
      textAlign: 'center',
      maxWidth: 500,
      alignSelf: 'center'
    },
    eyebrow: {
      color: theme.colors.accent,
      fontFamily: theme.typography.bold,
      letterSpacing: 1.2,
      textAlign: 'center',
      display: 'none'
    },
    subtleCopy: {
      color: theme.colors.textMuted,
      marginTop: -8,
      textAlign: 'center'
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
      width: '100%',
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
      alignItems: 'center',
      width: '100%'
    },
    appGrid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 10,
      justifyContent: 'center',
      width: '100%'
    },
    appCard: {
      width: '48%',
      minHeight: 82,
      borderRadius: 22,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      backgroundColor: 'rgba(255,255,255,0.03)',
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 8,
      paddingHorizontal: 12
    },
    appCardLabel: {
      flex: 1,
      textAlign: 'left',
      fontFamily: theme.typography.bold,
      fontSize: 18,
      lineHeight: 20
    },
    helperCard: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      padding: 14,
      width: '100%',
      borderRadius: 18,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.06)'
    },
    minutesDisplay: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      gap: 10,
      justifyContent: 'center'
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
      gap: 12,
      width: '100%'
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
      width: '100%',
      borderRadius: 28,
      gap: 18,
      borderWidth: 1,
      borderColor: 'rgba(186,250,32,0.24)',
      backgroundColor: 'rgba(186,250,32,0.05)'
    },
    barComparison: {
      flexDirection: 'row',
      justifyContent: 'center',
      alignItems: 'flex-end',
      gap: 28
    },
    scoreColumn: {
      width: 110,
      alignItems: 'center',
      gap: 12
    },
    scoreTrack: {
      width: 86,
      height: 188,
      borderRadius: 20,
      backgroundColor: 'rgba(255,255,255,0.08)',
      justifyContent: 'flex-end',
      overflow: 'hidden',
      padding: 8
    },
    scoreFill: {
      width: '100%',
      borderRadius: 14,
      alignItems: 'center',
      justifyContent: 'flex-start',
      paddingTop: 8
    },
    metricGrid: {
      gap: 12,
      width: '100%'
    },
    projectionBlock: {
      width: '100%',
      alignItems: 'center',
      gap: 8
    },
    projectionScreen: {
      flex: 1,
      justifyContent: 'center',
      gap: 16,
      paddingVertical: 8
    },
    projectionKicker: {
      color: theme.colors.textMuted,
      textAlign: 'center',
      letterSpacing: 1.3,
      fontFamily: theme.typography.bold
    },
    projectionLead: {
      textAlign: 'center',
      maxWidth: 420,
      alignSelf: 'center'
    },
    projectionHeroWrap: {
      width: '100%',
      borderRadius: 30,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.16)',
      backgroundColor: 'rgba(8,10,14,0.5)',
      paddingVertical: 26,
      paddingHorizontal: 20,
      alignItems: 'center',
      gap: 8,
      shadowColor: '#000000',
      shadowOpacity: 0.25,
      shadowRadius: 22,
      shadowOffset: { width: 0, height: 12 },
      elevation: 8
    },
    projectionHeroDanger: {
      fontFamily: theme.typography.heavy,
      fontSize: 80,
      lineHeight: 82,
      letterSpacing: -2.5,
      color: '#F4B15E',
      textAlign: 'center'
    },
    projectionHeroAccent: {
      fontFamily: theme.typography.heavy,
      fontSize: 80,
      lineHeight: 82,
      letterSpacing: -2.5,
      color: '#24D4FF',
      textAlign: 'center'
    },
    projectionHeroSubline: {
      textAlign: 'center',
      color: theme.colors.text
    },
    projectionPill: {
      alignSelf: 'center',
      borderRadius: 999,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.18)',
      backgroundColor: 'rgba(255,255,255,0.06)',
      paddingHorizontal: 18,
      paddingVertical: 11,
      alignItems: 'center',
      gap: 2,
      shadowColor: '#000000',
      shadowOpacity: 0.16,
      shadowRadius: 10,
      shadowOffset: { width: 0, height: 5 },
      elevation: 3
    },
    projectionHeadline: {
      textAlign: 'center'
    },
    projectionIntro: {
      color: theme.colors.textMuted,
      textAlign: 'center'
    },
    projectionValueDanger: {
      fontFamily: theme.typography.heavy,
      fontSize: 68,
      lineHeight: 68,
      letterSpacing: -2,
      color: theme.colors.danger
    },
    projectionValueAccent: {
      fontFamily: theme.typography.heavy,
      fontSize: 62,
      lineHeight: 62,
      letterSpacing: -2,
      color: theme.colors.accent
    },
    projectionBody: {
      color: theme.colors.textMuted,
      textAlign: 'center',
      maxWidth: 360,
      alignSelf: 'center'
    },
    projectionFootnote: {
      color: theme.colors.textMuted,
      textAlign: 'center',
      marginTop: 2
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
    centerPhoneWrap: {
      width: '100%',
      alignItems: 'center'
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
      gap: 12,
      width: '100%'
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
    paywallTopLinks: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      width: '100%',
      paddingHorizontal: 6
    },
    paywallLinkText: {
      color: theme.colors.textMuted
    },
    paywallHero: {
      width: '100%',
      alignItems: 'center',
      gap: 12
    },
    paywallHeroApps: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 12
    },
    paywallHeroAppBubble: {
      position: 'relative'
    },
    paywallHeroLock: {
      position: 'absolute',
      right: -3,
      bottom: -2
    },
    paywallQuoteCard: {
      width: '100%',
      borderRadius: 22,
      paddingHorizontal: 16,
      paddingVertical: 14,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      alignItems: 'center',
      gap: 8,
      overflow: 'hidden'
    },
    paywallStars: {
      color: theme.colors.accent
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
      gap: 12,
      width: '100%'
    },
    planCard: {
      position: 'relative',
      borderRadius: 26,
      borderWidth: 1.4,
      borderColor: 'rgba(255,255,255,0.14)',
      backgroundColor: 'rgba(10,14,8,0.55)',
      padding: 18,
      gap: 12,
      minHeight: 132
    },
    planBadge: {
      alignSelf: 'flex-start',
      borderRadius: 999,
      paddingHorizontal: 12,
      paddingVertical: 6
    },
    planBadgePlaceholder: {
      height: 28
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
      width: 28,
      height: 28,
      borderRadius: 14,
      borderWidth: 2,
      borderColor: 'rgba(255,255,255,0.22)',
      alignItems: 'center',
      justifyContent: 'center'
    },
    paywallLegalNote: {
      color: theme.colors.textMuted,
      textAlign: 'center',
      width: '100%'
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
      gap: 10,
      justifyContent: 'center'
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
      paddingHorizontal: 8,
      paddingVertical: 6,
      gap: 1
    },
    cameraDebugHeading: {
      color: theme.colors.accent,
      fontSize: 10,
      lineHeight: 12,
      marginBottom: 2
    },
    cameraDebugLine: {
      color: theme.colors.textMuted,
      fontSize: 10,
      lineHeight: 12
    },
    cameraDebugWarning: {
      borderRadius: 10,
      borderWidth: 1,
      borderColor: 'rgba(255,109,91,0.55)',
      backgroundColor: 'rgba(76,18,14,0.55)',
      paddingHorizontal: 8,
      paddingVertical: 6,
      marginBottom: 3
    },
    cameraDebugWarningTitle: {
      color: '#FFB3A9',
      fontSize: 10,
      lineHeight: 12
    },
    cameraDebugWarningBody: {
      color: '#FFD6D0',
      fontSize: 10,
      lineHeight: 12
    },
    journeyScreen: {
      gap: 14
    },
    journeyPainHero: {
      width: '100%',
      borderRadius: 28,
      borderWidth: 1,
      borderColor: 'rgba(255,109,91,0.3)',
      backgroundColor: 'rgba(70,18,12,0.28)',
      paddingVertical: 20,
      paddingHorizontal: 18,
      alignItems: 'center',
      gap: 6,
      overflow: 'hidden'
    },
    journeyPainHeroLabel: {
      color: '#FFB3A9',
      textAlign: 'center',
      letterSpacing: 1.1,
      fontFamily: theme.typography.bold
    },
    journeyPainHeroValue: {
      color: theme.colors.danger,
      fontFamily: theme.typography.heavy,
      fontSize: 72,
      lineHeight: 74,
      letterSpacing: -2.2,
      textAlign: 'center'
    },
    journeyPainHeroUnit: {
      textAlign: 'center'
    },
    journeyPainHeroFootnote: {
      color: theme.colors.textMuted,
      textAlign: 'center'
    },
    journeyPainStack: {
      width: '100%',
      gap: 10
    },
    painPointCard: {
      flexDirection: 'row',
      alignItems: 'flex-start',
      gap: 10,
      padding: 14,
      borderRadius: 20,
      borderWidth: 1,
      borderColor: 'rgba(255,109,91,0.22)',
      overflow: 'hidden'
    },
    painPointIconWrap: {
      width: 22,
      height: 22,
      borderRadius: 11,
      backgroundColor: '#FF8A75',
      alignItems: 'center',
      justifyContent: 'center',
      marginTop: 1
    },
    ratingHero: {
      padding: 22,
      width: '100%',
      borderRadius: 28,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.08)',
      gap: 10
    },
    ratingImpactScreen: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      gap: 28,
      paddingVertical: 10
    },
    ratingStarsImage: {
      width: 180,
      height: 46
    },
    ratingImpactStars: {
      color: theme.colors.accent,
      letterSpacing: 2.5,
      fontFamily: theme.typography.bold
    },
    ratingImpactBlock: {
      width: '100%',
      alignItems: 'center',
      gap: 2
    },
    ratingImpactTitle: {
      textAlign: 'center',
      fontSize: 38,
      lineHeight: 40,
      letterSpacing: -0.8
    },
    ratingImpactBody: {
      textAlign: 'center',
      maxWidth: 440,
      alignSelf: 'center',
      fontSize: 28,
      lineHeight: 30,
      letterSpacing: -0.5
    },
    ratingImpactWarm: {
      color: theme.colors.accent
    },
    ratingImpactCool: {
      color: theme.colors.accentSoft
    },
    ratingImpactFootnote: {
      color: theme.colors.textMuted,
      textAlign: 'center',
      maxWidth: 460,
      marginTop: 8
    },
    authMethodStack: {
      gap: 12,
      width: '100%'
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
  container: {
    overflow: 'hidden'
  },
  baseFill: {
    ...StyleSheet.absoluteFillObject
  },
  atmosphere: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: '100%',
    height: '100%',
    opacity: 0.6
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
