import Foundation

enum SampleData {
    private static let dashboard = DashboardMockData.make()

    static let meetings = dashboard.meetings
    static let tasks = dashboard.tasks
}
