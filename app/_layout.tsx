import {
  DarkTheme,
  DefaultTheme,
  Stack,
  ThemeProvider as NavigationThemeProvider,
} from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useMemo } from 'react';
import { useColorScheme } from 'react-native';
import {
  initialWindowMetrics,
  SafeAreaProvider,
} from 'react-native-safe-area-context';

import { AlignaThemeProvider, darkTheme, lightTheme } from '@/theme';

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const appTheme = colorScheme === 'dark' ? darkTheme : lightTheme;
  const navigationTheme = useMemo(() => {
    const base = colorScheme === 'dark' ? DarkTheme : DefaultTheme;
    return {
      ...base,
      colors: {
        ...base.colors,
        background: appTheme.colors.background,
        card: appTheme.colors.surface,
        text: appTheme.colors.text,
        border: appTheme.colors.border,
        primary: appTheme.colors.primary,
      },
    };
  }, [appTheme, colorScheme]);

  return (
    <SafeAreaProvider initialMetrics={initialWindowMetrics}>
      <AlignaThemeProvider>
        <NavigationThemeProvider value={navigationTheme}>
          <StatusBar style="auto" />
          <Stack
            screenOptions={{
              headerShown: false,
              contentStyle: { backgroundColor: appTheme.colors.background },
              animation: 'slide_from_right',
            }}>
            <Stack.Screen name="index" />
            <Stack.Screen name="(auth)" />
            <Stack.Screen name="(app)" />
          </Stack>
        </NavigationThemeProvider>
      </AlignaThemeProvider>
    </SafeAreaProvider>
  );
}
