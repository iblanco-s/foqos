import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

class DeviceActivityCenterUtil {
  static let appLimitActivityId = "AppLimitTimerActivity"

  static func appLimitActivityName(for profileId: UUID) -> DeviceActivityName {
    DeviceActivityName(rawValue: "\(appLimitActivityId):\(profileId.uuidString)")
  }

  static func appLimitEventName(for profileId: UUID) -> DeviceActivityEvent.Name {
    DeviceActivityEvent.Name("AppLimitUsageEvent.\(profileId.uuidString)")
  }

  /// Daily all-day monitoring for app limits. Time limits use threshold events;
  /// open limits use the schedule itself (midnight reset) plus Shield grants.
  /// Independent of focus sessions: runs even when no session is active.
  static func scheduleAppLimitMonitoring(for profile: BlockedProfiles) {
    let center = DeviceActivityCenter()
    let activityName = appLimitActivityName(for: profile.id)

    guard profile.hasAppLimitsEnabled else {
      stopActivities(for: [activityName], with: center)
      return
    }

    let schedule = DeviceActivitySchedule(
      intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
      intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
      repeats: true
    )

    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
    if let minutes = profile.dailyTimeLimitInMinutes, minutes > 0 {
      let threshold = DateComponents(
        hour: minutes / 60, minute: minutes % 60)
      let selection = profile.selectedActivity
      events[appLimitEventName(for: profile.id)] = DeviceActivityEvent(
        applications: selection.applicationTokens,
        categories: selection.categoryTokens,
        webDomains: selection.webDomainTokens,
        threshold: threshold
      )
    }

    do {
      stopActivities(for: [activityName], with: center)
      if events.isEmpty {
        try center.startMonitoring(activityName, during: schedule)
      } else {
        try center.startMonitoring(activityName, during: schedule, events: events)
      }
      print("Scheduled app limit monitoring for profile \(profile.id.uuidString)")
    } catch {
      print("Failed to start app limit monitoring: \(error.localizedDescription)")
    }

    // Apply the correct shield state immediately (mid-day enable).
    // Never override an active focus session.
    if SharedData.getActiveSharedSession() == nil {
      AppLimitStore.resetDayIfNeeded(for: profile.id)
      AppBlockerUtil().activateRestrictionsForAppLimit(
        for: BlockedProfiles.getSnapshot(for: profile))
    }
  }

  static func removeAppLimitMonitoring(for profile: BlockedProfiles) {
    stopActivities(for: [appLimitActivityName(for: profile.id)])
  }

  static func removeAllAppLimitMonitoring() {
    let center = DeviceActivityCenter()
    let activities = center.activities.filter {
      $0.rawValue.hasPrefix(appLimitActivityId)
    }
    stopActivities(for: activities, with: center)
  }

  static func scheduleTimerActivity(for profile: BlockedProfiles) {
    // Only schedule if the schedule is active
    guard let schedule = profile.schedule else { return }

    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let deviceActivityName = scheduleTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    // If the schedule is not active, remove any existing schedule
    if !schedule.isActive {
      stopActivities(for: [deviceActivityName], with: center)
      return
    }

    let (intervalStart, intervalEnd) = scheduleTimerActivity.getScheduleInterval(from: schedule)
    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: true,
    )

