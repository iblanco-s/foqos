import FamilyControls
import SwiftUI

private struct ProfileFieldDivider: View {
  var isVisible: Bool

  var body: some View {
    if isVisible {
      Divider()
    }
  }
}

struct BlockedProfileNameFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsFieldLabels: Bool = true

  var body: some View {
    TextField(
      showsFieldLabels ? "Profile Name" : "",
      text: $draft.name,
      prompt: Text("Profile Name")
    )
    .textContentType(.none)
    .disabled(disabled)
  }
}

struct BlockedProfileNameSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Name") {
      BlockedProfileNameFields(draft: draft, disabled: disabled)
    }
  }
}

struct BlockedProfileStrategyFields: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingStrategyPicker: Bool
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    Button(action: { showingStrategyPicker = true }) {
      HStack {
        Text("Choose Strategy")
          .foregroundStyle(themeManager.themeColor)
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.gray)
      }
    }
    .disabled(disabled)

    if let selectedStrategy = draft.selectedStrategy {
      ProfileFieldDivider(isVisible: showsSeparators)

      StrategyRow(
        strategy: selectedStrategy,
        isSelected: false,
        onTap: {},
        accessoryStyle: .none
      )
      .allowsHitTesting(false)
    }
  }
}

struct BlockedProfileStrategySection: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingStrategyPicker: Bool
  var disabled: Bool
  var showsStartSettings: Bool = false
  var onUpdateStartSettings: ((StrategyStartSettingsKind) -> Void)?

  var body: some View {
    Section {
      BlockedProfileStrategyFields(
        draft: draft,
        showingStrategyPicker: $showingStrategyPicker,
        disabled: disabled
      )

      if showsStartSettings,
        let settingsKind = StrategyStartSettingsKind(strategy: draft.selectedStrategy)
      {
        Button {
          onUpdateStartSettings?(settingsKind)
        } label: {
          HStack {
            Text("Update Start Settings")
              .foregroundStyle(themeManager.themeColor)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundStyle(.secondary)
          }
        }
        .disabled(disabled)

        CustomToggle(
          title: "Ask Me Every Time",
          description: "Turn off to use the saved settings automatically.",
          isOn: $draft.askForStartSettings,
          isDisabled: disabled
        )
      }
    } header: {
      Text("Blocking Strategy")
    }
  }
}

struct BlockedProfileAppsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingActivityPicker: Bool
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    BlockedProfileAppSelector(
      selection: draft.selectedActivity,
      buttonAction: { showingActivityPicker = true },
      allowMode: draft.enableAllowMode,
      disabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Allow Only Selected Apps",
      description:
        "Only selected apps stay available during sessions. Turning this on clears your blocked-app selection.",
      isOn: $draft.enableAllowMode,
      isDisabled: disabled || !draft.selectedStrategySupportsAllowMode,
      errorMessage: draft.selectedStrategySupportsAllowMode
        ? nil : "Allow-only mode isn't supported with Temporary Access."
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Block Websites in Safari",
      description:
        "Also block selected websites in Safari. When off, Safari stays unrestricted.",
      isOn: $draft.enableSafariBlocking,
      isDisabled: disabled
    )
    .onChange(of: draft.enableAllowMode) { _, newValue in
      draft.selectedActivity = FamilyActivitySelection(includeEntireCategory: newValue)
    }
  }
}

struct BlockedProfileAppsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingActivityPicker: Bool
  var disabled: Bool

  var body: some View {
    Section((draft.enableAllowMode ? "Allowed" : "Blocked") + " Apps") {
      BlockedProfileAppsFields(
        draft: draft,
        showingActivityPicker: $showingActivityPicker,
        disabled: disabled
      )
    }
  }
}

