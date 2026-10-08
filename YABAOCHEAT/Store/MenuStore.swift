import Foundation
import SwiftUI

/// Central app state: which game is selected, what controls the catalog offers,
/// and the live state of each game's injector.
///
/// One store for the whole app rather than a store per game — the catalog and
/// the authorization session are shared, and only the inject states are per-game.
@MainActor
public final class MenuStore: ObservableObject {
    public static let shared = MenuStore()

    // MARK: selection

    @AppStorage(Game.defaultsKey)
    private var storedGame: String = Game.freeFireMax.rawValue

    @Published public var selectedGame: Game {
        didSet { persistSelection() }
    }

    // MARK: catalog

    /// Controls the server sent, grouped by section, in catalog order.
    @Published public var catalog: [ControlDescriptor] = []

    /// Section order as the server sent it. Kept separate from `catalog` so a
    /// section that happens to be empty still renders its header.
    @Published public var sections: [String] = []

    /// Per-game control values, loaded lazily from `UserDefaults`.
    @Published public var configurations: [Game: FeatureControls] = [:]

    // MARK: injection

    @Published public var injectStates: [Game: InjectState] = [:]
    @Published public var resolutions: [Game: ContainerResolution] = [:]
    @Published public var injected: Set<Game> = []

    /// `liveUpdateTasks` keyed by game — the heartbeat is per game because the
    /// session is bound to the payload that is running.
    var liveUpdateTasks: [Game: Task<Void, Never>] = [:]

    /// Namespace for the defaults keys this store owns.
    enum defaults {
        static let catalog = "ffxc.catalog"
        static let sections = "ffxc.sections"
        static let controlPrefix = Game.controlsPrefix
    }

    private let log: AppLog

    private init(log: AppLog = .shared) {
        self.log = log

        // Read the backing store directly: `storedGame` is not reachable from
        // phase-1 init before `selectedGame` has a value.
        let stored = UserDefaults.standard.string(forKey: Game.defaultsKey)
            ?? Game.freeFireMax.rawValue
        selectedGame = Game(rawValue: stored) ?? .freeFireMax

        // Every game starts in .checking; the resolution pass fills it in.
        for g in Game.allCases {
            injectStates[g] = .checking
            resolutions[g] = nil
            configurations[g] = FeatureControls.load(for: g)
        }
    }

    // MARK: - catalog

    /// Adopt a catalog from the licensing response.
    public func apply(catalog descriptors: [ControlDescriptor], sections: [String]) {
        catalog = descriptors
        self.sections = sections.isEmpty ? Array(Set(descriptors.map(\.section))).sorted() : sections

        UserDefaults.standard.set(self.sections, forKey: defaults.sections)
        if let data = try? JSONEncoder().encode(descriptors) {
            UserDefaults.standard.set(data, forKey: defaults.catalog)
        }

        // Seed any control the user has not touched yet from its `initial`.
        for descriptor in descriptors {
            var config = configurations[selectedGame] ?? FeatureControls()
            if descriptor.initial != nil {
                // Only applied when the stored value is still at the default;
                // a user-set value is never overwritten by a catalog refresh.
                if config.isDefault { config.applyInitial(descriptor) }
            }
            configurations[selectedGame] = config
        }
    }

    /// The controls for the current game, filtered to one section.
    public func controls(inSection section: String) -> [ControlDescriptor] {
        catalog.filter { $0.section == section }
    }

    // MARK: - controls

    public var controls: FeatureControls {
        get { configurations[selectedGame] ?? FeatureControls() }
        set { configurations[selectedGame] = newValue; newValue.save(for: selectedGame) }
    }

    public func binding(for descriptor: ControlDescriptor) -> Binding<Double> {
        Binding(
            get: { self.value(of: descriptor) },
            set: { self.setValue($0, of: descriptor) }
        )
    }

    public func toggle(for descriptor: ControlDescriptor) -> Binding<Bool> {
        Binding(
            get: { self.value(of: descriptor) >= 0.5 },
            set: { self.setValue($0 ? 1 : 0, of: descriptor) }
        )
    }

    public func picker(for descriptor: ControlDescriptor) -> Binding<String> {
        Binding(
            get: {
                let options = descriptor.options ?? []
                let index = Int(self.value(of: descriptor))
                guard options.indices.contains(index) else { return "" }
                return self.optionValue(options[index])
            },
            set: { newValue in
                guard let options = descriptor.options,
                      let index = options.firstIndex(where: { self.optionValue($0) == newValue })
                else { return }
                self.setValue(Double(index), of: descriptor)
            }
        )
    }

    private func optionValue(_ option: String) -> String {
        option.split(separator: "|").last.map(String.init) ?? option
    }

    func value(of descriptor: ControlDescriptor) -> Double {
        let c = controls
        switch descriptor.id {
        case ControlID.headshot.rawValue:            return c.headshotValue ? 1 : 0
        case ControlID.aimTarget.rawValue:           return c.aimTarget == "head" ? 0 : 1
        case ControlID.aimbotFovMode.rawValue:       return c.aimFovMode == "strict" ? 0 : 1
        case ControlID.fastReloadPercent.rawValue:   return Double(c.fastReloadPercent)
        case ControlID.fastFire.rawValue:            return Double(c.fastFireLevel)
        case ControlID.colorControl.rawValue:        return Double(c.espColor)
        default:                                     return c.aimbotRadiusValue
        }
    }

    func setValue(_ new: Double, of descriptor: ControlDescriptor) {
        var c = controls
        switch descriptor.id {
        case ControlID.headshot.rawValue:            c.headshotValue = new >= 0.5
        case ControlID.aimTarget.rawValue:           c.aimTarget = new >= 0.5 ? "body" : "head"
        case ControlID.aimbotFovMode.rawValue:       c.aimFovMode = new >= 0.5 ? "loose" : "strict"
        case ControlID.fastReloadPercent.rawValue:   c.fastReloadPercent = Int(new)
        case ControlID.fastFire.rawValue:            c.fastFireLevel = Int(new)
        case ControlID.colorControl.rawValue:        c.espColor = Int(new)
        default:                                     c.aimbotRadiusValue = new
        }
        controls = c
    }

    // MARK: - selection

    private func persistSelection() {
        storedGame = selectedGame.rawValue
        log.log(.runtime, "selected game: \(selectedGame.rawValue)")
    }

    // MARK: - live updates

    func setLiveUpdate(_ task: Task<Void, Never>?, for game: Game) {
        liveUpdateTasks[game]?.cancel()
        liveUpdateTasks[game] = task
    }

    func cancelAllLiveUpdates() {
        for (_, task) in liveUpdateTasks { task.cancel() }
        liveUpdateTasks.removeAll()
    }
}

extension FeatureControls {
    /// True when nothing has been changed from the shipped defaults, which is the
    /// condition under which a catalog `initial` is allowed to apply.
    public var isDefault: Bool { self == FeatureControls() }

    mutating func applyInitial(_ descriptor: ControlDescriptor) {
        guard let initial = descriptor.initial else { return }
        switch descriptor.id {
        case ControlID.fastReloadPercent.rawValue: fastReloadPercent = Int(initial)
        case ControlID.fastFire.rawValue:          fastFireLevel = Int(initial)
        default:                                   aimbotRadiusValue = initial
        }
    }
}
