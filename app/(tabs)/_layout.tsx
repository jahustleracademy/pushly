import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '@/components/shared/ThemeProvider';

export default function TabsLayout() {
  const { theme } = useTheme();

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: theme.colors.surface,
          borderTopColor: theme.colors.border,
          height: 84,
          paddingTop: 8
        },
        tabBarActiveTintColor: theme.colors.accent,
        tabBarInactiveTintColor: theme.colors.textMuted,
        tabBarLabelStyle: {
          fontFamily: theme.typography.medium,
          fontSize: 11
        },
        tabBarIconStyle: {
          marginBottom: 2
        }
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Schutz',
          tabBarIcon: ({ color, size }) => <Ionicons name="shield-checkmark-outline" color={color} size={size} />
        }}
      />
      <Tabs.Screen
        name="progress"
        options={{
          title: 'Verlauf',
          tabBarIcon: ({ color, size }) => <Ionicons name="pulse-outline" color={color} size={size} />
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: 'Einstellungen',
          tabBarIcon: ({ color, size }) => <Ionicons name="settings-outline" color={color} size={size} />
        }}
      />
    </Tabs>
  );
}
