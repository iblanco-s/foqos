import ManagedSettings

class AppBlockerUtil {
  let store = ManagedSettingsStore(
    named: ManagedSettingsStore.Name("foqosAppRestrictions")
  )

  func activateRestrictions(for profile: SharedData.ProfileSnapshot) {
    let selection = profile.selectedActivity
    applyRestrictions(
      for: profile,
      applicationTokens: selection.applicationTokens,
      categoryTokens: selection.categoryTokens,
      categoryApplicationExceptions: []
    )
  }

  func activateSoftUnblockRestrictions(
    for profile: SharedData.ProfileSnapshot,
    unblockedApplicationTokens: Set<ApplicationToken>,
    unblockedCategoryTokens: Set<ActivityCategoryToken>
  ) {
    let selection = profile.selectedActivity
    let applicationTokens: Set<ApplicationToken>
    let categoryTokens: Set<ActivityCategoryToken>

    if profile.enableAllowMode {
      applicationTokens = selection.applicationTokens.union(unblockedApplicationTokens)
      categoryTokens = selection.categoryTokens
    } else {
      applicationTokens = selection.applicationTokens.subtracting(unblockedApplicationTokens)
      categoryTokens = selection.categoryTokens.subtracting(unblockedCategoryTokens)
    }

    applyRestrictions(
      for: profile,
      applicationTokens: applicationTokens,
      categoryTokens: categoryTokens,
      categoryApplicationExceptions: unblockedApplicationTokens
    )
  }

  private func applyRestrictions(
    for profile: SharedData.ProfileSnapshot,
    applicationTokens: Set<ApplicationToken>,
    categoryTokens: Set<ActivityCategoryToken>,
    categoryApplicationExceptions: Set<ApplicationToken>
  ) {
    print("Starting restrictions...")

    let selection = profile.selectedActivity
    let allowOnlyApps = profile.enableAllowMode
    let allowOnlyDomains = profile.enableAllowModeDomains
    let strict = profile.enableStrictMode
    let enableSafariBlocking = profile.enableSafariBlocking
    let enableAdultContentBlocking = profile.enableAdultContentBlocking == true
    let domains = getWebDomains(from: profile)

    let webTokens = selection.webDomainTokens

    if allowOnlyApps {
      store.shield.applicationCategories = .all(except: applicationTokens)

      if enableSafariBlocking {
        store.shield.webDomainCategories = .all(except: webTokens)
      }

    } else {
      store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
      store.shield.applicationCategories =
        categoryTokens.isEmpty
        ? nil
        : .specific(
          categoryTokens,
          except: categoryApplicationExceptions
        )

      if enableSafariBlocking {
        store.shield.webDomainCategories = .specific(selection.categoryTokens)
        store.shield.webDomains = webTokens
      }
    }

    if allowOnlyDomains {
      store.webContent.blockedByFilter = .all(except: domains)
    } else if enableAdultContentBlocking {
      store.webContent.blockedByFilter = .auto(domains)
    } else if !domains.isEmpty {
      store.webContent.blockedByFilter = .specific(domains)
    } else {
      store.webContent.blockedByFilter = nil
    }

    store.application.denyAppRemoval = strict
    store.application.denyAppInstallation = profile.enableBlockAppInstallation
  }

  func deactivateRestrictions() {
    print("Stoping restrictions...")

    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil

    store.application.denyAppRemoval = false
    store.application.denyAppInstallation = false

    store.webContent.blockedByFilter = nil

    store.clearAllSettings()
  }

  func deactivateRestrictionsForBreak(for profile: SharedData.ProfileSnapshot) {
    print("Stopping restrictions for break (strict mode: \(profile.enableStrictMode))...")

    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil

    store.webContent.blockedByFilter = nil
    store.application.denyAppInstallation = false

    if !profile.enableStrictMode {
      store.application.denyAppRemoval = false
    }
  }

  func getWebDomains(from profile: SharedData.ProfileSnapshot) -> Set<WebDomain> {
    if let domains = profile.domains {
      return Set(domains.map { WebDomain(domain: $0) })
    }

    return []
  }

  // MARK: - Daily app limits

