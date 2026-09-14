//
//  ShieldConfigurationExtension.swift
//  FoqosShieldConfig
//
//  Created by Ali Waseem on 2025-08-11.
//

import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import SwiftUI
import UIKit

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    if let softUnblockConfiguration = softUnblockConfiguration(for: application, in: nil) {
      return softUnblockConfiguration
    }

    if let limitConfiguration = appLimitConfiguration(for: application, in: nil) {
      return limitConfiguration
    }

    return createCustomShieldConfiguration(
      for: .app, title: application.localizedDisplayName ?? "App")
  }

  override func configuration(shielding application: Application, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    if let softUnblockConfiguration = softUnblockConfiguration(for: application, in: category) {
      return softUnblockConfiguration
    }

    if let limitConfiguration = appLimitConfiguration(for: application, in: category) {
      return limitConfiguration
    }

    return createCustomShieldConfiguration(
      for: .app, title: application.localizedDisplayName ?? "App")
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    return createCustomShieldConfiguration(for: .website, title: webDomain.domain ?? "Website")
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    return createCustomShieldConfiguration(for: .website, title: webDomain.domain ?? "Website")
  }

  private func createCustomShieldConfiguration(for type: BlockedContentType, title: String)
    -> ShieldConfiguration
  {
    // Get user's selected theme color
    let brandColor = UIColor(ThemeManager.shared.themeColor)

    // Get random fun message
    let randomMessage = getFunBlockMessage(for: type, title: title)

    // Emoji “icon” (rendered to an image so it works with ShieldConfiguration.icon)
    let emojiIcon = makeEmojiIcon(randomMessage.emoji, size: 96)

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: brandColor,
      icon: emojiIcon,
      title: ShieldConfiguration.Label(
        text: randomMessage.title,
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: withPendingTasks(randomMessage.subtitle),
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: randomMessage.buttonText,
        color: .black
      ),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: nil
    )
  }

  /// Appends pending tasks (if any) so the user sees what to do instead.
  private func withPendingTasks(_ subtitle: String) -> String {
    guard let block = SharedData.pendingTasksShieldBlock() else { return subtitle }
    return subtitle + "\n\n" + block
  }

  private func softUnblockConfiguration(
    for application: Application,
    in category: ActivityCategory?
  ) -> ShieldConfiguration? {
    guard let session = SoftUnblockGrantStore.activeSession,
      let snapshot = SharedData.snapshot(for: session.profileId.uuidString),
      let presentation = softUnblockPresentation(
        for: application,
        in: category,
        profile: snapshot
      ),
      !SoftUnblockGrantStore.hasActiveGrant(
        for: presentation.resource,
        profileId: session.profileId
      )
    else {
      return nil
    }

    let configuration = SoftUnblockStrategyData.decode(snapshot.strategyData)
    guard session.remainingUnblockCount > 0 else {
      return exhaustedSoftUnblockConfiguration(session: session)
    }

    let accessMinutes = configuration.accessDurationInMinutes
    let buttonText = "Open for \(accessMinutes)m"
    let randomMessage = getFunBlockMessage(
      for: .app,
      title: application.localizedDisplayName ?? presentation.resourceName
    )
    var allowanceLines = [
      "\(presentation.resourceName) (\(session.remainingUnblockCount)/\(session.maximumUnblockCount))",
      breakAllowanceIndicator(for: session),
    ]
    if let resetDescription = allowanceResetDescription(for: session) {
      allowanceLines.append(resetDescription)
    }
    let subtitle = [randomMessage.subtitle, allowanceLines.joined(separator: "\n")]
      .joined(separator: "\n\n")

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: UIColor(ThemeManager.shared.themeColor),
      icon: makeEmojiIcon(randomMessage.emoji, size: 96),
      title: ShieldConfiguration.Label(
        text: randomMessage.title,
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: withPendingTasks(subtitle),
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: buttonText,
        color: .black
      ),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: "Back",
        color: .white
      )
    )
  }

  private func exhaustedSoftUnblockConfiguration(
    session: SoftUnblockSessionState
  ) -> ShieldConfiguration {
    let usageText =
      session.maximumUnblockCount == 1
      ? "You already used your open for this session."
      : "You used all \(session.maximumUnblockCount) opens for this session."
    let subtitle = [usageText, allowanceResetDescription(for: session)]
      .compactMap { $0 }
      .joined(separator: " ")

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: UIColor(ThemeManager.shared.themeColor),
      icon: makeEmojiIcon("🔒", size: 96),
      title: ShieldConfiguration.Label(
        text: "No opens left",
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: withPendingTasks(subtitle),
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: "Back",
        color: .black
      ),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: nil
    )
  }

  private func allowanceResetDescription(for session: SoftUnblockSessionState) -> String? {
    guard session.allowanceResetIntervalInHours != nil,
      let nextAllowanceResetAt = session.nextAllowanceResetAt
    else {
      return nil
    }

    let remainingMinutes = max(
      Int(ceil(nextAllowanceResetAt.timeIntervalSinceNow / 60)),
      1
    )
    if remainingMinutes >= 60 {
      return "Resets in \(remainingMinutes / 60)h"
    }
    return "Resets in \(remainingMinutes)m"
  }

  private func breakAllowanceIndicator(for session: SoftUnblockSessionState) -> String {
    let availableBreaks = Array(
      repeating: "●",
      count: session.remainingUnblockCount
    )
    let usedBreaks = Array(
      repeating: "○",
      count: session.maximumUnblockCount - session.remainingUnblockCount
    )
    return (availableBreaks + usedBreaks).joined(separator: "  ")
  }

  // MARK: - Daily app limits

  private func appLimitConfiguration(
    for application: Application,
    in category: ActivityCategory?
  ) -> ShieldConfiguration? {
    guard let match = matchingLimitProfile(for: application, in: category) else {
      return nil
    }
    let profile = match.profile
    let resource = match.resource
    let appName = application.localizedDisplayName ?? "This app"

    // Skip when a grant already covers this resource; the shield should lift.
    if AppLimitStore.hasActiveGrant(for: resource, profileId: profile.id) {
      return nil
    }

    if AppLimitStore.isTimeExceeded(for: profile) {
      return ShieldConfiguration(
        backgroundBlurStyle: .dark,
        backgroundColor: UIColor(ThemeManager.shared.themeColor),
        icon: makeEmojiIcon("⏳", size: 96),
        title: ShieldConfiguration.Label(text: "Time's up for today", color: .white),
        subtitle: ShieldConfiguration.Label(
          text: withPendingTasks(
            "\(appName) hit its daily limit in \(profile.name). Fresh budget at midnight."
          ),
          color: UIColor.white.withAlphaComponent(0.88)
        ),
        primaryButtonLabel: ShieldConfiguration.Label(text: "Back", color: .black),
        primaryButtonBackgroundColor: .white,
        secondaryButtonLabel: nil
      )
    }

    guard profile.hasAppOpenLimit else { return nil }
    let remaining = AppLimitStore.remainingOpens(for: profile)
    let minutes = profile.resolvedAppLimitOpenDurationInMinutes

    if remaining <= 0 {
      return ShieldConfiguration(
        backgroundBlurStyle: .dark,
        backgroundColor: UIColor(ThemeManager.shared.themeColor),
        icon: makeEmojiIcon("🔒", size: 96),
        title: ShieldConfiguration.Label(text: "No opens left", color: .white),
        subtitle: ShieldConfiguration.Label(
          text: withPendingTasks(
            "You used all opens for \(appName) in \(profile.name) today. Resets at midnight."
          ),
          color: UIColor.white.withAlphaComponent(0.88)
        ),
        primaryButtonLabel: ShieldConfiguration.Label(text: "Back", color: .black),
        primaryButtonBackgroundColor: .white,
        secondaryButtonLabel: nil
      )
    }

    let dots = limitDots(remaining: remaining, total: profile.dailyOpenLimit ?? remaining)
    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: UIColor(ThemeManager.shared.themeColor),
      icon: makeEmojiIcon("🎯", size: 96),
      title: ShieldConfiguration.Label(text: "Daily limit", color: .white),
      subtitle: ShieldConfiguration.Label(
        text: withPendingTasks(
          "\(appName) · \(remaining) open\(remaining == 1 ? "" : "s") left in \(profile.name)\n\(dots)\nResets at midnight."
        ),
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: "Open for \(minutes)m", color: .black),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: "I'll do a task", color: .white)
    )
  }

  private func matchingLimitProfile(
    for application: Application,
    in category: ActivityCategory?
  ) -> (profile: SharedData.ProfileSnapshot, resource: SoftUnblockResource)? {
    let snapshots = SharedData.profileSnapshots.values.filter { $0.hasAppLimitsEnabled }
    guard !snapshots.isEmpty else { return nil }

    if let categoryToken = category?.token {
      for profile in snapshots {
        if !profile.enableAllowMode
          && profile.selectedActivity.categoryTokens.contains(categoryToken)
        {
          return (profile, .category(categoryToken))
        }
      }
    }
    if let appToken = application.token {
      for profile in snapshots {
        if !profile.enableAllowMode
          && profile.selectedActivity.applicationTokens.contains(appToken)
        {
          return (profile, .application(appToken))
        }
      }
    }
    // Time-only profiles still show "time's up" even for web/category shields
    // matched by app when tokens are unavailable.
    if let timedOut = snapshots.first(where: { AppLimitStore.isTimeExceeded(for: $0) }),
      let appToken = application.token
    {
      return (timedOut, .application(appToken))
    }
    return nil
  }

  private func limitDots(remaining: Int, total: Int) -> String {
    let total = max(total, remaining)
    let available = Array(repeating: "●", count: remaining)
    let used = Array(repeating: "○", count: max(total - remaining, 0))
    return (available + used).joined(separator: "  ")
  }

  private func softUnblockPresentation(
    for application: Application,
    in category: ActivityCategory?,
    profile: SharedData.ProfileSnapshot
  ) -> (resource: SoftUnblockResource, resourceName: String)? {
    if let categoryToken = category?.token {
      guard !profile.enableAllowMode else { return nil }

      let categoryName = category?.localizedDisplayName ?? "this category"
      return (
        resource: .category(categoryToken),
        resourceName: categoryName
      )
    }

    guard let applicationToken = application.token else { return nil }
    let applicationName = application.localizedDisplayName ?? "this app"
    return (
      resource: .application(applicationToken),
      resourceName: applicationName
    )
  }

  private func getFunBlockMessage(for _: BlockedContentType, title: String) -> (
    emoji: String, title: String, subtitle: String, buttonText: String
  ) {
    typealias FunMessage = (emoji: String, title: String, subtitle: String, buttonText: String)

    // Curated message "bundles" where the emoji and copy are designed to match.
    // This keeps things fun without feeling chaotic or mismatched.
    let messages: [FunMessage] = [
      ("📵", "Not right now", "\(title) can wait. You’re choosing your time on purpose.", "Back"),
      ("🧠", "Brain check", "Do you actually want \(title)… or was it autopilot?", "Return"),
      (
        "🎯", "Stay on target", "One small step toward your goal first. Then decide on \(title).",
        "Continue"
      ),
      (
        "⏳", "Give it 2 minutes", "Finish the next tiny thing. \(title) will still be there after.",
        "Keep going"
      ),
      ("🛡️", "Shield up", "Focus is protected. You’ve got this.", "Onward"),
      ("🔒", "Locked in", "This block is temporary. Your momentum isn’t.", "Stay here"),
      ("🧱", "Boundary set", "You made a plan. This is you sticking to it.", "Back"),
      ("✨", "Glow mode", "You’re building attention — that’s the real flex.", "Nice"),
      ("🫶", "Be kind to you", "No shame. Just a gentle nudge back to what matters.", "Got it"),
      (
        "🌐", "Not this detour", "\(title) isn’t part of the mission right now.", "Return"
      ),
      (
        "🕸️", "Avoid the trap", "One click turns into twenty. Let’s not.", "Back"
      ),
      ("🛡️", "Protected zone", "We’re keeping your attention where you wanted it.", "Got it"),
      ("🔒", "Locked in", "This is a temporary block for a long-term win.", "Return"),
      (
        "🎯", "Back to the task", "Close the detour. Finish the task. Then come back on purpose.",
        "Back to work"
      ),
      (
        "⏳", "Protect the time", "A few minutes can become an hour. Keep your momentum.",
        "Stay focused"
      ),
      ("📵", "Not missing anything", "You’re not missing anything important right now.", "Back"),
      ("✨", "Momentum mode", "Tiny choices like this add up fast.", "Continue"),
    ]
    guard !messages.isEmpty else { return ("🧠", "Quick pause", "Not right now.", "Back") }

    let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let dayKey =
      (comps.year ?? 0) * 10_000
      + (comps.month ?? 0) * 100
      + (comps.day ?? 0)

    let seed = Int(stableSeed(for: title) % UInt64(Int.max)) ^ dayKey
    let idx = abs(seed) % messages.count

    return messages[idx]
  }

  private func stableSeed(for title: String) -> UInt64 {
    // FNV-1a 64-bit over unicode scalars (deterministic across runs/devices).
    var hash: UInt64 = 14_695_981_039_346_656_037
    for scalar in title.unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return hash
  }

  private func makeEmojiIcon(_ emoji: String, size: CGFloat) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center

      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: size * 0.78),
        .paragraphStyle: paragraph,
      ]

      let rect = CGRect(x: 0, y: 0, width: size, height: size)
      let attributed = NSAttributedString(string: emoji, attributes: attributes)
      let bounds = attributed.boundingRect(
        with: rect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )

      // Vertically center emoji
      let drawRect = CGRect(
        x: rect.minX,
        y: rect.minY + (rect.height - bounds.height) / 2,
        width: rect.width,
        height: bounds.height
      )
      attributed.draw(in: drawRect)
    }
  }
}

enum BlockedContentType {
  case app
  case website
}
