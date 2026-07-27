import { useRouter } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import {
  AppBottomNav,
  Button,
  Card,
  Header,
  ScreenContainer,
  StatusBadge,
} from '@/components';
import { projects, timelineItems } from '@/features/mock-data';
import { useAppTheme } from '@/theme';
import type { TaskStatus } from '@/types';
import { formatLongDate, percentLabel } from '@/utils/date';

const DAY_WIDTH = 58;
const LABEL_WIDTH = 136;
const DAYS = ['Jul 27', 'Jul 29', 'Jul 31', 'Aug 2', 'Aug 4', 'Aug 6', 'Aug 8'];

function timelineTone(status: TaskStatus) {
  switch (status) {
    case 'done':
      return 'success' as const;
    case 'blocked':
      return 'danger' as const;
    case 'in-progress':
      return 'info' as const;
    default:
      return 'neutral' as const;
  }
}

function barColor(status: TaskStatus, theme: ReturnType<typeof useAppTheme>) {
  switch (status) {
    case 'done':
      return theme.colors.success;
    case 'blocked':
      return theme.colors.danger;
    case 'in-progress':
      return theme.colors.info;
    default:
      return theme.colors.textMuted;
  }
}

export function TimelineScreen() {
  const router = useRouter();
  const theme = useAppTheme();
  const project = projects[0];
  const chartWidth = DAYS.length * DAY_WIDTH;

  return (
    <ScreenContainer
      testID="timeline-screen"
      footer={<AppBottomNav />}
      contentStyle={styles.content}>
      <Header
        eyebrow="PROJECT TIMELINE"
        title={project.name}
        subtitle={`Target release · ${formatLongDate(project.dueDate)}`}
        onBack={() => router.back()}
      />

      <Card style={styles.overviewCard}>
        <View style={styles.overviewTop}>
          <View>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              DELIVERY CONFIDENCE
            </Text>
            <Text style={[theme.typography.title, { color: theme.colors.text }]}>82%</Text>
          </View>
          <StatusBadge label="On track" tone="success" />
        </View>
        <View style={[styles.progressTrack, { backgroundColor: theme.colors.surfaceElevated }]}>
          <View
            style={[
              styles.progressFill,
              { width: '64%', backgroundColor: theme.colors.primary },
            ]}
          />
        </View>
        <View style={styles.metrics}>
          <View>
            <Text style={[theme.typography.heading, { color: theme.colors.text }]}>5</Text>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              Milestones
            </Text>
          </View>
          <View>
            <Text style={[theme.typography.heading, { color: theme.colors.text }]}>2</Text>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              In progress
            </Text>
          </View>
          <View>
            <Text style={[theme.typography.heading, { color: theme.colors.danger }]}>1</Text>
            <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
              Blocked
            </Text>
          </View>
        </View>
      </Card>

      <View style={styles.sectionHeader}>
        <View>
          <Text style={[theme.typography.heading, { color: theme.colors.text }]}>
            Delivery plan
          </Text>
          <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
            Swipe horizontally to inspect the schedule
          </Text>
        </View>
        <StatusBadge label="2 weeks" tone="info" />
      </View>

      <Card style={styles.chartCard}>
        <ScrollView
          horizontal
          nestedScrollEnabled
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chartScroll}>
          <View>
            <View style={styles.chartHeader}>
              <View
                style={[
                  styles.labelHeader,
                  { width: LABEL_WIDTH, borderRightColor: theme.colors.border },
                ]}>
                <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
                  WORKSTREAM
                </Text>
              </View>
              <View style={[styles.dayHeader, { width: chartWidth }]}>
                {DAYS.map((day) => (
                  <View
                    key={day}
                    style={[
                      styles.dayCell,
                      { width: DAY_WIDTH, borderRightColor: theme.colors.border },
                    ]}>
                    <Text style={[styles.dayText, { color: theme.colors.textMuted }]}>{day}</Text>
                  </View>
                ))}
              </View>
            </View>

            {timelineItems.map((item) => {
              const color = barColor(item.status, theme);
              return (
                <View
                  key={item.id}
                  style={[styles.timelineRow, { borderTopColor: theme.colors.border }]}>
                  <View
                    style={[
                      styles.taskLabel,
                      { width: LABEL_WIDTH, borderRightColor: theme.colors.border },
                    ]}>
                    <Text
                      numberOfLines={1}
                      style={[theme.typography.caption, { color: theme.colors.text }]}>
                      {item.title}
                    </Text>
                    <Text style={[styles.ownerLabel, { color: theme.colors.textMuted }]}>
                      {item.owner.initials} · {percentLabel(item.progress)}
                    </Text>
                  </View>
                  <View style={[styles.track, { width: chartWidth }]}>
                    {DAYS.map((day) => (
                      <View
                        key={`${item.id}-${day}`}
                        style={[
                          styles.gridCell,
                          { width: DAY_WIDTH, borderRightColor: theme.colors.border },
                        ]}
                      />
                    ))}
                    <View
                      style={[
                        styles.timelineBar,
                        {
                          left: item.startDay * (DAY_WIDTH / 2),
                          width: Math.max(item.durationDays * (DAY_WIDTH / 2), 52),
                          backgroundColor: color,
                          borderRadius: theme.radius.pill,
                        },
                      ]}>
                      <View
                        style={[
                          styles.timelineProgress,
                          {
                            width: `${item.progress * 100}%`,
                            backgroundColor: 'rgba(255,255,255,0.28)',
                          },
                        ]}
                      />
                    </View>
                  </View>
                </View>
              );
            })}
          </View>
        </ScrollView>
      </Card>

      <View style={styles.sectionHeader}>
        <Text style={[theme.typography.heading, { color: theme.colors.text }]}>
          Milestones & dependencies
        </Text>
      </View>
      {timelineItems.map((item) => (
        <Card key={`detail-${item.id}`} style={styles.milestoneCard}>
          <View style={styles.milestoneTop}>
            <View style={styles.milestoneCopy}>
              <Text style={[theme.typography.bodyStrong, { color: theme.colors.text }]}>
                {item.title}
              </Text>
              <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
                {item.owner.name} · {item.durationDays} days
              </Text>
            </View>
            <StatusBadge
              label={item.status.replace('-', ' ')}
              tone={timelineTone(item.status)}
            />
          </View>
          {item.dependency && (
            <View style={[styles.dependency, { backgroundColor: theme.colors.surfaceElevated }]}>
              <Text style={[theme.typography.caption, { color: theme.colors.textMuted }]}>
                Depends on
              </Text>
              <Text style={[theme.typography.caption, { color: theme.colors.text }]}>
                {item.dependency}
              </Text>
            </View>
          )}
        </Card>
      ))}

      <Button
        title="Record a project update"
        onPress={() => router.push('/meeting')}
      />
      <Button
        title="Back to dashboard"
        variant="ghost"
        onPress={() => router.replace('/dashboard')}
      />
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: 16,
  },
  overviewCard: {
    gap: 16,
  },
  overviewTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  progressTrack: {
    height: 8,
    borderRadius: 99,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 99,
  },
  metrics: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingRight: 20,
  },
  sectionHeader: {
    minHeight: 40,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    marginTop: 5,
  },
  chartCard: {
    padding: 0,
    overflow: 'hidden',
  },
  chartScroll: {
    paddingBottom: 1,
  },
  chartHeader: {
    flexDirection: 'row',
    minHeight: 46,
  },
  labelHeader: {
    paddingHorizontal: 12,
    justifyContent: 'center',
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  dayHeader: {
    flexDirection: 'row',
  },
  dayCell: {
    justifyContent: 'center',
    alignItems: 'center',
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  dayText: {
    fontSize: 10,
    fontWeight: '600',
  },
  timelineRow: {
    height: 66,
    flexDirection: 'row',
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  taskLabel: {
    paddingHorizontal: 12,
    justifyContent: 'center',
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  ownerLabel: {
    fontSize: 10,
    lineHeight: 15,
    marginTop: 2,
  },
  track: {
    flexDirection: 'row',
    position: 'relative',
  },
  gridCell: {
    height: '100%',
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  timelineBar: {
    position: 'absolute',
    top: 20,
    height: 26,
    overflow: 'hidden',
  },
  timelineProgress: {
    height: '100%',
  },
  milestoneCard: {
    gap: 12,
  },
  milestoneTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  milestoneCopy: {
    flex: 1,
    gap: 2,
  },
  dependency: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    padding: 10,
    borderRadius: 10,
    gap: 12,
  },
});
