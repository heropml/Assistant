import Foundation

@MainActor
final class ActionStore: ObservableObject {
    @Published private(set) var actions: [QuickAction]
    @Published private(set) var enabledIDs: Set<String>
    @Published private(set) var applicationActions: [ApplicationAction]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedPreferences.defaults) {
        self.defaults = defaults
        actions = SharedPreferences.orderedActions(defaults: defaults)
        if let saved = defaults.stringArray(forKey: SharedPreferences.enabledActionIDsKey) {
            enabledIDs = Set(saved)
        } else {
            enabledIDs = Set(QuickAction.defaultEnabledActions.map(\.rawValue))
        }

        applicationActions = SharedPreferences.applicationActions(defaults: defaults)
        if defaults.data(forKey: SharedPreferences.applicationActionsKey) == nil {
            Self.persist([], defaults: defaults)
        }
    }

    var enabledCount: Int {
        actions.filter { enabledIDs.contains($0.rawValue) }.count
            + applicationActions.filter(\.isEnabled).count
    }

    func isEnabled(_ action: QuickAction) -> Bool {
        enabledIDs.contains(action.rawValue)
    }

    func setEnabled(_ enabled: Bool, for action: QuickAction) {
        if enabled {
            enabledIDs.insert(action.rawValue)
        } else {
            enabledIDs.remove(action.rawValue)
        }
        saveBuiltInActions()
    }

    func move(_ action: QuickAction, by offset: Int) {
        guard let source = actions.firstIndex(of: action) else { return }
        let destination = source + offset
        guard actions.indices.contains(destination) else { return }
        actions.swapAt(source, destination)
        saveBuiltInActions()
    }

    func canMove(_ action: QuickAction, by offset: Int) -> Bool {
        guard let index = actions.firstIndex(of: action) else { return false }
        return actions.indices.contains(index + offset)
    }

    @discardableResult
    func addApplication(at url: URL) -> Bool {
        let newAction = ApplicationAction(applicationURL: url)
        if let index = applicationActions.firstIndex(where: {
            if let newIdentifier = newAction.bundleIdentifier, let existingIdentifier = $0.bundleIdentifier {
                return newIdentifier == existingIdentifier
            }
            return $0.applicationPath == newAction.applicationPath
        }) {
            applicationActions[index].isEnabled = true
            saveApplicationActions()
            return false
        }
        applicationActions.append(newAction)
        saveApplicationActions()
        return true
    }

    func setEnabled(_ enabled: Bool, for application: ApplicationAction) {
        guard let index = applicationActions.firstIndex(where: { $0.id == application.id }) else { return }
        applicationActions[index].isEnabled = enabled
        saveApplicationActions()
    }

    func updateMenuTitle(_ title: String, for application: ApplicationAction) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = applicationActions.firstIndex(where: { $0.id == application.id }) else { return }
        applicationActions[index].menuTitle = trimmed
        saveApplicationActions()
    }

    func removeApplication(_ application: ApplicationAction) {
        applicationActions.removeAll { $0.id == application.id }
        saveApplicationActions()
    }

    func move(_ application: ApplicationAction, by offset: Int) {
        guard let source = applicationActions.firstIndex(where: { $0.id == application.id }) else { return }
        let destination = source + offset
        guard applicationActions.indices.contains(destination) else { return }
        applicationActions.swapAt(source, destination)
        saveApplicationActions()
    }

    func canMove(_ application: ApplicationAction, by offset: Int) -> Bool {
        guard let index = applicationActions.firstIndex(where: { $0.id == application.id }) else { return false }
        return applicationActions.indices.contains(index + offset)
    }

    private func saveBuiltInActions() {
        defaults.set(actions.map(\.rawValue), forKey: SharedPreferences.orderedActionIDsKey)
        defaults.set(actions.filter { enabledIDs.contains($0.rawValue) }.map(\.rawValue),
                     forKey: SharedPreferences.enabledActionIDsKey)
        defaults.synchronize()
    }

    private func saveApplicationActions() {
        Self.persist(applicationActions, defaults: defaults)
    }

    private static func persist(_ applications: [ApplicationAction], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        defaults.set(data, forKey: SharedPreferences.applicationActionsKey)
        defaults.synchronize()
    }

}
