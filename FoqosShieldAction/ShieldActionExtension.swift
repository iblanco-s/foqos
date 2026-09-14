import FamilyControls
import Foundation
import ManagedSettings
import OSLog

private let log = Logger(
  subsystem: "dev.ambitionsoftware.foqos",
  category: "SoftUnblockShieldAction"
)

class ShieldActionExtension: ShieldActionDelegate {
  override func handle(
    action: ShieldAction,
    for application: ApplicationToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    handle(
      action: action,
      resource: .application(application),
      completionHandler: completionHandler
    )
  }

  override func handle(
    action: ShieldAction,
    for webDomain: WebDomainToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    completionHandler(.close)
  }

  override func handle(
    action: ShieldAction,
    for category: ActivityCategoryToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    handle(
      action: action,
      resource: .category(category),
      completionHandler: completionHandler
    )
  }

  private func handle(
    action: ShieldAction,
    resource: SoftUnblockResource,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    guard action == .primaryButtonPressed else {
      completionHandler(.close)
      return
    }

    // Existing session-based temporary access takes precedence.
    if let session = SoftUnblockGrantStore.activeSession,
      let snapshot = SharedData.snapshot(for: session.profileId.uuidString)
    {
      if !(snapshot.enableAllowMode && isCategory(resource)) {
        let configuration = SoftUnblockStrategyData.decode(snapshot.strategyData)
        let durationInMinutes = max(configuration.accessDurationInMinutes, 1)
        let now = Date()
        let grant = SoftUnblockGrant(
          id: UUID(),
          sessionId: session.sessionId,
          profileId: session.profileId,
          resource: resource,
          createdAt: now,
          expiresAt: now.addingTimeInterval(TimeInterval(durationInMinutes * 60))
        )

        if SoftUnblockGrantStore.issue(grant) {
          do {
            try SoftUnblockGrantScheduler.scheduleGrant(grant)
          } catch {
            SoftUnblockGrantStore.rollbackIssuedGrant(
              id: grant.id,
              sessionId: grant.sessionId
            )
            log.error("Failed to schedule a soft-unblock grant: \(error.localizedDescription)")
          }
        }
      }
      completionHandler(.close)
      return
    }

    // Daily app limits (no session required): each primary-button tap consumes
    // one open and grants temporary access to the tapped app/category.
    handleAppLimit(resource: resource)
    completionHandler(.close)
  }

  private func isCategory(_ resource: SoftUnblockResource) -> Bool {
    if case .category = resource { return true }
    return false
  }

  private func handleAppLimit(resource: SoftUnblockResource) {
    guard let profile = matchingLimitProfile(for: resource) else { return }
    // Time is up: hard block, no more opens even when some remain.
    if AppLimitStore.isTimeExceeded(for: profile) { return }
    guard AppLimitStore.remainingOpens(for: profile) > 0 else { return }

    guard let grant = AppLimitStore.recordOpen(for: profile, resource: resource) else {
      return
    }

    do {
      try AppLimitGrantScheduler.scheduleGrant(grant)
    } catch {
      AppLimitStore.removeGrant(id: grant.id, profileId: grant.profileId)
      log.error("Failed to schedule an app-limit grant: \(error.localizedDescription)")
      return
    }

    // Unshield the granted app immediately so the next tap opens it.
    if let current = SharedData.snapshot(for: profile.id.uuidString) {
      AppBlockerUtil().activateRestrictionsForAppLimit(for: current)
    }
  }

  private func matchingLimitProfile(for resource: SoftUnblockResource)
    -> SharedData.ProfileSnapshot?
  {
    let snapshots = SharedData.profileSnapshots.values.filter { $0.hasAppOpenLimit }
    switch resource {
    case .application(let token):
      return snapshots.first { snapshot in
        !snapshot.enableAllowMode
          && snapshot.selectedActivity.applicationTokens.contains(token)
          && !AppLimitStore.hasActiveGrant(
            for: resource, profileId: snapshot.id)
      } ?? snapshots.first { snapshot in
        !snapshot.enableAllowMode
          && snapshot.selectedActivity.applicationTokens.contains(token)
      }
    case .category(let token):
      return snapshots.first { snapshot in
        !snapshot.enableAllowMode
          && snapshot.selectedActivity.categoryTokens.contains(token)
          && !AppLimitStore.hasActiveGrant(
            for: resource, profileId: snapshot.id)
      } ?? snapshots.first { snapshot in
        !snapshot.enableAllowMode
          && snapshot.selectedActivity.categoryTokens.contains(token)
      }
    }
  }
}
