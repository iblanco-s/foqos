import FamilyControls
import Foundation

enum SharedData {
  private static let suite = UserDefaults(
    suiteName: "group.dev.ambitionsoftware.foqos"
  )!

  // MARK: – Keys
  private enum Key: String {
    case profileSnapshots
    case activeScheduleSession
    case completedScheduleSessions
  }

  // MARK: – Serializable snapshot of a profile (no sessions)
  struct AppLimitConfiguration: Codable, Equatable {
    static let dailyTimeRange = 1...1440
    static let dailyOpenRange = 1...100
    static let openDurationRange = 1...60
    static let defaultOpenDurationInMinutes = 5

    var dailyTimeLimitInMinutes: Int?
    var dailyOpenLimit: Int?
    var openDurationInMinutes: Int?

    var isEnabled: Bool {
      (dailyTimeLimitInMinutes ?? 0) > 0 || (dailyOpenLimit ?? 0) > 0
    }

    var hasTimeLimit: Bool {
      (dailyTimeLimitInMinutes ?? 0) > 0
    }

    var hasOpenLimit: Bool {
      (dailyOpenLimit ?? 0) > 0
    }

    var normalized: AppLimitConfiguration {
      AppLimitConfiguration(
        dailyTimeLimitInMinutes: dailyTimeLimitInMinutes.flatMap {
          Self.dailyTimeRange.contains($0) ? $0 : nil
        },
        dailyOpenLimit: dailyOpenLimit.flatMap {
          Self.dailyOpenRange.contains($0) ? $0 : nil
        },
        openDurationInMinutes: {
          let raw = openDurationInMinutes ?? Self.defaultOpenDurationInMinutes
          return min(max(raw, Self.openDurationRange.lowerBound), Self.openDurationRange.upperBound)
        }()
      )
    }
  }

  struct ProfileSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var selectedActivity: FamilyActivitySelection
    var createdAt: Date
    var updatedAt: Date
    var blockingStrategyId: String?
    var strategyData: Data?
    var order: Int

    var enableLiveActivity: Bool
    var reminderTimeInSeconds: UInt32?
    var customReminderMessage: String?
    var enableBreaks: Bool
    var breakTimeInMinutes: Int = 15
    var allowMultipleBreaks: Bool? = nil
    var enableStrictMode: Bool
    var enableBlockAppInstallation: Bool = false
    var enableAllowMode: Bool
    var enableAllowModeDomains: Bool
    var enableSafariBlocking: Bool
    var enableAdultContentBlocking: Bool? = nil
    var enableMacSync: Bool? = nil

    var domains: [String]?

    @available(*, deprecated, message: "Use physicalUnblockItems instead")
    var physicalUnblockNFCTagId: String? = nil

    @available(*, deprecated, message: "Use physicalUnblockItems instead")
    var physicalUnblockQRCodeId: String? = nil

    var physicalUnblockItems: [PhysicalUnblockItem]? = nil

    var schedule: BlockedProfileSchedule?

    var disableBackgroundStops: Bool?
    var enableEmergencyUnblock: Bool?

    // MARK: - Daily app limits (alternative to focus sessions).
    // All optional so snapshots written by older versions still decode.
    var appLimitsEnabled: Bool? = nil
    var dailyTimeLimitInMinutes: Int? = nil
    var dailyOpenLimit: Int? = nil
    var appLimitOpenDurationInMinutes: Int? = nil

    var appLimitConfiguration: AppLimitConfiguration {
      AppLimitConfiguration(
        dailyTimeLimitInMinutes: dailyTimeLimitInMinutes,
        dailyOpenLimit: dailyOpenLimit,
        openDurationInMinutes: appLimitOpenDurationInMinutes
      ).normalized
    }

    var hasAppLimitsEnabled: Bool {
      (appLimitsEnabled ?? false) && appLimitConfiguration.isEnabled
    }

    var hasAppTimeLimit: Bool {
      hasAppLimitsEnabled && appLimitConfiguration.hasTimeLimit
    }

    var hasAppOpenLimit: Bool {
      hasAppLimitsEnabled && appLimitConfiguration.hasOpenLimit
    }

