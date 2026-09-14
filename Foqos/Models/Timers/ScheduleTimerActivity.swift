import DeviceActivity
import OSLog

private let log: Logger = Logger(subsystem: "com.foqos.monitor", category: ScheduleTimerActivity.id)

class ScheduleTimerActivity: TimerActivity {
  static var id: String = "ScheduleTimerActivity"

  private let appBlocker = AppBlockerUtil()

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    // Since schedules were implemented before the timer activities, the profile id is used as the device activity name for
    // backward compatibility
    return DeviceActivityName(rawValue: profileId)
  }

  func getAllScheduleTimerActivities(from activities: [DeviceActivityName]) -> [DeviceActivityName]
  {
    // Schedule timer activities use just the profile UUID as the rawValue (no prefix)
    // Other activities use prefixes like "BreakScheduleActivity:" or "StrategyTimerActivity:"
    return activities.filter { activity in
      let rawValue = activity.rawValue
      // If it contains ":", it's a prefixed activity (break or strategy timer), not a schedule
      guard !rawValue.contains(":") else { return false }
      // Must be a valid UUID
      return UUID(uuidString: rawValue) != nil
    }
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    guard let schedule = profile.schedule
    else {
      log.info("Start schedule timer activity for \(profileId), no schedule for profile found")
      return
    }

    if !schedule.isTodayScheduled() {
      log.info(
        "Start schedule timer activity for \(profileId), schedule is not scheduled for today")
      return
    }

    if !schedule.olderThan15Minutes() {
      log.info("Start schedule timer activity for \(profileId), schedule is too new")
      return
    }

    log.info("Start schedule timer activity for \(profileId), profile: \(profileId)")

    if let existingSession = SharedData.getActiveSharedSession() {
      if existingSession.blockedProfileId == profile.id {
        log.info(
          "Start schedule timer activity for \(profileId), existing session profile matches device activity profile, continuing active session"
        )
        return
      } else {
        log.info(
          "Start schedule timer activity for \(profileId), existing session profile does not match device activity profile, ending active session"
        )
        SharedData.endActiveSharedSession()
      }
    }

    // Create a new active scheduled session for the profile
    let session = SharedData.createSessionForSchedular(for: profile.id)
    BlockingSessionLifecycleRegistry.sessionDidStart(
      BlockingSessionLifecycleContext(
        profile: profile,
        session: session
      )
    )

    // Start restrictions
    appBlocker.activateRestrictions(for: profile)
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    guard let activeSession = SharedData.getActiveSharedSession() else {
      log.info("Stop schedule timer activity for \(profileId), no active session found")
      return
    }

    // Check to make sure the active session is the same as the profile before disabling restrictions
    if activeSession.blockedProfileId != profile.id {
      log.info(
        "Stop schedule timer activity for \(profileId), active session profile does not match device activity profile"
      )
      return
    }

    BlockingSessionLifecycleRegistry.sessionDidEnd(
      BlockingSessionLifecycleContext(
        profile: profile,
        session: activeSession
      )
    )

    // End restrictions
    appBlocker.deactivateRestrictions()

    // End the active scheduled session
    SharedData.endActiveSharedSession()
  }

  func getScheduleInterval(from schedule: BlockedProfileSchedule) -> (
    intervalStart: DateComponents, intervalEnd: DateComponents
  ) {
    let intervalStart = DateComponents(hour: schedule.startHour, minute: schedule.startMinute)
    let intervalEnd = DateComponents(hour: schedule.endHour, minute: schedule.endMinute)
    return (intervalStart: intervalStart, intervalEnd: intervalEnd)
  }
}

// MARK: - Daily app limits (time + opens), independent of focus sessions.
class AppLimitTimerActivity: TimerActivity {
  static var id: String = "AppLimitTimerActivity"

  private let appBlocker = AppBlockerUtil()

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    DeviceActivityName(rawValue: "\(AppLimitTimerActivity.id):\(profileId)")
  }

  func getAllAppLimitActivities(from activities: [DeviceActivityName]) -> [DeviceActivityName] {
    activities.filter { $0.rawValue.hasPrefix(AppLimitTimerActivity.id) }
  }

  func profileId(from activityName: DeviceActivityName) -> String {
    let components = activityName.rawValue.split(separator: ":", maxSplits: 1)
    if components.count == 2 {
      return String(components[1])
    }
    return activityName.rawValue
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString
    log.info("Start app limit activity for \(profileId)")
    AppLimitStore.resetDayIfNeeded(for: profile.id)
    guard SharedData.getActiveSharedSession() == nil else {
      log.info("Start app limit activity for \(profileId), session active, skipping")
      return
    }
    appBlocker.activateRestrictionsForAppLimit(for: profile)
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString
    log.info("Stop app limit activity for \(profileId)")
    AppLimitStore.removeExpiredGrants(for: profile.id)
  }

  func eventThresholdReached(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString
    log.info("App limit time threshold reached for \(profileId)")
    AppLimitStore.setTimeExceeded(for: profile.id)
    guard SharedData.getActiveSharedSession() == nil else {
      log.info("App limit threshold for \(profileId), session active, skipping shields")
      return
    }
    appBlocker.activateRestrictions(for: profile)
  }
}

// MARK: - Temporary open grants for app limits.
class AppLimitGrantTimerActivity: TimerActivity {
  static var id: String = "AppLimitGrantTimerActivity"

  private let appBlocker = AppBlockerUtil()

  func profileId(from activityName: DeviceActivityName) -> String {
    AppLimitGrantScheduler.identifiers(from: activityName)?.profileId.uuidString ?? ""
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    log.info("Start app limit grant without identifiers, ignoring")
  }

  func start(for profile: SharedData.ProfileSnapshot, activityName: DeviceActivityName) {
    guard AppLimitGrantScheduler.identifiers(from: activityName) != nil else { return }
    guard SharedData.getActiveSharedSession() == nil else { return }
    appBlocker.activateRestrictionsForAppLimit(for: profile)
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    log.info("Stop app limit grant without identifiers, ignoring")
  }

  func stop(for profile: SharedData.ProfileSnapshot, activityName: DeviceActivityName) {
    guard let identifiers = AppLimitGrantScheduler.identifiers(from: activityName) else { return }
    // Grant expired: drop it and re-shield the profile.
    AppLimitStore.removeGrant(id: identifiers.grantId, profileId: identifiers.profileId)
    guard SharedData.getActiveSharedSession() == nil else { return }
    if let current = SharedData.snapshot(for: identifiers.profileId.uuidString) {
      appBlocker.activateRestrictionsForAppLimit(for: current)
    } else {
      appBlocker.activateRestrictionsForAppLimit(for: profile)
    }
  }
}
