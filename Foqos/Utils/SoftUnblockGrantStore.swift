import Foundation

enum SoftUnblockGrantStore {
  struct DebugSnapshot: Equatable {
    let activeSession: SoftUnblockSessionState?
    let hasStoredActiveSession: Bool
    let grants: [SoftUnblockGrant]
    let storedGrantEntryCount: Int
    let undecodableGrantKeys: [String]
  }

  private static let suite = UserDefaults(
    suiteName: "group.dev.ambitionsoftware.foqos"
  )!

  private static let activeSessionKey = "softUnblock.activeSession"
  private static let grantKeyPrefix = "softUnblock.grant."

  static var activeSession: SoftUnblockSessionState? {
    currentSession(at: Date())
  }

  static func currentSession(at date: Date) -> SoftUnblockSessionState? {
    guard let data = suite.data(forKey: activeSessionKey) else { return nil }
    guard var session = try? JSONDecoder().decode(SoftUnblockSessionState.self, from: data) else {
      return nil
    }

    if session.resetAllowanceIfNeeded(at: date) {
      saveActiveSession(session)
    }

    return session
  }

  static func beginSession(
    sessionId: String,
    profileId: UUID,
    maximumUnblockCount: Int,
    allowanceResetIntervalInHours: Int?,
    startedAt: Date
  ) {
    clearAll()

    let resetInterval = normalizedResetInterval(allowanceResetIntervalInHours)
    let state = SoftUnblockSessionState(
      sessionId: sessionId,
      profileId: profileId,
      maximumUnblockCount: min(
        max(maximumUnblockCount, SoftUnblockSessionState.maximumUnblockCountRange.lowerBound),
        SoftUnblockSessionState.maximumUnblockCountRange.upperBound
      ),
      allowanceResetIntervalInHours: resetInterval,
      allowanceWindowStartedAt: startedAt,
      nextAllowanceResetAt: resetInterval.map {
        startedAt.addingTimeInterval(TimeInterval($0 * 60 * 60))
      },
      usedUnblockCount: 0
    )
    saveActiveSession(state)
  }

  static func issue(_ grant: SoftUnblockGrant) -> Bool {
    guard var session = currentSession(at: grant.createdAt),
      session.sessionId == grant.sessionId,
      session.profileId == grant.profileId,
      session.remainingUnblockCount > 0,
      let grantData = try? JSONEncoder().encode(grant)
    else {
      return false
    }

    session.usedUnblockCount += 1
    guard let sessionData = try? JSONEncoder().encode(session) else { return false }

    suite.set(grantData, forKey: grantKey(sessionId: grant.sessionId, grantId: grant.id))
    suite.set(sessionData, forKey: activeSessionKey)
    return true
  }

  static func rollbackIssuedGrant(id: UUID, sessionId: String) {
    guard let issuedGrant = grant(id: id, sessionId: sessionId) else { return }
    removeGrant(id: id, sessionId: sessionId)

    guard var session = activeSession,
      session.sessionId == sessionId,
      session.containsAllowanceUse(createdAt: issuedGrant.createdAt),
      session.usedUnblockCount > 0
    else {
      return
    }

    session.usedUnblockCount -= 1
    saveActiveSession(session)
  }

  static func grant(id: UUID, sessionId: String) -> SoftUnblockGrant? {
    let key = grantKey(sessionId: sessionId, grantId: id)
    guard let data = suite.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(SoftUnblockGrant.self, from: data)
  }

  static func activeGrants(
    for profileId: UUID,
    at date: Date = Date()
  ) -> [SoftUnblockGrant] {
    guard let activeSession = currentSession(at: date), activeSession.profileId == profileId else {
      return []
    }

    return grants(for: activeSession.sessionId).filter { !$0.isExpired(at: date) }
  }

  static func hasActiveGrant(
    for resource: SoftUnblockResource,
    profileId: UUID,
    at date: Date = Date()
  ) -> Bool {
    activeGrants(for: profileId, at: date).contains { $0.resource == resource }
  }

  static func removeGrant(id: UUID, sessionId: String) {
    suite.removeObject(forKey: grantKey(sessionId: sessionId, grantId: id))
  }

  static func endSession(sessionId: String) {
    removeGrants(for: sessionId)

    guard activeSession?.sessionId == sessionId else { return }
    suite.removeObject(forKey: activeSessionKey)
  }

  static func clearAll() {
    for key in suite.dictionaryRepresentation().keys where key.hasPrefix(grantKeyPrefix) {
      suite.removeObject(forKey: key)
    }
    suite.removeObject(forKey: activeSessionKey)
  }

