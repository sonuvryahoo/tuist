import ProjectDescription
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class PackageInfoMapperTests: TuistUnitTestCase {
    private var subject: PackageInfoMapper!

    override func setUp() {
        super.setUp()

        subject = PackageInfoMapper()

        // FileHandler
        fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        FileHandler.shared = fileHandler
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func testMap() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1")
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1")
                ]
            )
        )
    }

    func testMap_whenNameContainsUnderscors_mapsToDashInBundleID() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                ],
                targets: [
                    .test(name: "Target_1")
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target_1", customBundleID: "Target-1")
                ]
            )
        )
    }

    func testMap_whenTargetNotInProduct_ignoresIt() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2"),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1")
                ]
            )
        )
    }

    func testMap_whenTargetIsNotRegular_ignoresTarget() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1", "Target2", "Target3"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2", type: .test),
                    .test(name: "Target3", type: .binary),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1")
                ]
            )
        )
    }

    func testMap_whenProductIsNotLibrary_ignoresProduct() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    .init(name: "Product2", type: .plugin, targets: ["Target2"]),
                    .init(name: "Product3", type: .test, targets: ["Target3"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2"),
                    .test(name: "Target3"),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1")
                ]
            )
        )
    }

    func testMap_whenCustomSources() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1", sources: ["Subfolder", "Another/Subfolder/file.swift"]),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        customSources: [
                            "/Package/Path/Sources/Target1/Subfolder/**",
                            "/Package/Path/Sources/Target1/Another/Subfolder/file.swift",
                        ]
                    )
                ]
            )
        )
    }

    func testMap_whenHasResources() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        resources: [
                            .init(rule: .copy, path: "Resource/Folder"),
                            .init(rule: .process, path: "Another/Resource/Folder"),
                        ]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        resources: [
                            "/Package/Path/Sources/Target1/Resource/Folder/**",
                            "/Package/Path/Sources/Target1/Another/Resource/Folder/**",
                        ]
                    )
                ]
            )
        )
    }

    func testMap_whenHasHeaders() throws {
        fileHandler.stubFilesAndDirectoriesContained = { path in
            XCTAssertEqual(path, "/Package/Path/Sources/Target1")
            return [
                "/Package/Path/Sources/Package/Source.swift",
                "/Package/Path/Sources/Package/Source.c",
                "/Package/Path/Sources/Package/Source.h",
            ]
        }
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1"
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        headers: .init(public: "/Package/Path/Sources/Package/Source.h")
                    )
                ]
            )
        )
    }

    func testMap_whenCustomPath() throws {
        fileHandler.stubFilesAndDirectoriesContained = { path in
            XCTAssertEqual(path, "/Package/Path/Custom/Path")
            return [
                "/Package/Path/Custom/Path/Source.swift",
                "/Package/Path/Custom/Path/Source.c",
                "/Package/Path/Custom/Path/Source.h",
            ]
        }
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        path: "Custom/Path",
                        sources: ["Sources/Folder"],
                        resources: [.init(rule: .copy, path: "Resource/Folder")]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        customSources: "/Package/Path/Custom/Path/Sources/Folder/**",
                        resources: "/Package/Path/Custom/Path/Resource/Folder/**",
                        headers: .init(public: "/Package/Path/Custom/Path/Source.h")
                    )
                ]
            )
        )
    }

    func testMap_whenIOSAvailable_takesIOS() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: []
            ),
            platforms: [.iOS, .tvOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .iOS)
                ]
            )
        )
    }

    func testMap_whenIOSNotAvailable_takesOthers() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: []
            ),
            platforms: [.tvOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .tvOS)
                ]
            )
        )
    }

    func testMap_whenNoneAvailable_throws() throws {
        XCTAssertThrowsSpecific(
            try subject.map(
                packageInfo: .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.init(platformName: "tvos", version: "13.0", options: [])]
                ),
                platforms: [.iOS]
            ),
            SwiftPackageManagerGraphGeneratorError.noSupportedPlatforms(
                name: "Package",
                configured: [.iOS],
                package: [.tvOS]
            )
        )
    }

    func testMap_whenPackageDefinesPlatform_configuresDeploymentTarget() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: [.init(platformName: "ios", version: "13.0", options: [])]
            ),
            platforms: [.iOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .iOS, deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad, .mac]))
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        settings: [.init(tool: .c, name: .headerSearchPath, condition: nil, value: ["value"])]
                    )
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["value"]])
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        settings: [.init(tool: .cxx, name: .headerSearchPath, condition: nil, value: ["value"])]
                    )
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["value"]])
                ]
            )
        )
    }
}

extension PackageInfoMapping {
    fileprivate func map(
        packageInfo: PackageInfo,
        platforms: Set<TuistGraph.Platform> = [.iOS]
    ) throws -> ProjectDescription.Project {
        return try self.map(
            packageInfo: packageInfo,
            packageInfos: [:],
            name: "Package",
            path: "/Package/Path",
            productTypes: [:],
            platforms: platforms,
            deploymentTargets: [],
            packageToProject: [:],
            productToPackage: [:],
            targetDependencyToFramework: [:]
        )
    }
}

extension PackageInfo.Target {
    fileprivate static func test(
        name: String,
        type: PackageInfo.Target.TargetType = .regular,
        path: String? = nil,
        sources: [String]? = nil,
        resources: [PackageInfo.Target.Resource] = [],
        settings: [TargetBuildSettingDescription.Setting] = []
    ) -> Self {
        return .init(
            name: name,
            path: path,
            url: nil,
            sources: sources,
            resources: resources,
            exclude: [],
            dependencies: [],
            publicHeadersPath: nil,
            type: type,
            settings: settings,
            checksum: nil
        )
    }
}

extension ProjectDescription.Project {
    fileprivate static func test(name: String, targets: [ProjectDescription.Target]) -> Self {
        return .init(
            name: "Package",
            targets: targets,
            resourceSynthesizers: []
        )
    }
}

extension ProjectDescription.Target {
    fileprivate static func test(
        _ name: String,
        platform: ProjectDescription.Platform = .iOS,
        customBundleID: String? = nil,
        deploymentTarget: ProjectDescription.DeploymentTarget? = nil,
        customSources: SourceFilesList? = nil,
        resources: ResourceFileElements? = nil,
        headers: ProjectDescription.Headers? = nil,
        customSettings: ProjectDescription.SettingsDictionary = [:]
    ) -> Self {
        return .init(
            name: name,
            platform: platform,
            product: .staticFramework,
            bundleId: customBundleID ?? name,
            deploymentTarget: deploymentTarget,
            infoPlist: .default,
            sources: customSources ?? "/Package/Path/Sources/\(name)/**",
            resources: resources,
            headers: headers,
            settings: DependenciesGraph.spmSettings(with: customSettings)
        )
    }
}
