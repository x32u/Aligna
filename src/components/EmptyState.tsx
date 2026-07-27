import { StyleSheet, Text, View } from 'react-native';

import { Button } from './Button';
import { useAppTheme } from '@/theme';

export interface EmptyStateProps {
  icon?: string;
  title: string;
  description: string;
  actionLabel?: string;
  onAction?: () => void;
}

export function EmptyState({
  icon = '◇',
  title,
  description,
  actionLabel,
  onAction,
}: EmptyStateProps) {
  const theme = useAppTheme();

  return (
    <View style={[styles.container, { padding: theme.spacing.xl }]}>
      <View
        style={[
          styles.icon,
          {
            backgroundColor: theme.colors.infoSoft,
            borderRadius: theme.radius.lg,
          },
        ]}>
        <Text style={[styles.iconText, { color: theme.colors.info }]}>{icon}</Text>
      </View>
      <Text
        accessibilityRole="header"
        style={[theme.typography.heading, styles.center, { color: theme.colors.text }]}>
        {title}
      </Text>
      <Text style={[theme.typography.body, styles.center, { color: theme.colors.textMuted }]}>
        {description}
      </Text>
      {actionLabel && onAction && (
        <Button title={actionLabel} onPress={onAction} fullWidth={false} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    gap: 12,
  },
  icon: {
    width: 58,
    height: 58,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconText: {
    fontSize: 28,
    fontWeight: '700',
  },
  center: {
    textAlign: 'center',
  },
});