    var resolvedAppLimitOpenDurationInMinutes: Int {
      appLimitConfiguration.openDurationInMinutes
        ?? AppLimitConfiguration.defaultOpenDurationInMinutes
    }
  }

  // MARK: – Serializable snapshot of a session (no profile object)
  struct SessionSnapshot: Codable, Equatable {
    var id: String
    var tag: String
    var blockedProfileId: UUID

    var startTime: Date
    var endTime: Date?

    var breakStartTime: Date?
    var breakEndTime: Date?
    var usedBreakDurationInSeconds: TimeInterval? = nil

    var pauseStartTime: Date?
    var pauseEndTime: Date?

    var forceStarted: Bool
  }

  // MARK: – Persisted snapshots keyed by profile ID (UUID string)
  static var profileSnapshots: [String: ProfileSnapshot] {
    get {
      guard let data = suite.data(forKey: Key.profileSnapshots.rawValue) else { return [:] }
      return (try? JSONDecoder().decode([String: ProfileSnapshot].self, from: data)) ?? [:]
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        suite.set(data, forKey: Key.profileSnapshots.rawValue)
      } else {
        suite.removeObject(forKey: Key.profileSnapshots.rawValue)
      }
    }
  }

  static func snapshot(for profileID: String) -> ProfileSnapshot? {
    profileSnapshots[profileID]
  }

  static func setSnapshot(_ snapshot: ProfileSnapshot, for profileID: String) {
    var all = profileSnapshots
    all[profileID] = snapshot
    profileSnapshots = all
  }

  static func removeSnapshot(for profileID: String) {
    var all = profileSnapshots
    all.removeValue(forKey: profileID)
    profileSnapshots = all
  }

  // MARK: – Persisted array of scheduled sessions
  static var completedSessionsInSchedular: [SessionSnapshot] {
    get {
      guard let data = suite.data(forKey: Key.completedScheduleSessions.rawValue) else { return [] }
      return (try? JSONDecoder().decode([SessionSnapshot].self, from: data)) ?? []
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        suite.set(data, forKey: Key.completedScheduleSessions.rawValue)
      } else {
        suite.removeObject(forKey: Key.completedScheduleSessions.rawValue)
      }
    }
  }

  // MARK: – Persisted array of scheduled sessions
  static var activeSharedSession: SessionSnapshot? {
    get {
      guard let data = suite.data(forKey: Key.activeScheduleSession.rawValue) else { return nil }
      return (try? JSONDecoder().decode(SessionSnapshot.self, from: data)) ?? nil
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        suite.set(data, forKey: Key.activeScheduleSession.rawValue)
      } else {
        suite.removeObject(forKey: Key.activeScheduleSession.rawValue)
      }
    }
  }

  @discardableResult
  static func createSessionForSchedular(for profileID: UUID) -> SessionSnapshot {
    let session = SessionSnapshot(
      id: UUID().uuidString,
      tag: profileID.uuidString,
      blockedProfileId: profileID,
      startTime: Date(),
      forceStarted: true)
    activeSharedSession = session
    return session
  }

  static func createActiveSharedSession(for session: SessionSnapshot) {
    activeSharedSession = session
  }

  static func getActiveSharedSession() -> SessionSnapshot? {
    activeSharedSession
  }

  static func endActiveSharedSession() {
    guard var existingScheduledSession = activeSharedSession else { return }

    existingScheduledSession.endTime = Date()
    completedSessionsInSchedular.append(existingScheduledSession)

    activeSharedSession = nil
  }

  static func flushActiveSession() {
    activeSharedSession = nil
  }

  static func getCompletedSessionsForSchedular() -> [SessionSnapshot] {
    completedSessionsInSchedular
  }

  static func flushCompletedSessionsForSchedular() {
    completedSessionsInSchedular = []
  }

  static func setBreakStartTime(date: Date) {
    activeSharedSession?.breakStartTime = date
  }

  static func setBreakEndTime(date: Date) {
    activeSharedSession?.breakEndTime = date
  }

  static func resetBreak() {
    activeSharedSession?.breakStartTime = nil
    activeSharedSession?.breakEndTime = nil
  }

  static func setUsedBreakDurationInSeconds(_ duration: TimeInterval) {
    activeSharedSession?.usedBreakDurationInSeconds = duration
  }

  static func endBreak(date: Date, allowMultipleBreaks: Bool, totalAllowanceInSeconds: TimeInterval)
  {
    guard var session = activeSharedSession else { return }

    if allowMultipleBreaks, let breakStartTime = session.breakStartTime {
      let activeBreakDuration = max(0, date.timeIntervalSince(breakStartTime))
      let existingUsedDuration = session.usedBreakDurationInSeconds ?? 0
      session.usedBreakDurationInSeconds = min(
        totalAllowanceInSeconds,
        existingUsedDuration + activeBreakDuration
      )
    }

    session.breakEndTime = date
    activeSharedSession = session
  }

  static func setEndTime(date: Date) {
    activeSharedSession?.endTime = date
  }

  static func resetPause() {
    activeSharedSession?.pauseStartTime = nil
    activeSharedSession?.pauseEndTime = nil
  }

  static func setPauseStartTime(date: Date) {
    activeSharedSession?.pauseStartTime = date
  }

  static func setPauseEndTime(date: Date) {
    activeSharedSession?.pauseEndTime = date
  }
}