struct BlockedProfileDomainsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingDomainPicker: Bool
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    BlockedProfileDomainSelector(
      domains: draft.domains,
      buttonAction: { showingDomainPicker = true },
      allowMode: draft.enableAllowModeDomain,
      disabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Sync to Mac",
      description:
        "Block the same selected domains on your Mac with the Foqos for Mac app.",
      isOn: $draft.enableMacSync,
      isDisabled: disabled,
      learnMoreURL: URL(string: "https://www.foqos.app/mac.html")
    )
    .onChange(of: draft.enableMacSync) { _, newValue in
      if newValue {
        draft.enableAllowModeDomain = false
        draft.enableAdultContentBlocking = false
      }
    }

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Allow Only Selected Domains",
      description:
        "Only selected domains stay available during sessions.",
      isOn: $draft.enableAllowModeDomain,
      isDisabled: disabled || draft.enableMacSync,
      errorMessage: draft.enableMacSync ? "Allow-only mode isn't supported on Mac." : nil
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Block Adult Websites",
      description:
        "Use Apple's adult-content filter during sessions. You can still add extra domains to block.",
      isOn: $draft.enableAdultContentBlocking,
      isDisabled: disabled || draft.enableMacSync,
      errorMessage: draft.enableMacSync ? "Adult website blocking isn't supported on Mac." : nil
    )
    .onChange(of: draft.enableAllowModeDomain) { _, newValue in
      if newValue {
        draft.enableAdultContentBlocking = false
      }
    }
    .onChange(of: draft.enableAdultContentBlocking) { _, newValue in
      if newValue {
        draft.enableAllowModeDomain = false
      }
    }
  }
}

struct BlockedProfileDomainsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingDomainPicker: Bool
  var disabled: Bool

  var body: some View {
    Section((draft.enableAllowModeDomain ? "Allowed" : "Blocked") + " Domains") {
      BlockedProfileDomainsFields(
        draft: draft,
        showingDomainPicker: $showingDomainPicker,
        disabled: disabled
      )
    }
  }
}

struct BlockedProfileStrictUnlocksFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    BlockedProfilePhysicalUnblockSelector(
      physicalUnblockItems: $draft.physicalUnblockItems,
      disabled: disabled
    )
  }
}

struct BlockedProfileStrictUnlocksSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Physical Unlocks") {
      BlockedProfileStrictUnlocksFields(draft: draft, disabled: disabled)
    }
  }
}

struct BlockedProfileScheduleFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingSchedulePicker: Bool
  var disabled: Bool

  var body: some View {
    BlockedProfileScheduleSelector(
      schedule: draft.schedule,
      buttonAction: { showingSchedulePicker = true },
      disabled: disabled
    )
  }
}

struct BlockedProfileScheduleSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingSchedulePicker: Bool
  var disabled: Bool

  var body: some View {
    Section("Schedule") {
      BlockedProfileScheduleFields(
        draft: draft,
        showingSchedulePicker: $showingSchedulePicker,
        disabled: disabled
      )
    }
  }
}

struct BlockedProfileBreaksFields: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsSeparators: Bool = false

  private let minimumBreakDurationInMinutes = 5
  private let maximumBreakDurationInMinutes = 60

  @ViewBuilder
  var body: some View {
    if draft.selectedStrategyAllowsTimedBreaks {
      CustomToggle(
        title: "Allow Timed Breaks",
        description:
          "Take a break during your session. The break will automatically end after the selected duration.",
        isOn: $draft.enableBreaks,
        isDisabled: disabled
      )

      if draft.enableBreaks {
        ProfileFieldDivider(isVisible: showsSeparators)

        breakDurationPicker

        ProfileFieldDivider(isVisible: showsSeparators)

        CustomToggle(
          title: "Allow Multiple Breaks",
          description: "Take multiple breaks until your total break duration is used.",
          isOn: $draft.allowMultipleBreaks,
          isDisabled: disabled
        )
      }
    } else {
      ProfileFieldNotice(
        title: "Breaks are off for Temporary Access",
        message:
          "This strategy already gives short opens for blocked apps and categories, so timed breaks are not needed for this profile."
      )
    }
  }

  private var breakDurationPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Break Duration")

        Spacer()

        Text(DateFormatters.formatMinutes(draft.breakTimeInMinutes))
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }

      Slider(
        value: breakDurationBinding,
        in: Double(minimumBreakDurationInMinutes)...Double(maximumBreakDurationInMinutes),
        step: 5
      )
      .tint(themeManager.themeColor)
      .accessibilityValue(DateFormatters.formatMinutes(draft.breakTimeInMinutes))

      HStack {
        Text("5m")
        Spacer()
        Text("1h")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .disabled(disabled)
  }

  private var breakDurationBinding: Binding<Double> {
    Binding(
      get: { Double(draft.breakTimeInMinutes) },
      set: { draft.breakTimeInMinutes = Int($0) }
    )
  }
}

