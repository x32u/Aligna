import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';

import {
  AppBottomNav,
  Button,
  Card,
  Header,
  Input,
  ScreenContainer,
  StatusBadge,
} from '@/components';
import { projects } from '@/features/mock-data';
import { useAppTheme } from '@/theme';

type CaptureMode = 'idle' | 'recording' | 'ready';

export function MeetingCaptureScreen() {
  const router = useRouter();
  const theme = useAppTheme();
  const [mode, setMode] = useState<CaptureMode>('idle');
  const [title, setTitle] = useState('Weekly Product Sync');
  const [selectedProject, setSelectedProject] = useState(projects[0].id);

  const toggleRecording = () => {
    setMode((current) => (current === 'recording' ? 'ready' : 'recording'));
  };

  const showUploadPlaceholder = () => {
    Alert.alert(
      'Upload prepared',
      'The system file picker and audio upload service will be connected in the meeting-capture milestone.',
    );
  };

  return (
    <ScreenContainer
      testID="meeting-screen"
      keyboardAware
      footer={<AppBottomNav />}
      contentStyle={styles.content}>
      <Header
        title="Capture a meeting"
        subtitle="Record live or upload audio. Nothing is sent until you confirm."
        onBack={() => router.back()}
      />

      <Card style={styles.recorderCard}>
        <View style={styles.recorderHeader}>
          <StatusBadge
            label={
              mode === 'recording' ? 'Recording' : mode === 'ready' ? 'Ready to analyze' : 'Ready'
            }
            tone={mode === 'recording' ? 'danger' : mode === 'ready' ? 'success' : 'neutral'}
          />
          <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
            {mode === 'recording' ? '00:18' : '00:00'}
          </Text>
        </View>

        <Pressable
          accessibilityRole="button"
          accessibilityLabel={mode === 'recording' ? 'Stop recording' : 'Start recording'}
          onPress={toggleRecording}
          style={({ pressed }) => [
            styles.recordOuter,
            {
              borderColor:
                mode === 'recording' ? theme.colors.dangerSoft : theme.colors.surfaceElevated,
              opacity: pressed ? 0.75 : 1,
            },
          ]}>
          <View
            style={[
              styles.recordButton,
              {
                backgroundColor: theme.colors.danger,
                borderRadius: mode === 'recording' ? theme.radius.sm : 46,
                width: mode === 'recording' ? 38 : 76,
                height: mode === 'recording' ? 38 : 76,
              },
            ]}
          />
        </Pressable>

        <View style={styles.recorderCopy}>
          <Text style={[theme.typography.heading, { color: theme.colors.text }]}>
            {mode === 'recording'
              ? 'Listening to your meeting…'
              : mode === 'ready'
                ? 'Recording captured'
                : 'Tap to start recording'}
          </Text>
          <Text style={[theme.typography.body, styles.center, { color: theme.colors.textMuted }]}>
            {mode === 'recording'
              ? 'This is a visual prototype. No microphone audio is being saved yet.'
              : mode === 'ready'
                ? 'Use this mock recording to preview the AI review experience.'
                : 'Aligna will preserve the original audio until processing is confirmed.'}
          </Text>
        </View>
      </Card>

      <View style={styles.dividerRow}>
        <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />
        <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>OR</Text>
        <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />
      </View>

      <Button
        title="Upload an audio file"
        variant="secondary"
        onPress={showUploadPlaceholder}
      />

      <View style={styles.formSection}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Meeting details</Text>
        <Input label="Meeting title" value={title} onChangeText={setTitle} />
        <Text style={[theme.typography.label, { color: theme.colors.text }]}>Project</Text>
        <View style={styles.projectList}>
          {projects.map((project) => {
            const selected = project.id === selectedProject;
            return (
              <Card
                key={project.id}
                accessibilityLabel={`Select ${project.name}`}
                onPress={() => setSelectedProject(project.id)}
                style={[
                  styles.projectCard,
                  {
                    borderColor: selected ? theme.colors.primary : theme.colors.border,
                    backgroundColor: selected ? theme.colors.infoSoft : theme.colors.surface,
                  },
                ]}>
                <View style={styles.projectRow}>
                  <View
                    style={[
                      styles.radio,
                      {
                        borderColor: selected ? theme.colors.primary : theme.colors.textMuted,
                      },
                    ]}>
                    {selected && (
                      <View style={[styles.radioDot, { backgroundColor: theme.colors.primary }]} />
                    )}
                  </View>
                  <View style={styles.projectCopy}>
                    <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
                      {project.name}
                    </Text>
                    <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
                      {project.openTasks} open tasks
                    </Text>
                  </View>
                </View>
              </Card>
            );
          })}
        </View>
      </View>

      <Card style={[styles.privacyCard, { backgroundColor: theme.colors.accentSoft }]}>
        <Text style={[styles.privacyIcon, { color: theme.colors.accent }]}>✓</Text>
        <View style={styles.privacyCopy}>
          <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
            Review comes before action
          </Text>
          <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
            AI-generated tasks stay in draft until a manager approves or edits them.
          </Text>
        </View>
      </Card>

      <Button
        title={mode === 'ready' ? 'Analyze mock meeting' : 'Use sample meeting'}
        onPress={() => router.push('/results')}
      />
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: 18,
  },
  recorderCard: {
    alignItems: 'center',
    gap: 20,
    paddingVertical: 24,
  },
  recorderHeader: {
    alignSelf: 'stretch',
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  recordOuter: {
    width: 112,
    height: 112,
    borderRadius: 56,
    borderWidth: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  recordButton: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  recorderCopy: {
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 10,
  },
  center: {
    textAlign: 'center',
  },
  dividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    flex: 1,
  },
  formSection: {
    gap: 13,
    marginTop: 4,
  },
  projectList: {
    gap: 10,
  },
  projectCard: {
    padding: 13,
  },
  projectRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  radio: {
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  radioDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  projectCopy: {
    flex: 1,
    gap: 2,
  },
  privacyCard: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
    borderWidth: 0,
  },
  privacyIcon: {
    fontSize: 20,
    fontWeight: '700',
  },
  privacyCopy: {
    flex: 1,
    gap: 3,
  },
});
