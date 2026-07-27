import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useAppTheme } from '@/theme';

export interface HeaderProps {
  title: string;
  subtitle?: string;
  eyebrow?: string;
  onBack?: () => void;
  actionLabel?: string;
  onAction?: () => void;
}

export function Header({
  title,
  subtitle,
  eyebrow,
  onBack,
  actionLabel,
  onAction,
}: HeaderProps) {
  const theme = useAppTheme();

  return (
    <View style={[styles.container, { marginBottom: theme.spacing.xl }]}>
      <View style={styles.topRow}>
        {onBack ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Go back"
            onPress={onBack}
            hitSlop={6}
            style={({ pressed }) => [
              styles.iconButton,
              {
                backgroundColor: theme.colors.surface,
                borderColor: theme.colors.border,
                borderRadius: theme.radius.md,
                opacity: pressed ? 0.65 : 1,
              },
            ]}>
            <Text style={[styles.backIcon, { color: theme.colors.text }]}>‹</Text>
          </Pressable>
        ) : (
          <View style={[styles.logoMark, { backgroundColor: theme.colors.primary }]}>
            <Text style={[styles.logoText, { color: theme.colors.onPrimary }]}>A</Text>
          </View>
        )}

        {actionLabel && onAction ? (
          <Pressable
            accessibilityRole="button"
            onPress={onAction}
            hitSlop={8}
            style={styles.action}>
            <Text style={[theme.typography.label, { color: theme.colors.primary }]}>
              {actionLabel}
            </Text>
          </Pressable>
        ) : (
          <View />
        )}
      </View>

      {eyebrow && (
        <Text
          style={[
            theme.typography.caption,
            styles.eyebrow,
            { color: theme.colors.primary, marginTop: theme.spacing.lg },
          ]}>
          {eyebrow}
        </Text>
      )}
      <Text
        accessibilityRole="header"
        style={[
          theme.typography.title,
          { color: theme.colors.text, marginTop: eyebrow ? theme.spacing.xs : theme.spacing.lg },
        ]}>
        {title}
      </Text>
      {subtitle && (
        <Text
          style={[
            theme.typography.body,
            { color: theme.colors.textMuted, marginTop: theme.spacing.xs },
          ]}>
          {subtitle}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
  },
  topRow: {
    minHeight: 44,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  iconButton: {
    width: 44,
    height: 44,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  backIcon: {
    fontSize: 34,
    lineHeight: 36,
    marginTop: -2,
  },
  logoMark: {
    width: 40,
    height: 40,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoText: {
    fontSize: 21,
    fontWeight: '800',
  },
  action: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  eyebrow: {
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
});
