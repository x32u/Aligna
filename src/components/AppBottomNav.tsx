import { usePathname, useRouter } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useAppTheme } from '@/theme';

const navItems = [
  { label: 'Home', symbol: '⌂', href: '/dashboard' },
  { label: 'Meeting', symbol: '●', href: '/meeting' },
  { label: 'AI Review', symbol: '✦', href: '/results' },
  { label: 'Timeline', symbol: '▥', href: '/timeline' },
] as const;

export function AppBottomNav() {
  const router = useRouter();
  const pathname = usePathname();
  const theme = useAppTheme();

  return (
    <View
      accessibilityRole="tablist"
      style={[
        styles.container,
        {
          backgroundColor: theme.colors.surface,
          borderTopColor: theme.colors.border,
          paddingHorizontal: theme.spacing.xs,
        },
      ]}>
      {navItems.map((item) => {
        const active = pathname === item.href;
        return (
          <Pressable
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            key={item.href}
            onPress={() => router.replace(item.href)}
            style={({ pressed }) => [
              styles.item,
              {
                minHeight: theme.touchTarget,
                borderRadius: theme.radius.md,
                backgroundColor: active ? theme.colors.infoSoft : 'transparent',
                opacity: pressed ? 0.64 : 1,
              },
            ]}>
            <Text
              style={[
                styles.symbol,
                { color: active ? theme.colors.primary : theme.colors.textMuted },
              ]}>
              {item.symbol}
            </Text>
            <Text
              numberOfLines={1}
              style={[
                styles.label,
                {
                  color: active ? theme.colors.primary : theme.colors.textMuted,
                  fontWeight: active ? '700' : '500',
                },
              ]}>
              {item.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    paddingTop: 7,
  },
  item: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 5,
    gap: 2,
  },
  symbol: {
    fontSize: 19,
    lineHeight: 21,
    fontWeight: '700',
  },
  label: {
    fontSize: 10,
    lineHeight: 13,
  },
});