  static func isActive(sessionId: String, profileId: UUID) -> Bool {
    guard let activeSession else { return false }
    return activeSession.sessionId == sessionId && activeSession.profileId == profileId
  }

  static func debugSnapshot() -> DebugSnapshot {
    let storedValues = suite.dictionaryRepresentation()
    let grantEntries = storedValues.filter { key, _ in
      key.hasPrefix(grantKeyPrefix)
    }
    var grants: [SoftUnblockGrant] = []
    var undecodableGrantKeys: [String] = []

    for (key, value) in grantEntries {
      guard let data = value as? Data,
        let grant = try? JSONDecoder().decode(SoftUnblockGrant.self, from: data)
      else {
        undecodableGrantKeys.append(key)
        continue
      }

      grants.append(grant)
    }

    return DebugSnapshot(
      activeSession: activeSession,
      hasStoredActiveSession: storedValues[activeSessionKey] != nil,
      grants: grants.sorted { $0.createdAt < $1.createdAt },
      storedGrantEntryCount: grantEntries.count,
      undecodableGrantKeys: undecodableGrantKeys.sorted()
    )
  }

  private static func grants(for sessionId: String) -> [SoftUnblockGrant] {
    let prefix = grantSessionKeyPrefix(sessionId: sessionId)

    return suite.dictionaryRepresentation().compactMap { key, value in
      guard key.hasPrefix(prefix), let data = value as? Data else { return nil }
      return try? JSONDecoder().decode(SoftUnblockGrant.self, from: data)
    }
  }

  private static func removeGrants(for sessionId: String) {
    let prefix = grantSessionKeyPrefix(sessionId: sessionId)
    for key in suite.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      suite.removeObject(forKey: key)
    }
  }

  private static func grantSessionKeyPrefix(sessionId: String) -> String {
    "\(grantKeyPrefix)\(sessionId)."
  }

  private static func grantKey(sessionId: String, grantId: UUID) -> String {
    "\(grantSessionKeyPrefix(sessionId: sessionId))\(grantId.uuidString)"
  }

  private static func saveActiveSession(_ session: SoftUnblockSessionState) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    suite.set(data, forKey: activeSessionKey)
  }

  private static func normalizedResetInterval(_ interval: Int?) -> Int? {
    guard let interval,
      SoftUnblockSessionState.allowanceResetIntervalRangeInHours.contains(interval)
    else {
      return nil
    }
    return interval
  }
}

// MARK: - Daily app limits (time + opens), independent of focus sessions.
//
// Per-profile state stored in the shared App Group so the main app,
// DeviceActivity monitor, Shield Action and Shield Config all see the same
// counters. One entry per profile, keyed by profile UUID string, reset at
// local midnight. No DeviceActivity import here on purpose: this file is also
// compiled into the Widget extension which does not link DeviceActivity.
struct AppLimitDailyState: Codable, Equatable {
  var dateKey: String
  var usedOpens: Int
  var timeLimitExceeded: Bool
}

struct AppLimitOpenGrant: Codable, Equatable, Identifiable {
  let id: UUID
  let profileId: UUID
  let resource: SoftUnblockResource
  let createdAt: Date
  let expiresAt: Date

  func isExpired(at date: Date = Date()) -> Bool {
    expiresAt <= date
  }
}

enum AppLimitStore {
  private static let suite = UserDefaults(
    suiteName: "group.dev.ambitionsoftware.foqos"
  )!

  private static let stateKeyPrefix = "applimit.state."
  private static let grantKeyPrefix = "applimit.grant."

  static func dateKey(for date: Date = Date()) -> String {
    let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
  }

  static func currentState(for profileId: UUID, at date: Date = Date())
    -> AppLimitDailyState
  {
    let key = stateKeyPrefix + profileId.uuidString
    let today = dateKey(for: date)
    if let data = suite.data(forKey: key),
      let stored = try? JSONDecoder().decode(AppLimitDailyState.self, from: data),
      stored.dateKey == today
    {
      return stored
    }
    return AppLimitDailyState(dateKey: today, usedOpens: 0, timeLimitExceeded: false)
  }

  static func remainingOpens(for profile: SharedData.ProfileSnapshot, at date: Date = Date())
    -> Int
  {
    guard profile.hasAppOpenLimit, let limit = profile.dailyOpenLimit else { return 0 }
    let state = currentState(for: profile.id, at: date)
    return max(limit - state.usedOpens, 0)
  }

