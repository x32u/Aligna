import { useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import {
  AppBottomNav,
  Button,
  Card,
  Header,
  ScreenContainer,
  StatusBadge,
} from '@/components';
import { meetings, projects } from '@/features/mock-data';
import { useAppTheme } from '@/theme';
import { formatLongDate, percentLabel } from '@/utils/date';

export function DashboardScreen() {
  const router = useRouter();
  const theme = useAppTheme();
  const project = projects[0];
  const latestMeeting = meetings[0];

  return (
    <ScreenContainer
      testID="dashboard-screen"
      footer={<AppBottomNav />}
      contentStyle={styles.content}>
      <Header
        eyebrow="Monday, July 27"
        title="Good afternoon, Maya"
        subtitle="Here’s where your team needs alignment today."
        actionLabel="Sign out"
        onAction={() => router.replace('/login')}
      />

      <Card style={[styles.heroCard, { backgroundColor: theme.colors.primary }]}>
        <View style={styles.heroTop}>
          <View style={styles.heroCopy}>
            <Text style={[theme.typography.caption, { color: 'rgba(255,255,255,0.72)' }]}>
              ACTIVE PROJECT
            </Text>
            <Text style={[theme.typography.heading, { color: '#FFFFFF' }]}>{project.name}</Text>
          </View>
          <StatusBadge label="On track" tone="success" />
        </View>
        <Text style={[theme.typography.body, { color: 'rgba(255,255,255,0.82)' }]}>
          {project.description}
        </Text>
        <View style={styles.progressHeader}>
          <Text style={[theme.typography.caption, { color: '#FFFFFF' }]}>Overall progress</Text>
          <Text style={[theme.typography.caption, { color: '#FFFFFF' }]}>
            {percentLabel(project.progress)}
          </Text>
        </View>
        <View style={styles.progressTrack}>
          <View
            style={[
              styles.progressFill,
              {
                width: `${project.progress * 100}%`,
                backgroundColor: '#FFFFFF',
              },
            ]}
          />
        </View>
        <View style={styles.heroFooter}>
          <Text style={[theme.typography.caption, { color: 'rgba(255,255,255,0.78)' }]}>
            {project.openTasks} open tasks
          </Text>
          <Text style={[theme.typography.caption, { color: 'rgba(255,255,255,0.78)' }]}>
            Due {formatLongDate(project.dueDate)}
          </Text>
        </View>
      </Card>

      <View style={styles.sectionHeader}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Quick actions</Text>
      </View>
      <View style={styles.quickGrid}>
        <Card onPress={() => router.push('/meeting')} style={styles.quickCard}>
          <View style={[styles.quickIcon, { backgroundColor: theme.colors.dangerSoft }]}>
            <Text style={[styles.quickIconText, { color: theme.colors.danger }]}>●</Text>
          </View>
          <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
            New meeting
          </Text>
          <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
            Record or upload audio
          </Text>
        </Card>
        <Card onPress={() => router.push('/timeline')} style={styles.quickCard}>
          <View style={[styles.quickIcon, { backgroundColor: theme.colors.infoSoft }]}>
            <Text style={[styles.quickIconText, { color: theme.colors.info }]}>▥</Text>
          </View>
          <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
            Timeline
          </Text>
          <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
            Review milestones
          </Text>
        </Card>
      </View>

      <View style={styles.sectionHeader}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Needs review</Text>
        <StatusBadge label="3 suggestions" tone="warning" />
      </View>
      <Card onPress={() => router.push('/results')} accessibilityLabel="Review latest AI meeting results">
        <View style={styles.meetingTop}>
          <View style={[styles.aiMark, { backgroundColor: theme.colors.accentSoft }]}>
            <Text style={[styles.aiMarkText, { color: theme.colors.accent }]}>✦</Text>
          </View>
          <View style={styles.meetingCopy}>
            <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
              {latestMeeting.title}
            </Text>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              {latestMeeting.projectName} · {latestMeeting.duration}
            </Text>
          </View>
          <Text style={[styles.chevron, { color: theme.colors.textMuted }]}>›</Text>
        </View>
        <Text
          numberOfLines={3}
          style={[
            theme.typography.body,
            { color: theme.colors.textMuted, marginTop: theme.spacing.md },
          ]}>
          {latestMeeting.summary}
        </Text>
        <View style={[styles.reviewNote, { backgroundColor: theme.colors.warningSoft }]}>
          <Text style={[theme.typography.caption, { color: theme.colors.warning }]}>
            AI suggestions are drafts until you approve them
          </Text>
        </View>
      </Card>

      <View style={styles.sectionHeader}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Team pulse</Text>
      </View>
      <Card>
        <View style={styles.pulseRow}>
          <View>
            <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
              4 teammates active
            </Text>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              8 tasks completed this week
            </Text>
          </View>
          <View style={styles.avatars}>
            {project.members.map((person, index) => (
              <View
                key={person.id}
                style={[
                  styles.avatar,
                  {
                    backgroundColor: person.color,
                    marginLeft: index === 0 ? 0 : -9,
                    borderColor: theme.colors.surface,
                  },
                ]}>
                <Text style={styles.avatarText}>{person.initials}</Text>
              </View>
            ))}
          </View>
        </View>
        <Button
          title="View project timeline"
          variant="secondary"
          onPress={() => router.push('/timeline')}
          style={{ marginTop: theme.spacing.md }}
        />
      </Card>
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: 16,
  },
  heroCard: {
    gap: 14,
    borderWidth: 0,
  },
  heroTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  heroCopy: {
    flex: 1,
    gap: 5,
  },
  progressHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 3,
  },
  progressTrack: {
    height: 7,
    borderRadius: 99,
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.24)',
  },
  progressFill: {
    height: '100%',
    borderRadius: 99,
  },
  heroFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  sectionHeader: {
    minHeight: 34,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 6,
  },
  quickGrid: {
    flexDirection: 'row',
    gap: 12,
  },
  quickCard: {
    flex: 1,
    minHeight: 144,
    gap: 7,
  },
  quickIcon: {
    width: 40,
    height: 40,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 4,
  },
  quickIconText: {
    fontSize: 19,
    fontWeight: '700',
  },
  meetingTop: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  aiMark: {
    width: 42,
    height: 42,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  aiMarkText: {
    fontSize: 20,
  },
  meetingCopy: {
    flex: 1,
    gap: 2,
  },
  chevron: {
    fontSize: 28,
  },
  reviewNote: {
    marginTop: 14,
    padding: 11,
    borderRadius: 10,
  },
  pulseRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  avatars: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatar: {
    width: 34,
    height: 34,
    borderRadius: 17,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '700',
  },
});