  /// Applies shields for a single limit profile, respecting open grants and
  /// time-exceeded state. Time-only profiles stay unshielded until the daily
  /// threshold is reached; open-limit profiles stay shielded with per-tap grants.
  func activateRestrictionsForAppLimit(for profile: SharedData.ProfileSnapshot) {
    guard profile.hasAppLimitsEnabled else { return }

    if AppLimitStore.isTimeExceeded(for: profile) {
      // Hard block: time is up, ignore any remaining open grants.
      activateRestrictions(for: profile)
      return
    }

    guard profile.hasAppOpenLimit else {
      // Time-only limit not yet exceeded: leave apps usable so usage accrues.
      return
    }

    let grants = AppLimitStore.activeGrants(for: profile.id)
    let unblockedApps = Set(grants.compactMap(\.resource.applicationToken))
    let unblockedCategories = Set(grants.compactMap(\.resource.categoryToken))
    activateSoftUnblockRestrictions(
      for: profile,
      unblockedApplicationTokens: unblockedApps,
      unblockedCategoryTokens: unblockedCategories
    )
  }

  /// Recomputes shields for every limit profile. Never overrides an active
  /// focus session: sessions own the store while they run.
  /// V1 supports blocklist mode (Allow Only OFF). Allow-mode profiles are
  /// skipped here; their time thresholds still enforce via single-profile
  /// shields in the monitor extension.
  func refreshAllAppLimitRestrictions() {
    if SharedData.getActiveSharedSession() != nil {
      return
    }

    let limitProfiles = SharedData.profileSnapshots.values.filter {
      $0.hasAppLimitsEnabled && !$0.enableAllowMode
    }
    guard !limitProfiles.isEmpty else { return }

    // Time-exceeded profiles always shield fully. Open-limit profiles shield
    // minus their active grants. Time-only profiles that have not exceeded
    // must not shield, so they are skipped unless another profile shields them.
    var shieldedApps = Set<ApplicationToken>()
    var shieldedCategories = Set<ActivityCategoryToken>()
    var grantExceptions = Set<ApplicationToken>()
    var representative: SharedData.ProfileSnapshot?

    for profile in limitProfiles {
      AppLimitStore.resetDayIfNeeded(for: profile.id)
      if AppLimitStore.isTimeExceeded(for: profile) {
        shieldedApps.formUnion(profile.selectedActivity.applicationTokens)
        shieldedCategories.formUnion(profile.selectedActivity.categoryTokens)
        representative = representative ?? profile
      } else if profile.hasAppOpenLimit {
        shieldedApps.formUnion(profile.selectedActivity.applicationTokens)
        shieldedCategories.formUnion(profile.selectedActivity.categoryTokens)
        for grant in AppLimitStore.activeGrants(for: profile.id) {
          if let app = grant.resource.applicationToken {
            grantExceptions.insert(app)
          }
        }
        representative = representative ?? profile
      }
    }

    guard let base = representative else {
      // No profile currently requires shielding (e.g. time-only limits with
      // remaining budget). Do not clear: another feature may own the store.
      return
    }

    shieldedApps.subtract(grantExceptions)
    activateSoftUnblockRestrictions(
      for: base,
      unblockedApplicationTokens: grantExceptions,
      unblockedCategoryTokens: []
    )
    // activateSoftUnblockRestrictions uses base's selection; when multiple
    // limit profiles exist we union explicitly afterwards.
    if !shieldedApps.isEmpty {
      store.shield.applications = shieldedApps
    }
    if !shieldedCategories.isEmpty {
      store.shield.applicationCategories = .specific(shieldedCategories, except: grantExceptions)
    }
  }

  /// Clears limit shields only when no limit profile still needs them and no
  /// focus session is active. Used at midnight reset.
  func clearAppLimitRestrictionsIfIdle() {
    if SharedData.getActiveSharedSession() != nil { return }
    let needsShield = SharedData.profileSnapshots.values.contains { profile in
      guard profile.hasAppLimitsEnabled, !profile.enableAllowMode else { return false }
      if AppLimitStore.isTimeExceeded(for: profile) { return true }
      return profile.hasAppOpenLimit
    }
    if !needsShield {
      deactivateRestrictions()
    } else {
      refreshAllAppLimitRestrictions()
    }
  }
}