struct BlockedProfileBreaksSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Breaks") {
      BlockedProfileBreaksFields(draft: draft, disabled: disabled)
    }
  }
}

private struct ProfileFieldNotice: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)

      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

struct BlockedProfileStrictSafeguardsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    CustomToggle(
      title: "Prevent App Deletion",
      description:
        "Stop apps from being deleted during sessions, including Foqos.",
      isOn: $draft.enableStrictMode,
      isDisabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Prevent New App Installs",
      description:
        "Stop new apps from being installed during sessions.",
      isOn: $draft.enableBlockAppInstallation,
      isDisabled: disabled
    )
  }
}

struct BlockedProfileSessionSafeguardsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsSeparators: Bool = false

  @State private var showingEmergencyUnblockWarning = false

  var body: some View {
    CustomToggle(
      title: "Require Foqos to Stop",
      description:
        "Prevent this profile from being stopped by Shortcuts, NFC links, or QR links outside the app.",
      isOn: $draft.disableBackgroundStops,
      isDisabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Emergency Unblock",
      description:
        "Allow limited emergency unblocks during active sessions.",
      isOn: emergencyUnblockBinding,
      isDisabled: disabled
    )
    .alert("You Could Lock Yourself Out", isPresented: $showingEmergencyUnblockWarning) {
      Button("Cancel", role: .cancel) {}
      Button("I Understand the Risks", role: .destructive) {
        draft.enableEmergencyUnblock = false
      }
    } message: {
      Text(
        "Turning off Emergency Unblock removes your backup way to end an active session. "
          + "If a required NFC tag, QR code, or barcode is lost, damaged, or unavailable, "
          + "you may be unable to stop the session and could be locked out of apps and "
          + "features on this phone."
      )
    }
  }

  private var emergencyUnblockBinding: Binding<Bool> {
    Binding(
      get: { draft.enableEmergencyUnblock },
      set: { newValue in
        guard !newValue, draft.enableEmergencyUnblock else {
          draft.enableEmergencyUnblock = newValue
          return
        }

        showingEmergencyUnblockWarning = true
      }
    )
  }
}

struct BlockedProfileStrictSafeguardsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Session Protection") {
      BlockedProfileStrictSafeguardsFields(draft: draft, disabled: disabled)
    }
  }
}

struct BlockedProfileSessionSafeguardsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Stop Options") {
      BlockedProfileSessionSafeguardsFields(draft: draft, disabled: disabled)
    }
  }
}

struct BlockedProfileNotificationsFields: View {
  @EnvironmentObject private var strategyManager: StrategyManager
  @EnvironmentObject private var themeManager: ThemeManager
  @FocusState private var isReminderTimeFocused: Bool

  @ObservedObject var draft: BlockedProfileDraft
  var profile: BlockedProfiles?
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    notificationFields
  }

  @ViewBuilder
  private var notificationFields: some View {
    CustomToggle(
      title: "Live Activity",
      description:
        "Show session progress on the Lock Screen.",
      isOn: $draft.enableLiveActivity,
      isDisabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Reminder",
      description:
        "Remind you to start this profile when it ends.",
      isOn: $draft.enableReminder,
      isDisabled: disabled
    )

    if draft.enableReminder {
      ProfileFieldDivider(isVisible: showsSeparators)

      HStack {
        Text("Reminder time")
        Spacer()
        TextField(
          "",
          value: $draft.reminderTimeInMinutes,
          format: .number
        )
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(width: 58)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              isReminderTimeFocused
                ? themeManager.themeColor : Color.secondary.opacity(0.4),
              lineWidth: isReminderTimeFocused ? 2 : 1
            )
        }
        .focused($isReminderTimeFocused)
        .disabled(disabled)
        .font(.subheadline)
        .foregroundStyle(disabled ? Color.secondary : Color.primary)
        .accessibilityLabel("Reminder time in minutes")

        Text("minutes")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .listRowSeparator(.visible)

      ProfileFieldDivider(isVisible: showsSeparators)

      VStack(alignment: .leading) {
        Text("Reminder message")
        TextField(
          "Reminder message",
          text: $draft.customReminderMessage,
          prompt: Text(strategyManager.defaultReminderMessage(forProfile: profile)),
          axis: .vertical
        )
        .foregroundColor(.secondary)
        .lineLimit(...3)
        .onChange(of: draft.customReminderMessage) { _, newValue in
          if newValue.count > 178 {
            draft.customReminderMessage = String(newValue.prefix(178))
          }
        }
        .disabled(disabled)
      }
    }

    if !disabled {
      Button {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      } label: {
        Text("Manage notification settings")
          .foregroundStyle(themeManager.themeColor)
          .font(.caption)
      }
    }
  }
}

