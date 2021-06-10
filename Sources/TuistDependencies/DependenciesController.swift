import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Dependencies Controller Error

enum DependenciesControllerError: FatalError, Equatable {
    /// Thrown when platforms for dependencies to install are not determined in `Dependencies.swift`.
    case noPlatforms

    /// Thrown when the same dependency is defined more than once.
    case duplicatedDependency(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .noPlatforms, .duplicatedDependency:
            return .abort
        }
    }

    // Error description.
    var description: String {
        switch self {
        case .noPlatforms:
            return "Platforms were not determined. Select platforms in `Dependencies.swift` manifest file."
        case let .duplicatedDependency(name):
            return "The \(name) dependency is defined more than once."
        }
    }
}

// MARK: - Dependencies Controlling

/// `DependenciesControlling` controls:
///     1. Fetching/updating dependencies defined in `./Tuist/Dependencies.swift` by running appropriate dependencies managers (`Cocoapods`, `Carthage`, `SPM`).
///     2. Compiling fetched/updated dependencies into `.framework.`/`.xcframework.`.
///     3. Saving compiled frameworks under `./Tuist/Dependencies/*`.
///     4. Generating dependencies graph under `./Tuist/Dependencies/graph.json`.
public protocol DependenciesControlling {
    /// Fetches dependencies.
    /// - Parameter path: Directory where project's dependencies will be fetched.
    /// - Parameter dependencies: List of dependencies to fetch.
    /// - Parameter swiftVersion: The specified version of Swift. If `nil` is passed then the environment’s version will be used.
    func fetch(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws

    /// Updates dependencies.
    /// - Parameters:
    ///   - path: Directory where project's dependencies will be updated.
    ///   - dependencies: List of dependencies to update.
    ///   - swiftVersion: The specified version of Swift. If `nil` is passed then will use the environment’s version will be used.
    func update(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws
}

// MARK: - Dependencies Controller

public final class DependenciesController: DependenciesControlling {
    private let carthageInteractor: CarthageInteracting
    private let cocoaPodsInteractor: CocoaPodsInteracting
    private let swiftPackageManagerInteractor: SwiftPackageManagerInteracting
    private let dependenciesGraphController: DependenciesGraphControlling

    public init(
        carthageInteractor: CarthageInteracting = CarthageInteractor(),
        cocoaPodsInteractor: CocoaPodsInteracting = CocoaPodsInteractor(),
        swiftPackageManagerInteractor: SwiftPackageManagerInteracting = SwiftPackageManagerInteractor(),
        dependenciesGraphController: DependenciesGraphControlling = DependenciesGraphController()
    ) {
        self.carthageInteractor = carthageInteractor
        self.cocoaPodsInteractor = cocoaPodsInteractor
        self.swiftPackageManagerInteractor = swiftPackageManagerInteractor
        self.dependenciesGraphController = dependenciesGraphController
    }

    public func fetch(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws {
        try install(
            at: path,
            dependencies: dependencies,
            shouldUpdate: false,
            swiftVersion: swiftVersion
        )
    }

    public func update(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws {
        try install(
            at: path,
            dependencies: dependencies,
            shouldUpdate: true,
            swiftVersion: swiftVersion
        )
    }

    // MARK: - Helpers

    private func install(
        at path: AbsolutePath,
        dependencies: Dependencies,
        shouldUpdate: Bool,
        swiftVersion: String?
    ) throws {
        let dependenciesDirectory = path
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
        let platforms = dependencies.platforms

        guard !platforms.isEmpty else {
            throw DependenciesControllerError.noPlatforms
        }

        var dependenciesGraph = DependenciesGraph(thirdPartyDependencies: [:])

        if let carthageDependencies = dependencies.carthage, !carthageDependencies.dependencies.isEmpty {
            let carthageDependenciesGraph = try carthageInteractor.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: carthageDependencies,
                platforms: platforms,
                shouldUpdate: shouldUpdate
            )
            dependenciesGraph = try dependenciesGraph.merging(with: carthageDependenciesGraph)
        } else {
            try carthageInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }

        if let swiftPackageManagerDependencies = dependencies.swiftPackageManager, !swiftPackageManagerDependencies.packages.isEmpty {
            let swiftPackageManagerDependenciesGraph = try swiftPackageManagerInteractor.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: swiftPackageManagerDependencies,
                shouldUpdate: shouldUpdate,
                swiftToolsVersion: swiftVersion
            )
            dependenciesGraph = try dependenciesGraph.merging(with: swiftPackageManagerDependenciesGraph)
        } else {
            try swiftPackageManagerInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }

        if dependenciesGraph.thirdPartyDependencies.isEmpty {
            try dependenciesGraphController.clean(at: path)
        } else {
            try dependenciesGraphController.save(dependenciesGraph, to: path)
        }
    }
}

extension DependenciesGraph {
    fileprivate func merging(with other: Self) throws -> Self {
        let mergedThirdPartyDependencies = try thirdPartyDependencies.merging(other.thirdPartyDependencies) { old, _ in
            let name = self.thirdPartyDependencies.first { $0.value == old }!.key
            throw DependenciesControllerError.duplicatedDependency(name)
        }
        return .init(thirdPartyDependencies: mergedThirdPartyDependencies)
    }
}
