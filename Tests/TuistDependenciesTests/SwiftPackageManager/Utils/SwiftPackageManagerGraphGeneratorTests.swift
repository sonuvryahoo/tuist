import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies
import TuistGraph
import XCTest
@testable import TuistDependenciesTesting
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

class SwiftPackageManagerGraphGeneratorTests: TuistTestCase {
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var subject: SwiftPackageManagerGraphGenerator!
    private var path: AbsolutePath { try! temporaryPath() }
    private var spmFolder: Path { Path(path.pathString) }
    private var checkoutsPath: AbsolutePath { path.appending(component: "checkouts") }

    override func setUp() {
        super.setUp()
        swiftPackageManagerController = MockSwiftPackageManagerController()
        subject = SwiftPackageManagerGraphGenerator(swiftPackageManagerController: swiftPackageManagerController)
    }

    override func tearDown() {
        fileHandler = nil
        swiftPackageManagerController = nil
        subject = nil
        super.tearDown()
    }

    func test_generate_alamofire() throws {
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "Alamofire",
                  "path": "https://github.com/Alamofire/Alamofire"
                }
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                XCTAssertEqual(packagePath, self.path.appending(component: "checkouts").appending(component: "Alamofire"))
                return PackageInfo.alamofire
            },
            dependenciesGraph: .alamofire(spmFolder: spmFolder)
        )
    }

    func test_generate_google_measurement() throws {
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "GoogleAppMeasurement",
                  "path": "https://github.com/google/GoogleAppMeasurement"
                }
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "GoogleUtilities",
                  "path": "https://github.com/google/GoogleUtilities"
                }
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "nanopb",
                  "path": "https://github.com/nanopb/nanopb"
                }
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case self.checkoutsPath.appending(component: "GoogleAppMeasurement"):
                    return PackageInfo.googleAppMeasurement
                case self.checkoutsPath.appending(component: "GoogleUtilities"):
                    return PackageInfo.googleUtilities
                case self.checkoutsPath.appending(component: "nanopb"):
                    return PackageInfo.nanopb
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            dependenciesGraph: try .googleAppMeasurement(spmFolder: spmFolder)
                .merging(with: .googleUtilities(
                    spmFolder: spmFolder,
                    customProductTypes: [
                        "GULMethodSwizzler": .framework,
                        "GULNetwork": .dynamicLibrary,
                    ]
                ))
                .merging(with: .nanopb(spmFolder: spmFolder))
        )
    }

    func test_generate_test() throws {
        let testPath = AbsolutePath("/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "kind": "local",
                  "name": "test",
                  "path": "\(testPath.pathString)"
                }
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "a-dependency",
                  "path": "https://github.com/dependencies/a-dependency"
                }
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "another-dependency",
                  "path": "https://github.com/dependencies/another-dependency"
                }
              }
            ]
            """,
            stubFilesAndDirectoriesContained: { path in
                guard path == testPath.appending(component: "customPath").appending(component: "customPublicHeadersPath") else {
                    return nil
                }

                return [
                    AbsolutePath("/not/an/header.swift"),
                    AbsolutePath("/an/header.h"),
                ]
            },
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case testPath:
                    return PackageInfo.test
                case self.checkoutsPath.appending(component: "a-dependency"):
                    return PackageInfo.aDependency
                case self.checkoutsPath.appending(component: "another-dependency"):
                    return PackageInfo.anotherDependency
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            deploymentTargets: [
                .iOS("13.0", [.iphone, .ipad, .mac]),
            ],
            dependenciesGraph: .test(packageFolder: Path(testPath.pathString))
                .merging(with: .aDependency(spmFolder: spmFolder))
                .merging(with: .anotherDependency(spmFolder: spmFolder))
        )
    }

    private func checkGenerated(
        workspaceDependenciesJSON: String,
        stubFilesAndDirectoriesContained: @escaping (AbsolutePath) -> [AbsolutePath]? = { _ in nil },
        loadPackageInfoStub: @escaping (AbsolutePath) -> PackageInfo,
        deploymentTargets: Set<TuistGraph.DeploymentTarget> = [],
        dependenciesGraph: TuistCore.DependenciesGraph
    ) throws {
        // Given
        fileHandler.stubReadFile = {
            XCTAssertEqual($0, self.path.appending(component: "workspace-state.json"))
            return """
            {
              "object": {
                "dependencies": \(workspaceDependenciesJSON)
              }
            }
            """.data(using: .utf8)!
        }

        fileHandler.stubIsFolder = { _ in
            // called to convert globs to AbsolutePath
            true
        }

        fileHandler.stubFilesAndDirectoriesContained = stubFilesAndDirectoriesContained

        swiftPackageManagerController.loadPackageInfoStub = loadPackageInfoStub

        // When
        let got = try subject.generate(
            at: path,
            productTypes: [
                "GULMethodSwizzler": .framework,
                "GULNetwork": .dynamicLibrary,
            ],
            platforms: [.iOS],
            deploymentTargets: deploymentTargets
        )

        // Then
        XCTAssertEqual(got, dependenciesGraph)
    }
}

extension TuistCore.DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        let mergedExternalDependencies = other.externalDependencies.reduce(into: externalDependencies) { result, entry in
            result[entry.key] = entry.value
        }
        let mergedExternalProjects = other.externalProjects.reduce(into: externalProjects) { result, entry in
            result[entry.key] = entry.value
        }
        return .init(externalDependencies: mergedExternalDependencies, externalProjects: mergedExternalProjects)
    }
}