struct BlockedProfileNotificationsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var profile: BlockedProfiles?
  var disabled: Bool

  var body: some View {
    Section("Notifications") {
      BlockedProfileNotificationsFields(
        draft: draft,
        profile: profile,
        disabled: disabled
      )
    }
  }
}

struct BlockedProfileAppLimitsFields: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    CustomToggle(
      title: "Daily App Limits",
      description:
        "Limit total time and/or opens per day for the apps above. Works without starting a focus session. Resets at midnight.",
      isOn: $draft.appLimitsEnabled,
      isDisabled: disabled
    )

    if draft.enableAllowMode {
      Text("Daily Limits need blocklist mode. Turn off “Allow Only Selected Apps” to use them.")
        .font(.caption)
        .foregroundStyle(.orange)
    }

    if draft.appLimitsEnabled {
      CustomToggle(
        title: "Limit Daily Usage Time",
        description: "Block the selected apps for the rest of the day after this much use.",
        isOn: $draft.enableDailyTimeLimit,
        isDisabled: disabled
      )

      if draft.enableDailyTimeLimit {
        timeLimitPicker
      }

      CustomToggle(
        title: "Limit Daily Opens",
        description:
          "Keep the selected apps blocked. Each tap on Open uses one open and grants short access.",
        isOn: $draft.enableDailyOpenLimit,
        isDisabled: disabled
      )

      if draft.enableDailyOpenLimit {
        opensPicker
        openDurationPicker
      }

      if !draft.enableDailyTimeLimit && !draft.enableDailyOpenLimit {
        Text("Turn on at least one limit below.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var timeLimitPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Daily time limit")
        Spacer()
        Text(formatMinutes(draft.dailyTimeLimitInMinutes))
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }

      Slider(
        value: timeBinding,
        in: 5...480,
        step: 5
      )
      .tint(themeManager.themeColor)

      HStack {
        Text("5m")
        Spacer()
        Text("8h")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .disabled(disabled)
  }

  private var opensPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Opens per day")
        Spacer()
        Text("\(draft.dailyOpenLimit)")
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }

      Slider(
        value: opensBinding,
        in: 1...50,
        step: 1
      )
      .tint(themeManager.themeColor)

      HStack {
        Text("1")
        Spacer()
        Text("50")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .disabled(disabled)
  }

  private var openDurationPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Each open lasts")
        Spacer()
        Text(formatMinutes(draft.appLimitOpenDurationInMinutes))
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }

      Slider(
        value: openDurationBinding,
        in: 1...30,
        step: 1
      )
      .tint(themeManager.themeColor)

      HStack {
        Text("1m")
        Spacer()
        Text("30m")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .disabled(disabled)
  }

  private var timeBinding: Binding<Double> {
    Binding(
      get: { Double(draft.dailyTimeLimitInMinutes) },
      set: { draft.dailyTimeLimitInMinutes = Int($0) }
    )
  }

  private var opensBinding: Binding<Double> {
    Binding(
      get: { Double(draft.dailyOpenLimit) },
      set: { draft.dailyOpenLimit = Int($0) }
    )
  }

  private var openDurationBinding: Binding<Double> {
    Binding(
      get: { Double(draft.appLimitOpenDurationInMinutes) },
      set: { draft.appLimitOpenDurationInMinutes = Int($0) }
    )
  }

  private func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    let h = minutes / 60
    let m = minutes % 60
    if m == 0 { return "\(h)h" }
    return "\(h)h \(m)m"
  }
}

struct BlockedProfileAppLimitsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Daily Limits") {
      BlockedProfileAppLimitsFields(draft: draft, disabled: disabled)
    } footer: {
      Text("Alternative to sessions: enforced every day via Screen Time, even with the app closed.")
    }
  }
}
