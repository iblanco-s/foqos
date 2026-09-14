import DeviceActivity

class TimerActivityUtil {
  static func startTimerActivity(for activity: DeviceActivityName) {
    let parts = getTimerParts(from: activity)

    guard let timerActivity = getTimerActivity(for: parts.deviceActivityId),
      let profile = getProfile(for: timerActivity.profileId(from: activity))
    else {
      return
    }

    timerActivity.start(for: profile, activityName: activity)
  }

  static func stopTimerActivity(for activity: DeviceActivityName) {
    let parts = getTimerParts(from: activity)

    guard let timerActivity = getTimerActivity(for: parts.deviceActivityId),
      let profile = getProfile(for: timerActivity.profileId(from: activity))
    else {
      return
    }

    timerActivity.stop(for: profile, activityName: activity)
  }

  static func appLimitThresholdReached(
    event: DeviceActivityEvent.Name, for activity: DeviceActivityName
  ) {
    // Event names are "AppLimitUsageEvent.<profileUUID>".
    let profileId = event.rawValue.split(separator: ".").last.map(String.init)
      ?? TimerActivityUtil.getTimerParts(from: activity).profileId
    guard let profile = getProfile(for: profileId),
      profile.hasAppTimeLimit
    else {
      return
    }
    AppLimitTimerActivity().eventThresholdReached(for: profile)
  }

  private static func getTimerParts(from activity: DeviceActivityName) -> (
    deviceActivityId: String, profileId: String
  ) {
    let activityName = activity.rawValue
    let components = activityName.split(separator: ":", maxSplits: 1)

    // For versions >= 1.24, the activity name format is "type:profileId"
    if components.count == 2 {
      return (deviceActivityId: String(components[0]), profileId: String(components[1]))
    }

    // For versions < 1.24, the activity name format is just "profileId" and only supports schedule timer activity
    // This is to support backward compatibility for older schedules
    return (deviceActivityId: ScheduleTimerActivity.id, profileId: activityName)
  }

  private static func getTimerActivity(for deviceActivityId: String) -> TimerActivity? {
    switch deviceActivityId {
    case ScheduleTimerActivity.id:
      return ScheduleTimerActivity()
    case BreakTimerActivity.id:
      return BreakTimerActivity()
    case StrategyTimerActivity.id:
      return StrategyTimerActivity()
    case PauseTimerActivity.id:
      return PauseTimerActivity()
    case SoftUnblockGrantTimerActivity.id:
      return SoftUnblockGrantTimerActivity()
    case AppLimitTimerActivity.id:
      return AppLimitTimerActivity()
    case AppLimitGrantTimerActivity.id:
      return AppLimitGrantTimerActivity()
    default:
      return nil
    }
  }

  private static func getProfile(for profileId: String) -> SharedData.ProfileSnapshot? {
    return SharedData.snapshot(for: profileId)
  }
}
