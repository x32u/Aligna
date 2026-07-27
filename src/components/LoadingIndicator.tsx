import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';

import { useAppTheme } from '@/theme';

export interface LoadingIndicatorProps {
  label?: string;
}

export function LoadingIndicator({ label = 'Loading…' }: LoadingIndicatorProps) {
  const theme = useAppTheme();

  return (
    <View accessibilityRole="progressbar" style={styles.container}>
      <ActivityIndicator size="small" color={theme.colors.primary} />
      <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    padding: 16,
  },
});
