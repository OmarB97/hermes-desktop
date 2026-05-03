import SwiftUI

struct KanbanView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout

    @State private var searchText = ""
    @State private var statusFilter: KanbanStatusFilter = .all
    @State private var assigneeFilter = KanbanFilterOption.all
    @State private var tenantFilter = KanbanFilterOption.all
    @State private var isCreatingTask = false
    @State private var taskDraft = KanbanTaskDraft()

    var body: some View {
        HermesPersistentHSplitView(layout: $splitLayout, detailMinWidth: 440) {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Kanban",
                    subtitle: "Inspect and operate the host-wide Hermes Kanban board over SSH."
                ) {
                    headerActions
                }

                filterBar
                boardContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        } detail: {
            detailContent
                .hermesSplitDetailColumn(minWidth: 440, idealWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            if appState.kanbanBoard == nil {
                await appState.loadKanbanBoard()
            }
        }
        .onChange(of: appState.includeArchivedKanbanTasks) { _, includeArchived in
            Task { await appState.refreshKanbanBoard(includeArchived: includeArchived) }
        }
        .onChange(of: statusFilter) { _, filter in
            if filter == .archived, !appState.includeArchivedKanbanTasks {
                appState.includeArchivedKanbanTasks = true
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                taskDraft = KanbanTaskDraft()
                isCreatingTask = true
            } label: {
                Label("New", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .help(L10n.string("Create a Kanban task"))
            .disabled(appState.isSavingKanbanTaskDraft || appState.isOperatingOnKanbanTask)

            Button {
                Task { await appState.dispatchKanbanNow() }
            } label: {
                if appState.isDispatchingKanban {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Dispatch", systemImage: "paperplane")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .help(L10n.string("Nudge the remote Kanban dispatcher once"))
            .disabled(appState.isDispatchingKanban || appState.isLoadingKanbanBoard)

            HermesRefreshButton(isRefreshing: appState.isRefreshingKanbanBoard) {
                Task { await appState.refreshKanbanBoard() }
            }
            .disabled(appState.isLoadingKanbanBoard || appState.isSavingKanbanTaskDraft)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Status", selection: $statusFilter) {
                ForEach(KanbanStatusFilter.allCases, id: \.self) { option in
                    Text(L10n.string(option.title)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("Assignee", selection: $assigneeFilter) {
                Text(L10n.string("All assignees")).tag(KanbanFilterOption.all)
                ForEach(assigneeOptions, id: \.self) { assignee in
                    Text(assignee).tag(KanbanFilterOption.value(assignee))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Picker("Tenant", selection: $tenantFilter) {
                Text(L10n.string("All tenants")).tag(KanbanFilterOption.all)
                ForEach(tenantOptions, id: \.self) { tenant in
                    Text(tenant).tag(KanbanFilterOption.value(tenant))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .disabled(tenantOptions.isEmpty)

            Toggle("Archived", isOn: $appState.includeArchivedKanbanTasks)
                .toggleStyle(.checkbox)

            Spacer(minLength: 12)

            HermesExpandableSearchField(
                text: $searchText,
                prompt: "Search tasks",
                expandedWidth: 220
            )
        }
    }

    @ViewBuilder
    private var boardContent: some View {
        if appState.isLoadingKanbanBoard && appState.kanbanBoard == nil {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading Kanban board...",
                    minHeight: 320
                )
            }
        } else if let error = appState.kanbanError, appState.kanbanBoard == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load Kanban",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if let board = appState.kanbanBoard, !board.isInitialized {
            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 18) {
                    ContentUnavailableView(
                        "No Kanban board yet",
                        systemImage: "rectangle.3.group",
                        description: Text(L10n.string("No host-wide Kanban database exists at %@. Create the first task to initialize it on the remote host.", board.databasePath))
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)

                    Button {
                        taskDraft = KanbanTaskDraft()
                        isCreatingTask = true
                    } label: {
                        Label("Create First Task", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isSavingKanbanTaskDraft)
                }
            }
        } else if let board = appState.kanbanBoard {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: boardSubtitle(board)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if let warning = dispatcherWarning(for: board) {
                        KanbanWarningBanner(message: warning)
                    }

                    if let error = appState.kanbanError {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if filteredTasks.isEmpty {
                        ContentUnavailableView(
                            "No matching tasks",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search, status, assignee, tenant, or archive filter.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            kanbanBoardLayout(board)
                                .frame(minWidth: 920)

                            kanbanGroupedList(board)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingKanbanBoard && !appState.isRefreshingKanbanBoard {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    private func kanbanBoardLayout(_ board: KanbanBoard) -> some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(displayStatuses, id: \.rawValue) { status in
                    KanbanColumnView(
                        status: status,
                        tasks: filteredTasks(for: status),
                        selectedTaskID: appState.selectedKanbanTaskID,
                        onSelect: selectTask
                    )
                    .frame(width: 250)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
    }

    private func kanbanGroupedList(_ board: KanbanBoard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(displayStatuses, id: \.rawValue) { status in
                    let tasks = filteredTasks(for: status)
                    if !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(L10n.string(status.displayTitle))
                                    .font(.headline)

                                HermesBadge(text: "\(tasks.count)", tint: KanbanColors.tint(for: status))
                            }

                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(tasks) { task in
                                    KanbanTaskCard(
                                        task: task,
                                        isSelected: task.id == appState.selectedKanbanTaskID,
                                        onSelect: { selectTask(task) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isCreatingTask {
            KanbanTaskEditorView(
                draft: $taskDraft,
                errorMessage: appState.kanbanError,
                isSaving: appState.isSavingKanbanTaskDraft,
                assignees: assigneeOptions,
                onCancel: {
                    isCreatingTask = false
                },
                onSave: {
                    if await appState.createKanbanTask(taskDraft) {
                        isCreatingTask = false
                    }
                }
            )
        } else {
            KanbanTaskDetailView(
                task: selectedTask,
                detail: appState.selectedKanbanTaskDetail,
                errorMessage: appState.kanbanError,
                isLoading: appState.isLoadingKanbanTaskDetail,
                operationInFlight: selectedTask.map { task in
                    appState.isOperatingOnKanbanTask && appState.operatingKanbanTaskID == task.id
                } ?? false,
                assignees: assigneeOptions,
                onCreate: {
                    taskDraft = KanbanTaskDraft()
                    isCreatingTask = true
                },
                onAssign: { taskID, assignee in
                    await appState.assignKanbanTask(taskID: taskID, assignee: assignee)
                },
                onComment: { taskID, comment in
                    await appState.addKanbanComment(taskID: taskID, body: comment)
                },
                onBlock: { taskID, reason in
                    await appState.blockKanbanTask(taskID: taskID, reason: reason)
                },
                onUnblock: { taskID in
                    await appState.unblockKanbanTask(taskID: taskID)
                },
                onComplete: { taskID, result in
                    await appState.completeKanbanTask(taskID: taskID, result: result)
                },
                onArchive: { taskID in
                    await appState.archiveKanbanTask(taskID: taskID)
                }
            )
        }
    }

    private var filteredTasks: [KanbanTask] {
        guard let board = appState.kanbanBoard else { return [] }
        return board.tasks.filter { task in
            if !appState.includeArchivedKanbanTasks && task.status == .archived {
                return false
            }
            if let status = statusFilter.status, task.status != status {
                return false
            }
            if case .value(let assignee) = assigneeFilter, task.assignee != assignee {
                return false
            }
            if case .value(let tenant) = tenantFilter, task.tenant != tenant {
                return false
            }
            return task.matchesSearch(searchText)
        }
    }

    private func filteredTasks(for status: KanbanTaskStatus) -> [KanbanTask] {
        filteredTasks.filter { $0.status == status }
    }

    private var displayStatuses: [KanbanTaskStatus] {
        if let status = statusFilter.status {
            return [status]
        }

        return KanbanTaskStatus.boardStatuses.filter { status in
            status != .archived || appState.includeArchivedKanbanTasks
        }
    }

    private var assigneeOptions: [String] {
        let boardAssignees = appState.kanbanBoard?.assignees.map(\.name) ?? []
        let taskAssignees = appState.kanbanBoard?.tasks.compactMap(\.assignee) ?? []
        return Array(Set(boardAssignees + taskAssignees)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var tenantOptions: [String] {
        let boardTenants = appState.kanbanBoard?.tenants ?? []
        let taskTenants = appState.kanbanBoard?.tasks.compactMap(\.tenant) ?? []
        return Array(Set(boardTenants + taskTenants)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var selectedTask: KanbanTask? {
        appState.kanbanBoard?.task(id: appState.selectedKanbanTaskID)
    }

    private var panelTitle: String {
        let total = appState.kanbanBoard?.tasks.count ?? 0
        let filtered = filteredTasks.count
        let isFiltering = statusFilter != .all ||
            assigneeFilter != .all ||
            tenantFilter != .all ||
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            appState.includeArchivedKanbanTasks

        if isFiltering {
            return "Kanban Tasks (\(filtered) of \(total))"
        }

        return "Kanban Tasks (\(total))"
    }

    private func boardSubtitle(_ board: KanbanBoard) -> String {
        "Host-wide board at \(board.databasePath). The selected Hermes profile is used as operator context, not as board scope."
    }

    private func dispatcherWarning(for board: KanbanBoard) -> String? {
        guard board.tasks.contains(where: { $0.status == .ready }) else { return nil }
        guard board.dispatcher?.isKnownInactive == true else { return nil }
        return board.dispatcher?.message ?? "Ready tasks are waiting, but the Hermes gateway dispatcher does not appear to be active."
    }

    private func selectTask(_ task: KanbanTask) {
        Task { await appState.loadKanbanTaskDetail(taskID: task.id) }
    }
}

private enum KanbanStatusFilter: Hashable, CaseIterable {
    case all
    case triage
    case todo
    case ready
    case running
    case blocked
    case done
    case archived

    var title: String {
        switch self {
        case .all:
            "All"
        case .triage:
            "Triage"
        case .todo:
            "Todo"
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }

    var status: KanbanTaskStatus? {
        switch self {
        case .all:
            nil
        case .triage:
            .triage
        case .todo:
            .todo
        case .ready:
            .ready
        case .running:
            .running
        case .blocked:
            .blocked
        case .done:
            .done
        case .archived:
            .archived
        }
    }
}

private enum KanbanFilterOption: Hashable {
    case all
    case value(String)
}

private enum KanbanColors {
    static func tint(for status: KanbanTaskStatus) -> Color {
        switch status {
        case .triage:
            .secondary
        case .todo:
            .blue
        case .ready:
            .green
        case .running:
            .orange
        case .blocked:
            .red
        case .done:
            .purple
        case .archived:
            .secondary
        case .other:
            .secondary
        }
    }
}

private struct KanbanWarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [KanbanTask]
    let selectedTaskID: String?
    let onSelect: (KanbanTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.string(status.displayTitle))
                    .font(.headline)

                HermesBadge(text: "\(tasks.count)", tint: KanbanColors.tint(for: status))
            }

            LazyVStack(alignment: .leading, spacing: 10) {
                if tasks.isEmpty {
                    Text(L10n.string("No tasks"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(tasks) { task in
                        KanbanTaskCard(
                            task: task,
                            isSelected: task.id == selectedTaskID,
                            onSelect: { onSelect(task) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct KanbanTaskCard: View {
    let task: KanbanTask
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.resolvedTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(task.shortID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    HermesBadge(text: task.priorityLabel, tint: task.priority == 0 ? .secondary : .orange, isMonospaced: true)
                }

                if let body = task.trimmedBody {
                    Text(body.replacingOccurrences(of: "\n", with: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HermesWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    if let assignee = task.assignee {
                        HermesBadge(text: "@\(assignee)", tint: .accentColor, isMonospaced: true)
                    }

                    if let tenant = task.tenant {
                        HermesBadge(text: tenant, tint: .secondary)
                    }

                    if task.commentCount > 0 {
                        HermesBadge(text: "\(task.commentCount) comments", tint: .secondary)
                    }

                    if let progress = task.progressLabel {
                        HermesBadge(text: progress, tint: .green, isMonospaced: true)
                    }

                    if !task.parentIDs.isEmpty {
                        HermesBadge(text: "\(task.parentIDs.count) deps", tint: .secondary)
                    }
                }

                if let latest = task.latestActivityDate {
                    Text(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: latest, relativeTo: .now)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(NSColor.controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.16 : 0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct KanbanTaskEditorView: View {
    @Binding var draft: KanbanTaskDraft
    let errorMessage: String?
    let isSaving: Bool
    let assignees: [String]
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HermesSurfacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("New Kanban Task"))
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(L10n.string("The task will be created in the host-wide Hermes Kanban board over SSH."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("Create Task") {
                                Task { await onSave() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || draft.validationError != nil)

                            Button("Cancel", action: onCancel)
                                .buttonStyle(.bordered)
                                .disabled(isSaving)

                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                if let errorMessage {
                    KanbanWarningBanner(message: errorMessage)
                }

                HermesSurfacePanel(
                    title: "Task",
                    subtitle: "Describe the work and optionally assign it to a Hermes profile."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        KanbanFormField(label: "Title") {
                            TextField("Investigate failing release check", text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                        }

                        KanbanFormField(label: "Body") {
                            TextEditor(text: $draft.body)
                                .font(.body)
                                .frame(minHeight: 160)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                }
                        }

                        HStack(alignment: .top, spacing: 14) {
                            KanbanFormField(label: "Assignee") {
                                ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "researcher")
                            }

                            KanbanFormField(label: "Tenant") {
                                TextField("optional", text: $draft.tenant)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            KanbanFormField(label: "Priority") {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField("0", value: $draft.priority, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 96)

                                    Text(L10n.string("Higher values sort first. 0 is the Hermes default."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Toggle("Start in triage", isOn: $draft.startsInTriage)
                                .toggleStyle(.checkbox)
                                .padding(.top, 20)
                        }

                        KanbanFormField(label: "Skills") {
                            TextField("deploy-check, release-notes", text: $draft.skillsText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

private struct KanbanTaskDetailView: View {
    let task: KanbanTask?
    let detail: KanbanTaskDetail?
    let errorMessage: String?
    let isLoading: Bool
    let operationInFlight: Bool
    let assignees: [String]
    let onCreate: () -> Void
    let onAssign: (String, String?) async -> Void
    let onComment: (String, String) async -> Bool
    let onBlock: (String, String?) async -> Void
    let onUnblock: (String) async -> Void
    let onComplete: (String, String?) async -> Void
    let onArchive: (String) async -> Void

    @State private var draft = KanbanActionDraft()
    @State private var showArchiveConfirmation = false

    private let metadataColumns = [
        GridItem(.adaptive(minimum: 160), alignment: .topLeading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let task {
                    headerPanel(task)

                    if let errorMessage {
                        KanbanWarningBanner(message: errorMessage)
                    }

                    if isLoading && detail == nil {
                        HermesSurfacePanel {
                            HermesLoadingState(label: "Loading task detail...", minHeight: 180)
                        }
                    } else {
                        metadataPanel(task)

                        if let body = task.trimmedBody {
                            HermesSurfacePanel(
                                title: "Body",
                                subtitle: "Task description stored on the remote board."
                            ) {
                                HermesInsetSurface {
                                    Text(body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if let result = task.trimmedResult {
                            HermesSurfacePanel(
                                title: "Result",
                                subtitle: "Completion handoff stored by Hermes."
                            ) {
                                HermesInsetSurface {
                                    Text(result)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        actionPanel(task)

                        if let detail {
                            linksPanel(detail)
                            commentsPanel(task, detail)
                            runsPanel(detail)
                            eventsPanel(detail)
                            logPanel(detail)
                        }
                    }
                } else {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 18) {
                            ContentUnavailableView(
                                "Select a Kanban task",
                                systemImage: "rectangle.3.group",
                                description: Text("Choose a task from the host-wide board, or create a new one.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)

                            Button {
                                onCreate()
                            } label: {
                                Label("Create Kanban Task", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .onChange(of: task?.id) { _, _ in
            draft = KanbanActionDraft(
                comment: "",
                result: "",
                blockReason: "",
                assignee: task?.assignee ?? ""
            )
        }
        .onAppear {
            draft.assignee = task?.assignee ?? ""
        }
        .alert("Archive this task?", isPresented: $showArchiveConfirmation, presenting: task) { task in
            Button("Archive", role: .destructive) {
                Task { await onArchive(task.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text(L10n.string("“%@” will be hidden from the active board unless archived tasks are shown.", task.resolvedTitle))
        }
    }

    private func headerPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.resolvedTitle)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(task.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        HermesBadge(text: task.status.displayTitle, tint: KanbanColors.tint(for: task.status))
                        HermesBadge(text: task.priorityLabel, tint: task.priority == 0 ? .secondary : .orange, isMonospaced: true)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        primaryActions(task)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        primaryActions(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func primaryActions(_ task: KanbanTask) -> some View {
        if task.canUnblock {
            Button("Unblock") {
                Task { await onUnblock(task.id) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(operationInFlight)
        }

        if task.canComplete {
            if task.status == .blocked {
                Button("Complete") {
                    Task { await onComplete(task.id, draft.normalizedResult) }
                }
                .buttonStyle(.bordered)
                .disabled(operationInFlight)
            } else {
                Button("Complete") {
                    Task { await onComplete(task.id, draft.normalizedResult) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(operationInFlight)
            }
        }

        if task.canBlock {
            Button("Block") {
                Task { await onBlock(task.id, draft.normalizedBlockReason) }
            }
            .buttonStyle(.bordered)
            .disabled(operationInFlight)
        }

        Button("Archive", role: .destructive) {
            showArchiveConfirmation = true
        }
        .buttonStyle(.bordered)
        .disabled(operationInFlight || task.status == .archived)

        if operationInFlight {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func metadataPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel(
            title: "Details",
            subtitle: "Board metadata from the remote host."
        ) {
            LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 14) {
                HermesLabeledValue(label: "Status", value: task.status.displayTitle, emphasizeValue: true)
                HermesLabeledValue(label: "Assignee", value: task.assignee ?? "Unassigned", isMonospaced: task.assignee != nil)
                HermesLabeledValue(label: "Priority", value: "\(task.priority)", isMonospaced: true)
                HermesLabeledValue(label: "Workspace", value: task.workspaceKind.displayTitle)

                if let workspacePath = task.workspacePath {
                    HermesLabeledValue(label: "Workspace path", value: workspacePath, isMonospaced: true)
                }

                if let progress = task.progressLabel {
                    HermesLabeledValue(label: "Child progress", value: progress, isMonospaced: true)
                }

                if let tenant = task.tenant {
                    HermesLabeledValue(label: "Tenant", value: tenant, isMonospaced: true)
                }

                if let createdBy = task.createdBy {
                    HermesLabeledValue(label: "Created by", value: createdBy, isMonospaced: true)
                }

                if let created = task.createdDate {
                    HermesLabeledValue(label: "Created", value: DateFormatters.shortDateTimeFormatter().string(from: created))
                }

                if let latest = task.latestActivityDate {
                    HermesLabeledValue(label: "Latest activity", value: DateFormatters.shortDateTimeFormatter().string(from: latest))
                }

                if let workerPID = task.workerPID {
                    HermesLabeledValue(label: "Worker PID", value: "\(workerPID)", isMonospaced: true)
                }

                if let heartbeat = task.lastHeartbeatAt {
                    HermesLabeledValue(
                        label: "Heartbeat",
                        value: DateFormatters.shortDateTimeFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(heartbeat)))
                    )
                }
            }

            if !task.skills.isEmpty {
                Divider()
                    .opacity(0.5)

                HermesWrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(task.skills, id: \.self) { skill in
                        HermesBadge(text: skill, tint: .accentColor, isMonospaced: true)
                    }
                }
            }

            if let lastSpawnError = task.lastSpawnError {
                Divider()
                    .opacity(0.5)

                KanbanWarningBanner(message: lastSpawnError)
            }
        }
    }

    private func actionPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel(
            title: "Actions",
            subtitle: "Small, explicit mutations sent to the remote board over SSH."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                KanbanFormField(label: "Assignee") {
                    HStack(spacing: 8) {
                        ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                        Button("Assign") {
                            Task { await onAssign(task.id, draft.normalizedAssignee) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight)
                    }
                }

                KanbanFormField(label: "Comment") {
                    VStack(alignment: .trailing, spacing: 8) {
                        TextEditor(text: $draft.comment)
                            .font(.body)
                            .frame(minHeight: 72)
                            .padding(8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button("Add Comment") {
                            Task {
                                if await onComment(task.id, draft.comment) {
                                    draft.comment = ""
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight || draft.normalizedComment == nil)
                    }
                }

                KanbanFormField(label: "Completion result") {
                    TextField("Optional handoff summary", text: $draft.result)
                        .textFieldStyle(.roundedBorder)
                }

                KanbanFormField(label: "Block reason") {
                    TextField("Optional reason", text: $draft.blockReason)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func linksPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Dependencies",
            subtitle: "Parent and child task links discovered on the board."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                KanbanIDGroup(title: "Parents", ids: detail.parentIDs)
                KanbanIDGroup(title: "Children", ids: detail.childIDs)
            }
        }
    }

    private func commentsPanel(_ task: KanbanTask, _ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Comments",
            subtitle: "Human and agent notes attached to this task."
        ) {
            if detail.comments.isEmpty {
                Text(L10n.string("No comments yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.comments) { comment in
                        KanbanCommentRow(comment: comment)
                    }
                }
            }
        }
    }

    private func runsPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Runs",
            subtitle: "Attempt history recorded by Hermes."
        ) {
            if detail.runs.isEmpty {
                Text(L10n.string("No runs recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.runs) { run in
                        KanbanRunRow(run: run)
                    }
                }
            }
        }
    }

    private func eventsPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Events",
            subtitle: "Chronological board events for this task."
        ) {
            if detail.events.isEmpty {
                Text(L10n.string("No events recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.events.suffix(20)) { event in
                        KanbanEventRow(event: event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logPanel(_ detail: KanbanTaskDetail) -> some View {
        if let log = detail.workerLog?.trimmingCharacters(in: .whitespacesAndNewlines), !log.isEmpty {
            HermesSurfacePanel(
                title: "Worker Log",
                subtitle: "Tail of the remote worker log for this task."
            ) {
                HermesInsetSurface {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct KanbanFormField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct ComboBoxTextField: View {
    @Binding var text: String
    let suggestions: [String]
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)

            if !suggestions.isEmpty {
                Menu {
                    Button("Unassigned") {
                        text = ""
                    }

                    Divider()

                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            text = suggestion
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .help(L10n.string("Pick a discovered assignee"))
            }
        }
    }
}

private struct KanbanIDGroup: View {
    let title: String
    let ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)

            if ids.isEmpty {
                Text(L10n.string("None"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HermesWrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(ids, id: \.self) { id in
                        HermesBadge(text: id, tint: .secondary, isMonospaced: true)
                    }
                }
            }
        }
    }
}

private struct KanbanCommentRow: View {
    let comment: KanbanComment

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))

                    Text(DateFormatters.relativeFormatter().localizedString(for: comment.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(comment.body)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct KanbanRunRow: View {
    let run: KanbanRun

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HermesBadge(text: "#\(run.id)", tint: .secondary, isMonospaced: true)
                    HermesBadge(text: run.resolvedOutcome, tint: run.endedAt == nil ? .orange : .secondary)

                    if let profile = run.profile {
                        HermesBadge(text: "@\(profile)", tint: .accentColor, isMonospaced: true)
                    }
                }

                Text(DateFormatters.shortDateTimeFormatter().string(from: run.startedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summary = run.summary {
                    Text(summary)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }

                if let error = run.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct KanbanEventRow: View {
    let event: KanbanEvent

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HermesBadge(text: event.kind, tint: .secondary)

                    if let runID = event.runID {
                        HermesBadge(text: "run \(runID)", tint: .secondary, isMonospaced: true)
                    }

                    Spacer(minLength: 8)

                    Text(DateFormatters.relativeFormatter().localizedString(for: event.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let payload = event.displayPayload {
                    Text(payload)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
