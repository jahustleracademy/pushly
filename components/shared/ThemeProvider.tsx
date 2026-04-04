import React, { createContext, useContext, useMemo } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { pushlyTheme, PushlyTheme } from '@/constants/theme';

type ThemeContextValue = {
  theme: PushlyTheme;
};

const ThemeContext = createContext<ThemeContextValue>({ theme: pushlyTheme });

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const value = useMemo(() => ({ theme: pushlyTheme }), []);

  return (
    <SafeAreaProvider>
      <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
    </SafeAreaProvider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
