export type PushlyTheme = {
  colors: {
    background: string;
    surface: string;
    surfaceElevated: string;
    border: string;
    text: string;
    textMuted: string;
    accent: string;
    accentStrong: string;
    success: string;
    warning: string;
  };
  spacing: {
    xs: number;
    sm: number;
    md: number;
    lg: number;
    xl: number;
  };
  radius: {
    sm: number;
    md: number;
    lg: number;
    xl: number;
  };
  typography: {
    regular: string;
    medium: string;
    semibold: string;
    bold: string;
  };
};

export const pushlyTheme: PushlyTheme = {
  colors: {
    background: '#05070B',
    surface: '#0E1219',
    surfaceElevated: '#151C27',
    border: '#1F2A3A',
    text: '#F4F7FF',
    textMuted: '#8C98AD',
    accent: '#3EE7A8',
    accentStrong: '#00C887',
    success: '#4ADE80',
    warning: '#F59E0B'
  },
  spacing: {
    xs: 6,
    sm: 10,
    md: 16,
    lg: 24,
    xl: 32
  },
  radius: {
    sm: 8,
    md: 12,
    lg: 16,
    xl: 24
  },
  typography: {
    regular: 'Sora_400Regular',
    medium: 'Sora_500Medium',
    semibold: 'Sora_600SemiBold',
    bold: 'Sora_700Bold'
  }
};
