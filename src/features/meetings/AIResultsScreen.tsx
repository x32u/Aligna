import { useRouter } from 'expo-router';
import { useMemo, useState } from 'react';
import { Alert, StyleSheet, Text, View } from 'react-native';

import {
  AppBottomNav,
  Button,
  Card,
  Header,
  ScreenContainer,
  StatusBadge,
} from '@/components';
import { actionItems as initialActionItems, meetings } from '@/features/mock-data';
import { useAppTheme } from '@/theme';
import type { ActionItem, SuggestionStatus } from '@/types';
import { formatShortDate } from '@/utils/date';

function statusPresentation(status: SuggestionStatus) {
  switch (status) {
    case 'approved':
      return { label: 'Approved', tone: 'success' as const };
    case 'dismissed':
      return { label: 'Dismissed', tone: 'danger' as const };
    case 'editing':
      return { label: 'Editing', tone: 'info' as const };
    default:
      return { label: 'Needs review', tone: 'warning' as const };
  }
}

export function AIResultsScreen() {
  const router = useRouter();
  const theme = useAppTheme();
  const meeting = meetings[0];
  const [items, setItems] = useState<ActionItem[]>(() =>
    initialActionItems.map((item) => ({ ...item })),
  );

  const approvedCount = useMemo(
    () => items.filter((item) => item.status === 'approved').length,
    [items],
  );
  const pendingCount = useMemo(
    () => items.filter((item) => item.status === 'pending' || item.status === 'editing').length,
    [items],
  );

  const setStatus = (id: string, status: SuggestionStatus) => {
    setItems((current) =>
      current.map((item) => (item.id === id ? { ...item, status } : item)),
    );
  };

  const editSuggestion = (item: ActionItem) => {
    setStatus(item.id, 'editing');
    Alert.alert(
      'Edit task placeholder',
      `A task editor for “${item.title}” will open here when project forms are implemented.`,
    );
  };

  const approveRemaining = () => {
    setItems((current) =>
      current.map((item) =>
        item.status === 'pending' || item.status === 'editing'
          ? { ...item, status: 'approved' }
          : item,
      ),
    );
  };

  return (
    <ScreenContainer
      testID="results-screen"
      footer={<AppBottomNav />}
      contentStyle={styles.content}>
      <Header
        eyebrow="AI MEETING RESULTS"
        title={meeting.title}
        subtitle={`${meeting.projectName} · ${meeting.duration}`}
        onBack={() => router.back()}
      />

      <Card style={[styles.reviewBanner, { backgroundColor: theme.colors.warningSoft }]}>
        <View style={styles.reviewBannerTop}>
          <Text style={[styles.reviewIcon, { color: theme.colors.warning }]}>!</Text>
          <View style={styles.reviewBannerCopy}>
            <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
              Human approval required
            </Text>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              Nothing below becomes an official project task until you approve it.
            </Text>
          </View>
        </View>
        <View style={styles.reviewStats}>
          <Text style={[theme.typography.caption, { color: theme.colors.warning }]}>
            {pendingCount} awaiting review
          </Text>
          <Text style={[theme.typography.caption, { color: theme.colors.success }]}>
            {approvedCount} approved
          </Text>
        </View>
      </Card>

      <View style={styles.sectionHeader}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Meeting summary</Text>
        <StatusBadge label="AI generated" tone="info" />
      </View>
      <Card>
        <Text style={[theme.typography.body, { color: theme.colors.text }]}>
          {meeting.summary}
        </Text>
        <View style={[styles.decisionBox, { backgroundColor: theme.colors.surfaceElevated }]}>
          <Text style={[theme.typography.caption, { color: theme.colors.primary }]}>
            KEY DECISION
          </Text>
          <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
            Internal beta moves to August 14, after offline recording recovery is validated.
          </Text>
        </View>
      </Card>

      <View style={styles.sectionHeader}>
        <View>
          <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Suggested tasks</Text>
          <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
            Review each suggestion before it joins the project
          </Text>
        </View>
        <StatusBadge label={`${items.length} found`} tone="neutral" />
      </View>

      {items.map((item) => {
        const presentation = statusPresentation(item.status);
        const inactive = item.status === 'approved' || item.status === 'dismissed';
        return (
          <Card key={item.id} style={styles.suggestionCard}>
            <View style={styles.suggestionTop}>
              <StatusBadge label={presentation.label} tone={presentation.tone} />
              <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
                {Math.round(item.confidence * 100)}% confidence
              </Text>
            </View>
            <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
              {item.title}
            </Text>
            <Text style={[theme.typography.body, { color: theme.colors.textMuted }]}>
              {item.description}
            </Text>
            <View style={[styles.assignmentRow, { borderTopColor: theme.colors.border }]}>
              <View style={[styles.avatar, { backgroundColor: item.assignee.color }]}>
                <Text style={styles.avatarText}>{item.assignee.initials}</Text>
              </View>
              <View style={styles.assignmentCopy}>
                <Text style={[theme.typography.caption, { color: theme.colors.text }]}>
                  {item.assignee.name}
                </Text>
                <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
                  Due {formatShortDate(item.deadline)}
                </Text>
              </View>
            </View>
            <View style={styles.actionRow}>
              <Button
                disabled={inactive}
                fullWidth={false}
                style={styles.actionButton}
                title="Approve"
                variant="success"
                onPress={() => setStatus(item.id, 'approved')}
              />
              <Button
                disabled={inactive}
                fullWidth={false}
                style={styles.actionButton}
                title="Edit"
                variant="secondary"
                onPress={() => editSuggestion(item)}
              />
              <Button
                disabled={inactive}
                fullWidth={false}
                style={styles.actionButton}
                title="Dismiss"
                variant="danger"
                onPress={() => setStatus(item.id, 'dismissed')}
              />
            </View>
          </Card>
        );
      })}

      <Button
        disabled={pendingCount === 0}
        title={`Approve remaining (${pendingCount})`}
        onPress={approveRemaining}
      />

      <View style={styles.sectionHeader}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>Transcript preview</Text>
        <StatusBadge label="12 speakers" tone="neutral" />
      </View>
      <Card style={styles.transcript}>
        <Text style={[theme.typography.caption, { color: theme.colors.primary }]}>10:14 · Maya</Text>
        <Text style={[theme.typography.body, { color: theme.colors.text }]}>
          Let’s keep every extracted task in review until an owner confirms the wording and due date.
        </Text>
        <View style={[styles.transcriptDivider, { backgroundColor: theme.colors.border }]} />
        <Text style={[theme.typography.caption, { color: theme.colors.accent }]}>10:52 · Leo</Text>
        <Text style={[theme.typography.body, { color: theme.colors.text }]}>
          I can validate interrupted uploads before the beta. That should remain a dependency for release.
        </Text>
      </Card>

      <Button
        title="Continue to project timeline"
        variant="secondary"
        onPress={() => router.push('/timeline')}
      />
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: 16,
  },
  reviewBanner: {
    gap: 13,
    borderWidth: 0,
  },
  reviewBannerTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  reviewIcon: {
    width: 28,
    fontSize: 23,
    lineHeight: 26,
    fontWeight: '800',
    textAlign: 'center',
  },
  reviewBannerCopy: {
    flex: 1,
    gap: 3,
  },
  reviewStats: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginLeft: 40,
  },
  sectionHeader: {
    minHeight: 38,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    marginTop: 5,
  },
  decisionBox: {
    padding: 13,
    borderRadius: 12,
    gap: 4,
    marginTop: 16,
  },
  suggestionCard: {
    gap: 11,
  },
  suggestionTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 8,
  },
  assignmentRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingTop: 12,
    gap: 10,
  },
  avatar: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '700',
  },
  assignmentCopy: {
    flex: 1,
    gap: 1,
  },
  actionRow: {
    flexDirection: 'row',
    gap: 8,
  },
  actionButton: {
    flex: 1,
    paddingHorizontal: 6,
  },
  transcript: {
    gap: 8,
  },
  transcriptDivider: {
    height: StyleSheet.hairlineWidth,
    marginVertical: 5,
  },
});