    do {
      // Remove any existing schedule and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      print("Scheduled restrictions from \(intervalStart) to \(intervalEnd) daily")
    } catch {
      print("Failed to start monitoring: \(error.localizedDescription)")
    }
  }

  static func startBreakTimerActivity(for profile: BlockedProfiles) {
    startBreakTimerActivity(
      for: profile,
      durationInSeconds: TimeInterval(profile.breakTimeInMinutes * 60)
    )
  }

  static func startBreakTimerActivity(
    for profile: BlockedProfiles,
    durationInSeconds: TimeInterval
  ) {
    let center = DeviceActivityCenter()
    let breakTimerActivity = BreakTimerActivity()
    let deviceActivityName = breakTimerActivity.getDeviceActivityName(from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(from: durationInSeconds)
    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    do {
      // Remove any existing schedule and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      print("Scheduled break timer activity from \(intervalStart) to \(intervalEnd) daily")
    } catch {
      print("Failed to start break timer activity: \(error.localizedDescription)")
    }
  }

  static func startStrategyTimerActivity(for profile: BlockedProfiles) {
    guard let strategyData = profile.strategyData else {
      print("No strategy data found for profile: \(profile.id.uuidString)")
      return
    }
    let timerData = StrategyTimerData.toStrategyTimerData(from: strategyData)

    let center = DeviceActivityCenter()
    let strategyTimerActivity = StrategyTimerActivity()
    let deviceActivityName = strategyTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(
      from: TimeInterval(timerData.durationInMinutes * 60))

    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    do {
      // Remove any existing activity and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      print("Scheduled strategy timer activity from \(intervalStart) to \(intervalEnd) daily")
    } catch {
      print("Failed to start strategy timer activity: \(error.localizedDescription)")
    }
  }

  static func removeScheduleTimerActivities(for profile: BlockedProfiles) {
    let scheduleTimerActivity = ScheduleTimerActivity()
    let deviceActivityName = scheduleTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
  }

  static func removeScheduleTimerActivities(for activity: DeviceActivityName) {
    stopActivities(for: [activity])
  }

  static func removeAllBreakTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let breakTimerActivity = BreakTimerActivity()
    let breakTimerActivities = breakTimerActivity.getAllBreakTimerActivities(from: activities)
    stopActivities(for: breakTimerActivities, with: center)
  }

  static func removeBreakTimerActivity(for profile: BlockedProfiles) {
    let breakTimerActivity = BreakTimerActivity()
    let deviceActivityName = breakTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
  }

  static func removeAllStrategyTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let strategyTimerActivity = StrategyTimerActivity()
    let strategyTimerActivities = strategyTimerActivity.getAllStrategyTimerActivities(
      from: activities)
    stopActivities(for: strategyTimerActivities, with: center)
  }

  static func startPauseTimerActivity(for profile: BlockedProfiles) {
    do {
      try schedulePauseTimerActivity(for: profile)
    } catch {
      print("Failed to start pause timer activity: \(error.localizedDescription)")
    }
  }

  static func schedulePauseTimerActivity(for profile: BlockedProfiles) throws {
    let pauseData = StrategyPauseTimerData.toStrategyPauseTimerData(from: profile.strategyData)

    let center = DeviceActivityCenter()
    let pauseTimerActivity = PauseTimerActivity()
    let deviceActivityName = pauseTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(
      from: TimeInterval(pauseData.pauseDurationInMinutes * 60))

    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    stopActivities(for: [deviceActivityName], with: center)
    try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
    print("Scheduled pause timer activity from \(intervalStart) to \(intervalEnd)")
  }

  static func removePauseTimerActivity(for profile: BlockedProfiles) {
    let pauseTimerActivity = PauseTimerActivity()
    let deviceActivityName = pauseTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
  }

  static func removeAllPauseTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let pauseTimerActivity = PauseTimerActivity()
    let pauseTimerActivities = pauseTimerActivity.getAllPauseTimerActivities(from: activities)
    stopActivities(for: pauseTimerActivities, with: center)
  }

  static func getActivePauseTimerActivity(for profile: BlockedProfiles) -> DeviceActivityName? {
    let center = DeviceActivityCenter()
    let pauseTimerActivity = PauseTimerActivity()
    let activities = center.activities

    return activities.first(where: {
      $0 == pauseTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    })
  }

  static func getActiveScheduleTimerActivity(for profile: BlockedProfiles) -> DeviceActivityName? {
    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let activities = center.activities

    return activities.first(where: {
      $0 == scheduleTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    })
  }

  static func getDeviceActivities() -> [DeviceActivityName] {
    let center = DeviceActivityCenter()
    return center.activities
  }

  private static func stopActivities(
    for activities: [DeviceActivityName], with center: DeviceActivityCenter? = nil
  ) {
    let center = center ?? DeviceActivityCenter()

    if activities.isEmpty {
      // No activities to stop
      print("No activities to stop")
      return
    }

    center.stopMonitoring(activities)
  }

  private static func getTimeIntervalStartAndEnd(from durationInSeconds: TimeInterval) -> (
    intervalStart: DateComponents, intervalEnd: DateComponents
  ) {
    let intervalStart = DateComponents(hour: 0, minute: 0, second: 0)

    let now = Date()
    let safeDuration = max(1, durationInSeconds)
    let endDate = min(
      now.addingTimeInterval(safeDuration),
      Calendar.current.startOfDay(for: now).addingTimeInterval((24 * 60 * 60) - 1)
    )
    let intervalEnd = Calendar.current.dateComponents([.hour, .minute, .second], from: endDate)
    return (intervalStart: intervalStart, intervalEnd: intervalEnd)
  }
}
