import { useRouter } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Button, Card, Input, ScreenContainer } from '@/components';
import { useAppTheme } from '@/theme';

export interface AuthScreenProps {
  mode: 'login' | 'create-account';
}

export function AuthScreen({ mode }: AuthScreenProps) {
  const router = useRouter();
  const theme = useAppTheme();
  const isCreating = mode === 'create-account';
  const [name, setName] = useState('');
  const [email, setEmail] = useState('maya@aligna.app');
  const [password, setPassword] = useState('aligna-demo');

  const continueToApp = () => {
    router.replace('/dashboard');
  };

  return (
    <ScreenContainer
      keyboardAware
      testID={isCreating ? 'create-account-screen' : 'login-screen'}
      contentStyle={styles.content}>
      <View style={styles.brand}>
        <View
          style={[
            styles.logo,
            {
              backgroundColor: theme.colors.primary,
              borderRadius: theme.radius.lg,
              shadowColor: theme.colors.primary,
            },
          ]}>
          <Text style={[styles.logoText, { color: theme.colors.onPrimary }]}>A</Text>
        </View>
        <Text style={[theme.typography.display, { color: theme.colors.text }]}>Aligna</Text>
        <Text style={[theme.typography.body, styles.tagline, { color: theme.colors.textMuted }]}>
          Turn every conversation into clear, accountable progress.
        </Text>
      </View>

      <Card style={styles.form}>
        <View style={styles.formHeader}>
          <Text accessibilityRole="header" style={[theme.typography.title, { color: theme.colors.text }]}>
            {isCreating ? 'Create your workspace' : 'Welcome back'}
          </Text>
          <Text style={[theme.typography.body, { color: theme.colors.textMuted }]}>
            {isCreating
              ? 'Start organizing meetings, decisions, and delivery.'
              : 'Continue to your projects and meeting insights.'}
          </Text>
        </View>

        {isCreating && (
          <Input
            autoCapitalize="words"
            autoComplete="name"
            label="Full name"
            onChangeText={setName}
            placeholder="Maya Chen"
            value={name}
          />
        )}
        <Input
          autoCapitalize="none"
          autoComplete="email"
          keyboardType="email-address"
          label="Work email"
          onChangeText={setEmail}
          placeholder="you@company.com"
          value={email}
        />
        <Input
          autoCapitalize="none"
          autoComplete={isCreating ? 'new-password' : 'current-password'}
          label="Password"
          onChangeText={setPassword}
          secureTextEntry
          value={password}
        />

        <Button
          accessibilityHint="Opens the Aligna project dashboard"
          title={isCreating ? 'Create account' : 'Sign in'}
          onPress={continueToApp}
        />
        <Button
          title={isCreating ? 'I already have an account' : 'Create an account'}
          variant="ghost"
          onPress={() =>
            router.replace(isCreating ? '/login' : '/create-account')
          }
        />
      </Card>

      <View style={styles.trustRow}>
        <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
          Human-reviewed AI
        </Text>
        <View style={[styles.dot, { backgroundColor: theme.colors.border }]} />
        <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
          Your team stays in control
        </Text>
      </View>
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  content: {
    justifyContent: 'center',
    gap: 28,
  },
  brand: {
    alignItems: 'center',
    gap: 10,
    paddingTop: 12,
  },
  logo: {
    width: 68,
    height: 68,
    alignItems: 'center',
    justifyContent: 'center',
    shadowOpacity: 0.22,
    shadowRadius: 20,
    shadowOffset: { width: 0, height: 10 },
  },
  logoText: {
    fontSize: 36,
    fontWeight: '800',
  },
  tagline: {
    maxWidth: 320,
    textAlign: 'center',
  },
  form: {
    gap: 18,
  },
  formHeader: {
    gap: 6,
    marginBottom: 2,
  },
  trustRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    flexWrap: 'wrap',
    gap: 8,
    paddingBottom: 8,
  },
  dot: {
    width: 4,
    height: 4,
    borderRadius: 2,
  },
});
