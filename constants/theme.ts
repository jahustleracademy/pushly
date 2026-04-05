export type PushlyTheme = {
  colors: {
    background: string;
    backgroundDeep: string;
    surface: string;
    surfaceElevated: string;
    surfaceGlass: string;
    border: string;
    borderStrong: string;
    text: string;
    textMuted: string;
    accent: string;
    accentSoft: string;
    accentStrong: string;
    accentDeep: string;
    success: string;
    warning: string;
    danger: string;
    dangerSoft: string;
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
    heavy: string;
  };
};

export const pushlyTheme: PushlyTheme = {
  colors: {
    background: '#070807',
    backgroundDeep: '#030402',
    surface: '#101210',
    surfaceElevated: '#171A17',
    surfaceGlass: 'rgba(255,255,255,0.06)',
    border: 'rgba(255,255,255,0.1)',
    borderStrong: 'rgba(255,255,255,0.2)',
    text: '#F7F8F2',
    textMuted: '#A8AD9F',
    accent: '#BAFA20',
    accentSoft: '#AEDD46',
    accentStrong: '#87AD35',
    accentDeep: '#617B24',
    success: '#4ADE80',
    warning: '#FFB020',
    danger: '#FF7A1A',
    dangerSoft: '#FFB36A'
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
    regular: 'Outfit_400Regular',
    medium: 'Outfit_500Medium',
    semibold: 'Outfit_600SemiBold',
    bold: 'Outfit_700Bold',
    heavy: 'Outfit_800ExtraBold'
  }
};
