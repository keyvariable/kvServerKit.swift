//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2023 Svyatoslav Popov (info@keyvar.com).
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
//  the License. You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
//  an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
//  specific language governing permissions and limitations under the License.
//
//  SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//
//  KvDirectoryTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 16.10.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit



final class KvDirectoryTests : XCTestCase {

    // MARK: - testDefaultDirectory()

    func testDefaultDirectory() async throws {

        struct DefaultDirectoryServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvDirectory(at: Constants.htmlDirectoryURL)
                }
            }

        }

        try await TestKit.withRunningServer(of: DefaultDirectoryServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String, expectedPath: String?) async throws {
                switch expectedPath {
                case .some(let expectedPath):
                    let url = Constants.htmlDirectoryURL.appendingPathComponent(expectedPath)
                    let expected = try Data(contentsOf: url)

                    try await TestKit.assertResponse(baseURL, path: path, contentType: nil, expecting: expected)

                case .none:
                    try await TestKit.assertResponse(baseURL, path: path, statusCode: .notFound, expecting: "")
                }
            }

            func AssertUUID(at path: String, isHidden: Bool) async throws {
                try await Assert(path: path + "/uuid.txt", expectedPath: !isHidden ? (path + "/uuid.txt") : nil)
                try await Assert(path: path + "/.uuid.txt", expectedPath: nil)
            }

            try await Assert(path: "", expectedPath: "index.html")
            try await Assert(path: "index.html", expectedPath: "index.html")
            try await Assert(path: "uuid.txt", expectedPath: "uuid.txt")
            try await Assert(path: "sample.txt", expectedPath: nil)
            try await Assert(path: ".uuid.txt", expectedPath: nil)

            try await Assert(path: "a", expectedPath: "a/index")
            try await Assert(path: "a/index", expectedPath: "a/index")
            try await Assert(path: "a/index.html", expectedPath: nil)

            try await AssertUUID(at: "a", isHidden: false)
            try await AssertUUID(at: ".a", isHidden: true)
            try await AssertUUID(at: "a/b", isHidden: false)
            try await AssertUUID(at: "a/.b", isHidden: true)

            try await AssertUUID(at: ".well-known", isHidden: false)
            try await AssertUUID(at: "a/.well-known", isHidden: true)

            try await Assert(path: "./././uuid.txt", expectedPath: "uuid.txt")
            try await Assert(path: ".a/../uuid.txt", expectedPath: "uuid.txt")
            try await Assert(path: ".a/../.././.././uuid.txt", expectedPath: "uuid.txt")
            try await Assert(path: ".a/../../a/c/.././uuid.txt", expectedPath: "a/uuid.txt")

            try await AssertUUID(at: "./c/./..///./.well-known", isHidden: false)
        }
    }



    // MARK: - testUrlResolvation()

    func testUrlResolvation() {
        typealias ResolvedURL = KvDirectory.ResolvedURL

        func Assert(bundlePath: String, expectation: (URL) -> Result<ResolvedURL, KvHttpResponseError>) {
            let url = Bundle.module.resourceURL!.appendingPathComponent(bundlePath)
            XCTAssertEqual(Result(catching: { try ResolvedURL(for: url, indexNames: [ "index.html", "index" ]) }).mapError { $0 as! KvHttpResponseError }, expectation(url), "URL: \(url)")
        }

        Assert(bundlePath: "Resources/sample.txt", expectation: { .success(.init(resolved: $0, isLocal: true)) })
        Assert(bundlePath: "Resources/missing_file", expectation: { .failure(.fileDoesNotExist($0)) })

        Assert(bundlePath: "Resources/html", expectation: { .success(.init(resolved: $0.appendingPathComponent("index.html"), isLocal: true)) })
        Assert(bundlePath: "Resources/html/a", expectation: { .success(.init(resolved: $0.appendingPathComponent("index"), isLocal: true)) })
        Assert(bundlePath: "Resources/html/a/b", expectation: { .failure(.unableToFindIndexFile(directoryURL: $0)) })
    }



    // MARK: - testSubpathResolver()

    func testSubpathResolver() {
        let baseURL = Bundle.module.resourceURL!.appendingPathComponent("Resources/html")

        func Assert(subpath: KvUrlSubpath, blackList: [KvUrlSubpath]?, whiteList: [KvUrlSubpath]?, expected: String?) {
            let result = KvDirectory.resolvedSubpath(subpath, rootURL: baseURL, accessList: .init(black: blackList, white: whiteList))
            let expected =  expected.map { !$0.isEmpty ? baseURL.appendingPathComponent($0) : baseURL }

            XCTAssertEqual(result, expected)
        }

        let blackList: [KvUrlSubpath] = [ "a", "c" ]
        let whiteList: [KvUrlSubpath] = [ ".b", ".d" ]

        Assert(subpath: "", blackList: nil      , whiteList: nil      , expected: "")
        Assert(subpath: "", blackList: blackList, whiteList: whiteList, expected: "")

        Assert(subpath: "a"    , blackList: nil, whiteList: nil, expected: "a")
        Assert(subpath: "a/b/c", blackList: nil, whiteList: nil, expected: "a/b/c")

        Assert(subpath: ".a/b/c", blackList: nil, whiteList: nil, expected: nil)
        Assert(subpath: "a/.b/c", blackList: nil, whiteList: nil, expected: nil)
        Assert(subpath: "a/b/.c", blackList: nil, whiteList: nil, expected: nil)

        Assert(subpath: "a" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".a", blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: "b" , blackList: blackList, whiteList: whiteList, expected: "b")
        Assert(subpath: ".b", blackList: blackList, whiteList: whiteList, expected: ".b")

        Assert(subpath: "a/a" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".a/a", blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: "b/a" , blackList: blackList, whiteList: whiteList, expected: "b/a")
        Assert(subpath: ".b/a", blackList: blackList, whiteList: whiteList, expected: ".b/a")

        Assert(subpath: "a/.a" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".a/.a", blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: "b/.a" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".b/.a", blackList: blackList, whiteList: whiteList, expected: nil)

        Assert(subpath: "a/b" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".a/b", blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: "b/b" , blackList: blackList, whiteList: whiteList, expected: "b/b")
        Assert(subpath: ".b/b", blackList: blackList, whiteList: whiteList, expected: ".b/b")

        Assert(subpath: "a/.b" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".a/.b", blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: "b/.b" , blackList: blackList, whiteList: whiteList, expected: nil)
        Assert(subpath: ".b/.b", blackList: blackList, whiteList: whiteList, expected: nil)

        Assert(subpath: ".a/.b/c", blackList: nil, whiteList: [ ".a/.b", ".a/.bc", ".a/.c/.d", ".a/.c" ], expected: ".a/.b/c")

        Assert(subpath: "a/.b/c" , blackList: nil           , whiteList: [ "a/.b" ], expected: "a/.b/c")
        Assert(subpath: "a/.b/c" , blackList: [ "a", "a/b" ], whiteList: [ "a/.b" ], expected: nil)

        Assert(subpath: "a", blackList: [ "a", "c" ], whiteList: [ "a", "b" ], expected: nil)
    }



    // MARK: - testBlackAndWhiteLists()

    func testBlackAndWhiteLists() async throws {

        struct AccessListServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("1") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .whiteList("a/.b", ".c")
                    }
                    KvGroup("2") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .whiteList("a/.b", "a/.c")
                            .whiteList(".well-known")
                    }
                    KvGroup("3") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .blackList("a", "c")
                            .blackList(".well-known")
                    }
                    KvGroup("4") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .whiteList("a/.b/.uuid.txt")
                    }
                    KvGroup("5") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .whiteList("a/.b/.uuid.txt")
                            .blackList("a/.b")
                    }
                }
            }

        }
        try await TestKit.withRunningServer(of: AccessListServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(directory: String, path: String, expected: String?) async throws {
                switch expected {
                case .some(let expected):
                    let expectedData = try Data(contentsOf: Constants.htmlDirectoryURL.appendingPathComponent(expected))
                    try await TestKit.assertResponse(baseURL, path: directory + "/" + path, contentType: nil, expecting: expectedData)
                case .none:
                    try await TestKit.assertResponse(baseURL, path: directory + "/" + path, statusCode: .notFound, expecting: "")
                }
            }

            try await Assert(directory: "1", path: "a/uuid.txt", expected: "a/uuid.txt")
            try await Assert(directory: "1", path: "a/.b/uuid.txt", expected: "a/.b/uuid.txt")
            try await Assert(directory: "1", path: ".well-known/uuid.txt", expected: nil)

            try await Assert(directory: "2", path: "a/uuid.txt", expected: "a/uuid.txt")
            try await Assert(directory: "2", path: "a/.b/uuid.txt", expected: "a/.b/uuid.txt")
            try await Assert(directory: "2", path: ".well-known/uuid.txt", expected: ".well-known/uuid.txt")

            try await Assert(directory: "3", path: "a/uuid.txt", expected: nil)
            try await Assert(directory: "3", path: ".well-known/uuid.txt", expected: nil)

            try await Assert(directory: "4", path: "a/.b/uuid.txt", expected: nil)
            try await Assert(directory: "4", path: "a/.b/.uuid.txt", expected: "a/.b/.uuid.txt")

            try await Assert(directory: "5", path: "a/.b/uuid.txt", expected: nil)
            try await Assert(directory: "5", path: "a/.b/.uuid.txt", expected: nil)
        }
    }



    // MARK: - testHttpMethodConstraint()

    func testHttpMethodConstraint() async throws {

        struct TestServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvDirectory(at: Constants.htmlDirectoryURL)
                }
            }

        }

        try await TestKit.withRunningServer(of: TestServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, method: "GET"   , path: "uuid.txt", statusCode: .ok, contentType: nil, expecting: Constants.data_uuid_txt)
            try await TestKit.assertResponse(baseURL, method: "HEAD"  , path: "uuid.txt", statusCode: .ok, contentType: nil, expecting: Data())
            try await TestKit.assertResponse(baseURL, method: "POST"  , path: "uuid.txt", statusCode: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, method: "PUT"   , path: "uuid.txt", statusCode: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, method: "DELETE", path: "uuid.txt", statusCode: .notFound, expecting: "")
        }
    }



    // MARK: - testStatusURL()

    func testStatusDirectory() async throws {

        struct StatusDirectoryServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("1") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpStatusDirectory(url: Constants.htmlStatusDirectoryURL)
                    }
                    KvGroup("2") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpStatusDirectory(url: Constants.htmlDirectoryURL.appendingPathComponent("a/.././status"))
                    }
                    KvGroup("3") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpStatusDirectory(pathComponent: "status")
                    }
                    KvGroup("4") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpStatusDirectory(url: Constants.htmlDirectoryURL.appendingPathComponent("status"))
                            .httpStatusFileName {
                                switch $0 {
                                case .badRequest:
                                    return "BadRequest.html"
                                case .notFound:
                                    return "NotFound.html"
                                default:
                                    return nil
                                }
                            }
                    }
                    KvGroup("5") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpStatusDirectory(url: Constants.externalHtmlStatusDirectoryURL)
                    }
                    KvGroup("6") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpStatusDirectory(url: Constants.htmlStatusDirectoryURL)

                        KvHttpResponse.dynamic
                            .query(.required("uuid"))
                            .content { _ in .string { UUID().uuidString } }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: StatusDirectoryServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert404(directory: String, statusDirectoryURL: URL? = nil, customName: Bool = false) async throws {
                let statusDirectoryURL = statusDirectoryURL ?? Constants.htmlStatusDirectoryURL
                let statusFileName = customName ? "NotFound.html" : "404.html"

                let expectedData = try Data(contentsOf: statusDirectoryURL.appendingPathComponent(statusFileName))
                try await TestKit.assertResponse(baseURL, path: directory + "/.uuid.txt", statusCode: .notFound, contentType: nil, expecting: expectedData)
            }

            func AssertDirectAccess(directory: String, customName: Bool = false) async throws {
                let statusFileName = customName ? "NotFound.html" : "404.html"

                let expectedData = try Data(contentsOf: Constants.htmlStatusDirectoryURL.appendingPathComponent(statusFileName))
                try await TestKit.assertResponse(baseURL, path: directory + "/status/uuid.txt", statusCode: .notFound, contentType: nil, expecting: expectedData)
            }

            try await Assert404(directory: "1")
            try await Assert404(directory: "2")
            try await Assert404(directory: "3")
            try await Assert404(directory: "4", customName: true)
            try await Assert404(directory: "5", statusDirectoryURL: Constants.externalHtmlStatusDirectoryURL)
            try await Assert404(directory: "6")

            try await AssertDirectAccess(directory: "1")
            try await AssertDirectAccess(directory: "2")
            try await AssertDirectAccess(directory: "3")
            try await AssertDirectAccess(directory: "4", customName: true)
        }
    }



    // MARK: - testMixedDirectory()

    func testMixedDirectory() async throws {

        struct MixedServer : KvServer {

            static let uuid = (UUID(), UUID(), UUID())
            static let notFoundString_a = "a/404"

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvDirectory(at: Constants.htmlDirectoryURL)
                        .httpStatusDirectory(url: Constants.htmlStatusDirectoryURL)

                    KvHttpResponse.dynamic
                        .query(.required("uuid"))
                        .content { _ in .string { Self.uuid.0.uuidString } }

                    KvGroup("index.html") {
                        KvHttpResponse.static { .string { Self.uuid.1.uuidString } }
                    }
                    KvGroup("bytes") {
                        KvHttpResponse.static { .string { Self.uuid.2.uuidString } }
                    }
                    .onHttpIncident { incident in
                        guard incident.defaultStatus == .notFound else { return nil }
                        return .notFound.string { Self.notFoundString_a }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: MixedServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String, expectedPath: String) async throws {
                try await TestKit.assertResponse(baseURL, path: path, contentType: nil, expecting: Data(contentsOf: Constants.htmlDirectoryURL.appendingPathComponent(expectedPath)))
            }

            func Assert(path: String, status: KvHttpStatus) async throws {
                let expecteData = try Data(contentsOf: Constants.htmlStatusDirectoryURL.appendingPathComponent("\(status.code).html"))
                try await TestKit.assertResponse(baseURL, path: path, statusCode: status, contentType: nil, expecting: expecteData)
            }

            func Assert(path: String, status: KvHttpStatus, expected: String) async throws {
                try await TestKit.assertResponse(baseURL, path: path, statusCode: status, contentType: nil, expecting: expected)
            }

            func Assert(path: String, query: TestKit.Query? = nil, expecting: UUID) async throws {
                try await TestKit.assertResponse(baseURL, path: path, query: query, expecting: expecting.uuidString)
            }

            try await Assert(path: "", expectedPath: "index.html")
            try await Assert(path: "a/uuid.txt", expectedPath: "a/uuid.txt")

            try await Assert(path: "", query: .items([ .init(name: "uuid", value: nil) ]), expecting: MixedServer.uuid.0)
            try await Assert(path: "bytes", expecting: MixedServer.uuid.2)

            try await Assert(path: "index.html", status: .badRequest)
            try await Assert(path: "bytes/index.html", status: .notFound, expected: MixedServer.notFoundString_a)
        }
    }



    // MARK: - testIndexFiles()

    func testIndexFiles() async throws {

        struct IndexServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("1") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .indexFileNames("uuid.txt")
                    }
                    KvGroup("2") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .httpIndexFileNames("uuid.txt")
                    }
                    KvGroup("3") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .indexFileNames()
                            .httpIndexFileNames("uuid.txt")
                    }
                    KvGroup("4") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .indexFileNames("uuid.txt")
                            .httpIndexFileNames()
                    }
                    KvGroup("5") {
                        KvDirectory(at: Constants.htmlDirectoryURL)
                            .indexFileNames()
                            .httpIndexFileNames()
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: IndexServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(directory: String, expected: String) async throws {
                let expectedData = try Data(contentsOf: Constants.htmlDirectoryURL.appendingPathComponent(expected))

                try await TestKit.assertResponse(baseURL, path: directory, contentType: nil, expecting: expectedData)
            }

            try await Assert(directory: "1", expected: "index.html")
            try await Assert(directory: "2", expected: "uuid.txt")
            try await Assert(directory: "3", expected: "uuid.txt")
            try await Assert(directory: "4", expected: "uuid.txt")

            try await TestKit.assertResponse(baseURL, path: "5", statusCode: .notFound, expecting: "")
        }
    }



    // MARK: - Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup


    private typealias ContentType = KvHttpResponseProvider.ContentType


    private struct Constants {

        static let resourceDirectoryURL = Bundle.module.resourceURL!.appendingPathComponent("Resources")
        static let htmlDirectoryURL = resourceDirectoryURL.appendingPathComponent("html")
        static let htmlStatusDirectoryURL = htmlDirectoryURL.appendingPathComponent("status")
        static let externalHtmlStatusDirectoryURL = resourceDirectoryURL.appendingPathComponent("html_status")

        /// Data at /uuid.txt.
        static let data_uuid_txt = try! Data(contentsOf: htmlDirectoryURL.appendingPathComponent("uuid.txt"))

    }

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
