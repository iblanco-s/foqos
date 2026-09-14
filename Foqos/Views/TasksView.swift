import SwiftUI

/// Pending tasks with estimated time. Shown on blocked-app shields as
/// friction before opening apps, so the user can pick a task instead.
struct TasksView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var themeManager: ThemeManager

  @State private var tasks: [SharedData.FocusTask] = SharedData.focusTasks
  @State private var showingAddSheet = false
  @State private var newTitle = ""
  @State private var newMinutes = 30

  private var pending: [SharedData.FocusTask] {
    tasks.filter { !$0.isCompleted }
  }

  private var completed: [SharedData.FocusTask] {
    tasks.filter { $0.isCompleted }
  }

  var body: some View {
    NavigationStack {
      List {
        if tasks.isEmpty {
          Section {
            VStack(alignment: .leading, spacing: 6) {
              Text("No tasks yet")
                .font(.subheadline)
                .fontWeight(.semibold)
              Text(
                "Add what you want to do instead of opening blocked apps. Pending tasks appear on the block screen."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
          }
        }

        if !pending.isEmpty {
          Section("Pending (\(pending.count))") {
            ForEach(pending) { task in
              taskRow(task)
            }
            .onDelete { offsets in
              deleteTasks(offsets, in: pending)
            }
          }
        }

        if !completed.isEmpty {
          Section("Done") {
            ForEach(completed) { task in
              taskRow(task)
            }
            .onDelete { offsets in
              deleteTasks(offsets, in: completed)
            }
          }
        }
      }
      .navigationTitle("Tasks")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: {
            newTitle = ""
            newMinutes = 30
            showingAddSheet = true
          }) {
            Image(systemName: "plus")
          }
          .accessibilityLabel("Add task")
        }
      }
      .sheet(isPresented: $showingAddSheet) {
        NavigationStack {
          Form {
            Section("Task") {
              TextField("What to do instead?", text: $newTitle)
            }
            Section("Estimated time") {
              Stepper(
                "\(formatMinutes(newMinutes))",
                value: $newMinutes,
                in: 5...480,
                step: 5
              )
            }
          }
          .navigationTitle("New Task")
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("Cancel") { showingAddSheet = false }
            }
            ToolbarItem(placement: .topBarTrailing) {
              Button("Add") {
                if SharedData.addFocusTask(title: newTitle, estimatedMinutes: newMinutes)
                  != nil
                {
                  reload()
                  showingAddSheet = false
                }
              }
              .fontWeight(.semibold)
              .disabled(
                newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              )
            }
          }
        }
        .presentationDetents([.medium])
      }
    }
    .tint(themeManager.themeColor)
  }

  private func taskRow(_ task: SharedData.FocusTask) -> some View {
    HStack(spacing: 12) {
      Button(action: {
        SharedData.toggleFocusTask(id: task.id)
        reload()
      }) {
        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(task.isCompleted ? themeManager.themeColor : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(task.isCompleted ? "Mark as pending" : "Mark as done")

      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .strikethrough(task.isCompleted)
          .foregroundStyle(task.isCompleted ? .secondary : .primary)
        Text(formatMinutes(task.estimatedMinutes))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(.vertical, 2)
  }

  private func deleteTasks(_ offsets: IndexSet, in section: [SharedData.FocusTask]) {
    for index in offsets {
      SharedData.deleteFocusTask(id: section[index].id)
    }
    reload()
  }

  private func reload() {
    tasks = SharedData.focusTasks
  }

  private func formatMinutes(_ minutes: Int) -> String {
    if minutes <= 0 { return "No estimate" }
    if minutes < 60 { return "~\(minutes) min" }
    let h = minutes / 60
    let m = minutes % 60
    if m == 0 { return "~\(h) h" }
    return "~\(h) h \(m) min"
  }
}

#Preview {
  TasksView()
    .environmentObject(ThemeManager.shared)
}