  static func isTimeExceeded(for profile: SharedData.ProfileSnapshot, at date: Date = Date())
    -> Bool
  {
    guard profile.hasAppTimeLimit else { return false }
    return currentState(for: profile.id, at: date).timeLimitExceeded
  }

  static func isBlockedByLimit(for profile: SharedData.ProfileSnapshot, at date: Date = Date())
    -> Bool
  {
    guard profile.hasAppLimitsEnabled else { return false }
    if isTimeExceeded(for: profile, at: date) { return true }
    if profile.hasAppOpenLimit {
      // Open-limit profiles stay shielded; each tap consumes one open.
      // Active grants temporarily unshield a single app/category.
      return true
    }
    return false
  }

  /// Records one open for a limit profile. Returns the grant when allowed.
  static func recordOpen(
    for profile: SharedData.ProfileSnapshot,
    resource: SoftUnblockResource,
    at date: Date = Date()
  ) -> AppLimitOpenGrant? {
    guard profile.hasAppOpenLimit else { return nil }
    guard remainingOpens(for: profile, at: date) > 0 else { return nil }
    guard !hasActiveGrant(for: resource, profileId: profile.id, at: date) else {
      return activeGrants(for: profile.id, at: date).first { $0.resource == resource }
    }

    var state = currentState(for: profile.id, at: date)
    state.usedOpens += 1
    saveState(state, for: profile.id)

    let duration = TimeInterval(
      max(profile.resolvedAppLimitOpenDurationInMinutes, 1) * 60)
    let grant = AppLimitOpenGrant(
      id: UUID(),
      profileId: profile.id,
      resource: resource,
      createdAt: date,
      expiresAt: date.addingTimeInterval(duration)
    )
    guard let data = try? JSONEncoder().encode(grant) else {
      // Roll back the counter when persistence fails.
      var rollback = currentState(for: profile.id, at: date)
      rollback.usedOpens = max(rollback.usedOpens - 1, 0)
      saveState(rollback, for: profile.id)
      return nil
    }
    suite.set(data, forKey: grantKey(profileId: profile.id, grantId: grant.id))
    return grant
  }

  static func setTimeExceeded(for profileId: UUID, at date: Date = Date()) {
    var state = currentState(for: profileId, at: date)
    state.timeLimitExceeded = true
    saveState(state, for: profileId)
  }

  static func resetDayIfNeeded(for profileId: UUID, at date: Date = Date()) {
    // Accessing currentState recreates a fresh entry when the day changed.
    _ = currentState(for: profileId, at: date)
    removeExpiredGrants(for: profileId, at: date)
  }

  static func activeGrants(for profileId: UUID, at date: Date = Date())
    -> [AppLimitOpenGrant]
  {
    grants(for: profileId).filter { !$0.isExpired(at: date) }
  }

  static func hasActiveGrant(
    for resource: SoftUnblockResource,
    profileId: UUID,
    at date: Date = Date()
  ) -> Bool {
    activeGrants(for: profileId, at: date).contains { $0.resource == resource }
  }

  static func removeGrant(id: UUID, profileId: UUID) {
    suite.removeObject(forKey: grantKey(profileId: profileId, grantId: id))
  }

  static func removeExpiredGrants(for profileId: UUID, at date: Date = Date()) {
    for grant in grants(for: profileId) where grant.isExpired(at: date) {
      removeGrant(id: grant.id, profileId: profileId)
    }
  }

  static func removeState(for profileId: UUID) {
    suite.removeObject(forKey: stateKeyPrefix + profileId.uuidString)
    let prefix = grantSessionKeyPrefix(profileId: profileId)
    for key in suite.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      suite.removeObject(forKey: key)
    }
  }

  private static func saveState(_ state: AppLimitDailyState, for profileId: UUID) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    suite.set(data, forKey: stateKeyPrefix + profileId.uuidString)
  }

  private static func grants(for profileId: UUID) -> [AppLimitOpenGrant] {
    let prefix = grantSessionKeyPrefix(profileId: profileId)
    return suite.dictionaryRepresentation().compactMap { key, value in
      guard key.hasPrefix(prefix), let data = value as? Data else { return nil }
      return try? JSONDecoder().decode(AppLimitOpenGrant.self, from: data)
    }
  }

  private static func grantSessionKeyPrefix(profileId: UUID) -> String {
    "\(grantKeyPrefix)\(profileId.uuidString)."
  }

  private static func grantKey(profileId: UUID, grantId: UUID) -> String {
    "\(grantSessionKeyPrefix(profileId: profileId))\(grantId.uuidString)"
  }
}
