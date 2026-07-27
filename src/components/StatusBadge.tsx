import { StyleSheet, Text, View } from 'react-native';

import { useAppTheme } from '@/theme';

type BadgeTone = 'neutral' | 'success' | 'warning' | 'danger' | 'info';

export interface StatusBadgeProps {
  label: string;
  tone?: BadgeTone;
}

export function StatusBadge({ label, tone = 'neutral' }: StatusBadgeProps) {
  const theme = useAppTheme();
  const tones: Record<BadgeTone, { background: string; color: string }> = {
    neutral: { background: theme.colors.surfaceElevated, color: theme.colors.textMuted },
    success: { background: theme.colors.successSoft, color: theme.colors.success },
    warning: { background: theme.colors.warningSoft, color: theme.colors.warning },
    danger: { background: theme.colors.dangerSoft, color: theme.colors.danger },
    info: { background: theme.colors.infoSoft, color: theme.colors.info },
  };

  return (
    <View
      style={[
        styles.badge,
        {
          backgroundColor: tones[tone].background,
          borderRadius: theme.radius.pill,
        },
      ]}>
      <Text style={[theme.typography.caption, { color: tones[tone].color }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
});
