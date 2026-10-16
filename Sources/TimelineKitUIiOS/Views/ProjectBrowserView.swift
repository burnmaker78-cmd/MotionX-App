
#if canImport(UIKit)
import SwiftUI
import TimelineKitCore
import TimelineKitUIShared

public struct ProjectBrowserView: View {
    @Bindable var libraryStore: TimelineLibraryStore

    @State private var showCreateProject = false
    @State private var newProjectName = ""
    @State private var renameTarget: LibraryProject?
    @State private var renameText = ""
    @State private var deleteTarget: LibraryProject?
    @State private var errorMessage: String?
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private let backgroundColor = Color(
        red: 0.035, green: 0.04, blue: 0.075
    )

    public init(libraryStore: TimelineLibraryStore) {
        self.libraryStore = libraryStore
    }

    private var filteredProjects: [LibraryProject] {
        let matching = libraryStore.projects.filter {
            searchText.isEmpty ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        return matching.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
    }

    public var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    searchBar
                    projectsSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("MotionX")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateProject = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.cyan,
                                    Color.purple
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Create project")
            }
        }
        .navigationDestination(for: UUID.self) { projectID in
            editorDestination(projectID: projectID)
        }
        .alert("New Project", isPresented: $showCreateProject) {
            TextField(
                "Project name",
                text: $newProjectName,
                prompt: Text("Untitled Project")
            )

            Button("Create") {
                createProject()
            }

            Button("Cancel", role: .cancel) {
                newProjectName = ""
            }
        } message: {
            Text("Create a project and start editing your video.")
        }
        .alert(
            "Rename Project",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Project name", text: $renameText)

            Button("Save") {
                commitRename()
            }

            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                commitDelete()
            }

            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(
                "Delete \"\(deleteTarget?.name ?? "")\"? This cannot be undone."
            )
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            libraryStore.refreshProjects()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.9),
                                    Color.purple.opacity(0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "waveform.path")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MotionX")
                        .font(.system(size: 27, weight: .heavy))
                        .foregroundStyle(.white)

                    Text("CREATE WITHOUT LIMITS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.cyan.opacity(0.85))
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.purple.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your creative space")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)

                Text("Bring your next video to life.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.45))

            TextField("Search your projects", text: $searchText)
                .font(.system(size: 15))
                .tint(.cyan)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Projects")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)

                    Text("\(filteredProjects.count) projects")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Button {
                    showCreateProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.cyan.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            if filteredProjects.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredProjects) { project in
                        NavigationLink(value: project.id) {
                            ProjectCardView(project: project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                renameTarget = project
                                renameText = project.name
                            } label: {
                                Label(
                                    "Rename",
                                    systemImage: "pencil"
                                )
                            }

                            Button {
                                duplicate(project)
                            } label: {
                                Label(
                                    "Duplicate",
                                    systemImage: "doc.on.doc"
                                )
                            }

                            Button {
                                togglePin(project)
                            } label: {
                                Label(
                                    project.isPinned
                                        ? "Unpin Project"
                                        : "Pin Project",
                                    systemImage: project.isPinned
                                        ? "pin.slash"
                                        : "pin"
                                )
                            }

                            Button(role: .destructive) {
                                deleteTarget = project
                            } label: {
                                Label(
                                    "Delete",
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.045))

                Image(
                    systemName: searchText.isEmpty
                        ? "film.stack"
                        : "magnifyingglass"
                )
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .frame(width: 88, height: 88)

            Text(
                searchText.isEmpty
                    ? "Your story starts here"
                    : "No projects found"
            )
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)

            Text(
                searchText.isEmpty
                    ? "Create a project and make something amazing."
                    : "Try searching for another project name."
            )
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)

            if searchText.isEmpty {
                Button {
                    showCreateProject = true
                } label: {
                    Label(
                        "Create Your First Project",
                        systemImage: "plus"
                    )
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    Color.white.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func editorDestination(projectID: UUID) -> some View {
        if let project = libraryStore.projects.first(
            where: { $0.id == projectID }
        ) {
            ClipEditorView(
                libraryStore: libraryStore,
                project: project
            )
        } else {
            ContentUnavailableView(
                "Project Not Found",
                systemImage: "film",
                description: Text(
                    "This project may have been deleted."
                )
            )
        }
    }

    // MARK: - Project Actions

    private func createProject() {
        let name = newProjectName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let finalName = name.isEmpty ? "Untitled Project" : name
        newProjectName = ""

        do {
            _ = try libraryStore.createProject(name: finalName)
            libraryStore.refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        renameTarget = nil

        let name = renameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !name.isEmpty, name != target.name else { return }

        do {
            try libraryStore.renameProject(
                id: target.id,
                newName: name
            )
            libraryStore.refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicate(_ project: LibraryProject) {
        do {
            _ = try libraryStore.duplicateProject(id: project.id)
            libraryStore.refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePin(_ project: LibraryProject) {
        do {
            try libraryStore.setPinned(
                id: project.id,
                isPinned: !project.isPinned
            )
            libraryStore.refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil

        do {
            try libraryStore.deleteProject(id: target.id)
            libraryStore.refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Project Card

private struct ProjectCardView: View {
    let project: LibraryProject

    private let cyan = Color.cyan
    private let purple = Color.purple

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.13, blue: 0.23),
                                Color(red: 0.17, green: 0.09, blue: 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(cyan.opacity(0.13))
                    .frame(width: 95, height: 95)
                    .blur(radius: 2)
                    .offset(x: 15, y: -18)

                Circle()
                    .fill(purple.opacity(0.16))
                    .frame(width: 80, height: 80)
                    .blur(radius: 2)
                    .offset(x: -65, y: 50)

                Image(systemName: "waveform.path")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [cyan, purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if project.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                        .padding(9)
                }

                VStack {
                    Spacer()

                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))

                        Text("EDIT PROJECT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)

                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.38))
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 7) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text(
                        ProjectCardView.durationString(
                            seconds: project.timeline.duration
                        )
                    )
                    .monospacedDigit()

                    Spacer(minLength: 2)

                    Text(
                        ProjectCardView.dateString(
                            project.createdAt
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(9)
        .background(Color(red: 0.075, green: 0.08, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(
                    Color.white.opacity(0.075),
                    lineWidth: 1
                )
        }
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(
            .dateTime.month(.abbreviated).day()
        )
    }

    private static func durationString(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            seconds
        )
    }
}

#endif
