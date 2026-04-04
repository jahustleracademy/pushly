const required = {
  supabaseUrl: process.env.EXPO_PUBLIC_SUPABASE_URL ?? '',
  supabaseAnonKey: process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? ''
};

const optional = {
  revenueCatIosApiKey: process.env.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY ?? '',
  revenueCatAndroidApiKey: process.env.EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY ?? '',
  analyticsEnabled: (process.env.EXPO_PUBLIC_ANALYTICS_ENABLED ?? 'false').toLowerCase() === 'true'
};

export const env = {
  ...required,
  ...optional,
  hasSupabase: Boolean(required.supabaseUrl && required.supabaseAnonKey)
};
