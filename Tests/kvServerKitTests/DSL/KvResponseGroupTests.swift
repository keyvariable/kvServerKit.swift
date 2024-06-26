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
//  KvResponseGroupTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 10.10.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit

import kvHttpKit



final class KvResponseGroupTests : XCTestCase {

    // MARK: - testMultichannelServer()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testMultichannelServer() async throws {

        /// A server provifing a simple response at the root receiving requests on several channels.
        struct MultichannelServer : KvServer {

            static let configurations = TestKit.testConfigurations

            var body: some KvResponseRootGroup {
                KvForEach(Self.configurations) { configuration in
                    NetworkGroup(with: configuration) {
                        KvHttpResponse {
                            .string { Self.greeting(for: configuration) }
                        }
                    }
                }
            }

            static func greeting(for configuration: KvHttpChannel.Configuration) -> String {
                "Hello, \(TestKit.description(of: configuration.http)) client"
            }

        }

        try await TestKit.withRunningServer(of: MultichannelServer.self) {
            for configuration in MultichannelServer.configurations {
                let baseURL = TestKit.baseURL(for: configuration)

                try await TestKit.assertResponse(baseURL, contentType: .text(.plain), expecting: MultichannelServer.greeting(for: configuration))
            }
        }

    }



    // MARK: - testResponseHierarchy()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testResponseHierarchy() async throws {

        /// A server providing non-trivial hierarchy of various responses.
        struct ResponseHierarchyServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("a") {
                        KvGroup("b") {
                            KvGroup("c") {
                                KvHttpResponse { .string { "/a/b/c" } }
                            }
                        }
                        KvGroup("б/") {
                            KvHttpResponse { .string { "/a/б" } }
                        }
                    }

                    KvGroup("/a/b/d") {
                        KvGroup(httpMethods: .post) {
                            KvHttpResponse { .string { "POST /a/b/d" } }
                        }
                    }

                    KvGroup("///b/./c/..//b///e///./f/../") {
                        KvHttpResponse { .string { "/b/./c/../b/e/./f/.." } }
                    }

                    KvHttpResponse { .string { "/" } }
                }
            }

        }

        try await TestKit.withRunningServer(of: ResponseHierarchyServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert200(path: String, method: String? = nil) async throws {
                try await TestKit.assertResponse(baseURL, method: method, path: path, contentType: .text(.plain)) { data, request, message in
                    let expectedBody = [method, request.url?.path].compactMap({ $0 }).joined(separator: " ")
                    XCTAssertEqual(String(data: data, encoding: .utf8), expectedBody, message())
                }
            }

            func Assert404(path: String, method: String? = nil) async throws {
                try await TestKit.assertResponse(baseURL, method: method, path: path, status: .notFound, contentType: .text(.plain)) { data, request, message in
                    XCTAssertTrue(data.isEmpty, message())
                }
            }

            try await Assert200(path: "/")

            do {
                let variants = [ "a", "b", "c" ]
                let okPath = variants.joined(separator: "/")

                for first in variants {
                    for second in variants {
                        for third in variants {
                            let path = "\(first)/\(second)/\(third)"

                            switch path {
                            case okPath:
                                try await Assert200(path: path)
                            default:
                                try await Assert404(path: path)
                            }
                        }
                    }
                }

                try await Assert200(path: okPath + "/")
            }

            try await Assert404(path: "a")
            try await Assert404(path: "a/b")
            try await Assert404(path: "a/b/c/d")

            try await Assert200(path: "a/б")

            try await Assert404(path: "a/в")
            try await Assert404(path: "a/с")

            try await Assert200(path: "b/./c/../b/e/./f/..")

            try await Assert404(path: "b")
            try await Assert404(path: "b/c")
            try await Assert404(path: "b/b")
            try await Assert404(path: "b/b/e/f")

            try await Assert200(path: "a/b/d", method: "POST")
            try await Assert404(path: "a/b/d", method: "GET")
            try await Assert404(path: "a/b/d", method: "PUT")
        }
    }



    // MARK: - testResponseGroupModifiers()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testResponseGroupModifiers() async throws {

        struct ModifiedResponseGroupServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            static var greeting: String { "Welcome!" }

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("a") {
                        KvGroup {
                            KvHttpResponse { .string { Self.greeting } }
                        }
                        .httpMethods(.delete)
                        .httpMethods(.get, .put)
                        .path("/c/")
                        .path("d///e")
                    }
                    .path("//b")
                }
            }

        }

        try await TestKit.withRunningServer(of: ModifiedResponseGroupServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, path: "a/b/c/d/e", expecting: ModifiedResponseGroupServer.greeting)
        }
    }



    // MARK: - testQueryOverloads()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testQueryOverloads() async throws {

        struct OverloadedQueryServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("entire") {
                        KvGroup("single") {
                            echoResponse(strict: false)
                        }
                        KvGroup("multiple") {
                            echoResponse()
                            namesResponse
                        }
                        KvGroup("ambiguous") {
                            echoResponse(strict: false)
                            namesResponse
                        }
                    }
                    KvGroup("serial") {
                        KvGroup("single") {
                            requiredStringResponse
                        }
                        KvGroup("multiple") {
                            serialResponses
                        }
                        KvGroup("with_empty") {
                            voidResponse
                            requiredStringResponse
                        }
                        KvGroup("ambiguous") {
                            voidResponse
                            optionalIntResponse
                        }
                    }
                    KvGroup("mixed") {          // Custom + empty as serial
                        KvGroup("empty") {
                            voidResponse
                            echoResponse()
                            namesResponse
                        }
                        KvGroup("serial") {     // Custom + serial
                            echoResponse()
                            serialResponses
                        }
                        KvGroup("all") {        // Custom + both serial and empty as serial
                            voidResponse
                            echoResponse()
                            serialResponses
                        }
                        KvGroup("ambiguous") {  // Ambiguous raw and structured responses.
                            echoResponse(strict: false)
                            requiredStringResponse
                        }
                    }
                }
            }

            /// Empty query response.
            private var voidResponse: some KvResponse {
                KvHttpResponse { .string { "()" } }
            }

            @KvResponseGroupBuilder
            private var serialResponses: some KvResponseGroup {
                rangeResponses
                abcAmbiguousResponses
            }

            private var optionalIntResponse: some KvResponse {
                KvHttpResponse.with
                    .query(.optional("int", of: Int.self))
                    .content { input in .string { "\(input.query.map(String.init(_:)) ?? "nil") as Int?" } }
            }

            private var requiredStringResponse: some KvResponse {
                KvHttpResponse.with
                    .query(.required("string"))
                    .content { input in .string { "\"\(input.query)\"" } }
            }

            /// Produces value of single query item if it's name is `echo`.
            private func echoResponse(strict: Bool = true) -> some KvResponse {
                let r = {
                    switch strict {
                    case false:
                        return KvHttpResponse.with
                            .queryMap { $0?.first.flatMap { $0.name == "echo" ? ($0.value ?? "") : nil } }
                    case true:
                        return KvHttpResponse.with
                            .queryFlatMap { query -> QueryResult<String?> in
                                guard let first = query?.first,
                                      query!.count == 1,
                                      first.name == "echo"
                                else { return .failure }
                                return .success(first.value ?? "")
                            }
                    }
                }()

                return r.content { input in .string { input.query.map { "\"\($0)\"" } ?? "nil" } }
            }

            /// Produces comma-separated list of query item names whether there are 2+ items.
            private var namesResponse: some KvResponse {
                KvHttpResponse.with
                    .queryFlatMap { query -> QueryResult<String> in
                        guard let query = query, query.count > 1 else { return .failure }
                        return .success(query.lazy.map({ $0.name }).joined(separator: ","))
                    }
                    .content { input in .string { input.query } }
            }

            /// Group of unambiguous responses.
            @KvResponseGroupBuilder
            private var rangeResponses: some KvResponseGroup {
                KvHttpResponse.with
                    .query(.required("from", of: Float.self))
                    .query(.optional("to", of: Float.self))
                    .content {
                        switch $0.query {
                        case (let from, .none):
                            return .string { "\(from) ..." }
                        case (let from, .some(let to)):
                            return .string { "\(from) ..< \(to)" }
                        }
                    }

                KvHttpResponse.with
                    .query(.required("to", of: Float.self))
                    .content { input in .string { "..< \(input.query)" } }

                KvHttpResponse.with
                    .query(.optional("from", of: Float.self))
                    .query(.required("through", of: Float.self))
                    .content {
                        switch $0.query {
                        case (.none, let through):
                            return .string { "... \(through)" }
                        case (.some(let from), let through):
                            return .string { "\(from) ... \(through)" }
                        }
                    }
            }

            // Group of ambiguous responses.
            @KvResponseGroupBuilder
            private var abcAmbiguousResponses: some KvResponseGroup {
                KvHttpResponse.with
                    .query(.required("a"))
                    .query(.required("b"))
                    .content {
                        let (a, b) = $0.query
                        return .string { "a: \"\(a)\", b: \"\(b)\"" }
                    }

                KvHttpResponse.with
                    .query(.required("a"))
                    .query(.required("c"))
                    .content {
                        let (a, c) = $0.query
                        return .string { "a: \"\(a)\", c: \"\(c)\"" }
                    }
            }

        }

        try await TestKit.withRunningServer(of: OverloadedQueryServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert200(path: String, query: TestKit.Query?, expectedBody: String) async throws {
                try await TestKit.assertResponse(baseURL, path: path, query: query, status: .ok, expecting: expectedBody)
            }
            func Assert400(path: String, query: TestKit.Query?) async throws {
                try await TestKit.assertResponse(baseURL, path: path, query: query, status: .badRequest, expecting: "")
            }
            func Assert404(path: String, query: TestKit.Query?) async throws {
                try await TestKit.assertResponse(baseURL, path: path, query: query, status: .notFound, expecting: "")
            }

            func AssertVoid(path: String) async throws {
                try await Assert200(path: path, query: nil, expectedBody: "()")
            }

            func AssertEcho(path: String) async throws {
                try await Assert200(path: path, query: "echo=Hello!", expectedBody: "\"Hello!\"")
                try await Assert200(path: path, query: "echo", expectedBody: "\"\"")
            }

            func AssertNames(path: String) async throws {
                try await Assert200(path: path, query: "a&a=a&b=2&cde=3&a=1", expectedBody: "a,a,b,cde,a")
            }

            func AssertOptionalInt(path: String) async throws {
                try await Assert200(path: path, query: nil, expectedBody: "nil as Int?")
                try await Assert200(path: path, query: "int=14", expectedBody: "14 as Int?")
            }

            func AssertRequiredString(path: String) async throws {
                try await Assert200(path: path, query: "string=Hello!", expectedBody: "\"Hello!\"")
                try await Assert200(path: path, query: "string", expectedBody: "\"\"")
            }

            func AssertRange(path: String) async throws {
                try await Assert200(path: path, query: "from=1.1", expectedBody: "1.1 ...")
                try await Assert200(path: path, query: "from=2.2&to=3.3", expectedBody: "2.2 ..< 3.3")
                try await Assert200(path: path, query: "from=4.4&through=5.5", expectedBody: "4.4 ... 5.5")
                try await Assert200(path: path, query: "to=6.6", expectedBody: "..< 6.6")
                try await Assert200(path: path, query: "through=7.7", expectedBody: "... 7.7")
            }

            func AssertABC(path: String) async throws {
                try await Assert200(path: path, query: "a=1&b=2", expectedBody: "a: \"1\", b: \"2\"")
                try await Assert200(path: path, query: "a=3&c=4", expectedBody: "a: \"3\", c: \"4\"")
                try await Assert404(path: path, query: "a=5")
                try await Assert404(path: path, query: "a=6&b=7&c=8")
            }

            try await AssertEcho(path: "entire/single")
            try await Assert200(path: "entire/single", query: "echo_", expectedBody: "nil")
            try await Assert200(path: "entire/single", query: nil, expectedBody: "nil")

            try await AssertEcho(path: "entire/multiple")
            try await AssertNames(path: "entire/multiple")

            try await AssertEcho(path: "entire/ambiguous")
            try await Assert200(path: "entire/ambiguous", query: "echo_", expectedBody: "nil")
            try await Assert200(path: "entire/ambiguous", query: nil, expectedBody: "nil")
            try await Assert400(path: "entire/ambiguous", query: "echo=ambiguous&int=3")
            try await Assert400(path: "entire/ambiguous", query: "a&b=2")

            try await AssertRequiredString(path: "serial/single")

            try await AssertRange(path: "serial/multiple")
            try await AssertABC(path: "serial/multiple")

            try await AssertVoid(path: "serial/with_empty")
            try await AssertRequiredString(path: "serial/with_empty")

            try await Assert400(path: "serial/ambiguous", query: nil)
            try await Assert200(path: "serial/ambiguous", query: "int=02", expectedBody: "2 as Int?")

            try await AssertVoid(path: "mixed/empty")
            try await AssertEcho(path: "mixed/empty")
            try await AssertNames(path: "mixed/empty")

            try await AssertEcho(path: "mixed/serial")
            try await AssertRange(path: "mixed/serial")
            try await AssertABC(path: "mixed/serial")

            try await AssertVoid(path: "mixed/all")
            try await AssertEcho(path: "mixed/all")
            try await AssertRange(path: "mixed/all")
            try await AssertABC(path: "mixed/all")

            try await AssertEcho(path: "mixed/ambiguous")
            try await Assert400(path: "mixed/ambiguous", query: "string=Ambiguous!")
        }
    }



    // MARK: - testCascadeNetworkModifiers()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testCascadeNetworkModifiers() async throws {

        struct CascadeNetworkModifierServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            static let greeting = "cascade"

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    httpsServer
                }
            }

            private var httpsServer: some KvResponseRootGroup {
                NetworkGroup(with: TestKit.secureHttpConfiguration()) {
                    KvHttpResponse { .string { Self.greeting } }
                }
            }

        }

        try await TestKit.withRunningServer(of: CascadeNetworkModifierServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, expecting: CascadeNetworkModifierServer.greeting)
        }
    }



    // MARK: - testCascadeHttpMethodModifiers()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testCascadeHttpMethodModifiers() async throws {

        struct CascadeHttpMethodModifierServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse { .string { "/" } }

                    KvGroup("a") {
                        KvHttpResponse { .string { "/a" } }

                        KvGroup("b") {
                            KvHttpResponse { .string { "/a/b" } }

                            KvGroup("c") {
                                KvHttpResponse { .string { "/a/b/c" } }
                            }
                            .httpMethods(.post)
                        }
                        .httpMethods(.post, .put)

                        KvGroup("d") {
                            KvHttpResponse { .string { "/a/d" } }
                        }
                        .httpMethods(.put)
                    }
                    .httpMethods(.get, .post)
                }
            }

        }

        try await TestKit.withRunningServer(of: CascadeHttpMethodModifierServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, method: "GET" , path: nil, expecting: "/")
            try await TestKit.assertResponse(baseURL, method: "POST", path: nil, expecting: "/")
            try await TestKit.assertResponse(baseURL, method: "PUT" , path: nil, expecting: "/")

            try await TestKit.assertResponse(baseURL, method: "GET" , path: "a", expecting: "/a")
            try await TestKit.assertResponse(baseURL, method: "POST", path: "a", expecting: "/a")
            try await TestKit.assertResponse(baseURL, method: "PUT" , path: "a", status: .notFound, expecting: "")

            try await TestKit.assertResponse(baseURL, method: "GET" , path: "a/b", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, method: "POST", path: "a/b", expecting: "/a/b")
            try await TestKit.assertResponse(baseURL, method: "PUT" , path: "a/b", status: .notFound, expecting: "")

            try await TestKit.assertResponse(baseURL, method: "GET" , path: "a/b/c", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, method: "POST", path: "a/b/c", expecting: "/a/b/c")
            try await TestKit.assertResponse(baseURL, method: "PUT" , path: "a/b/c", status: .notFound, expecting: "")

            try await TestKit.assertResponse(baseURL, method: "GET" , path: "a/d", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, method: "POST", path: "a/d", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, method: "PUT" , path: "a/d", status: .notFound, expecting: "")
        }
    }



    // MARK: - testCascadeUserModifiers()

    // TODO: Enable when user filters will be actually applied.
#if false
    func testCascadeUserModifiers() async throws {

        struct CascadeUserModifierServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse { .string { "/" } }

                    KvGroup("a") {
                        KvHttpResponse { .string { "/a" } }

                        KvGroup("b") {
                            KvHttpResponse { .string { "/a/b" } }

                            KvGroup("c") {
                                KvHttpResponse { .string { "/a/b/c" } }
                            }
                            .users("Y")
                        }
                        .users("Y", "Z")

                        KvGroup("d") {
                            KvHttpResponse { .string { "/a/d" } }
                        }
                        .users("Z")
                    }
                    .users("X", "Y")
                }
            }

        }

        try await TestKit.withRunningServer(of: CascadeUserModifierServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(user: String?, path: String?, expecting: String?) async throws {
                var baseURL = baseURL
                if let user = user {
                    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
                    components.user = user
                    baseURL = components.url!
                }
                try await TestKit.assertResponse(baseURL, path: path, status: expecting != nil ? .ok : .notFound, expecting: expecting ?? "")
            }

            try await Assert(user: nil, path: nil, expecting: "/")
            try await Assert(user: "X", path: nil, expecting: "/")
            try await Assert(user: "Y", path: nil, expecting: "/")
            try await Assert(user: "Z", path: nil, expecting: "/")

            try await Assert(user: nil, path: "a", expecting: nil)
            try await Assert(user: "X", path: "a", expecting: "/a")
            try await Assert(user: "Y", path: "a", expecting: "/a")
            try await Assert(user: "Z", path: "a", expecting: nil)

            try await Assert(user: nil, path: "a/b", expecting: nil)
            try await Assert(user: "X", path: "a/b", expecting: nil)
            try await Assert(user: "Y", path: "a/b", expecting: "/a/b")
            try await Assert(user: "Z", path: "a/b", expecting: nil)

            try await Assert(user: nil, path: "a/b/c", expecting: nil)
            try await Assert(user: "X", path: "a/b/c", expecting: nil)
            try await Assert(user: "Y", path: "a/b/c", expecting: "/a/b/c")
            try await Assert(user: "Z", path: "a/b/c", expecting: nil)

            try await Assert(user: nil, path: "a/d", expecting: nil)
            try await Assert(user: "X", path: "a/d", expecting: nil)
            try await Assert(user: "Y", path: "a/d", expecting: nil)
            try await Assert(user: "Z", path: "a/d", expecting: nil)
        }
    }
#endif



    // MARK: - testOnHttpIncident()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testOnHttpIncident() async throws {

        struct IncidentServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup {
                        KvGroup("a") {
                            greetingResponse
                            KvGroup {
                                KvHttpResponse.with
                                    .query(.void("count"))
                                    .requestBody(.data.bodyLengthLimit(Self.bodyLimit))
                                    .content { input in .string { "\(input.requestBody?.count ?? 0)" } }
                                    .onIncident { incident, _ in
                                        guard incident.defaultStatus == .contentTooLarge else { return nil }
                                        return .contentTooLarge.string { Self.contentTooLargeString }
                                    }
                            }
                            .httpMethods(.post)

                            KvGroup("b") {
                                greetingResponse
                            }
                        }
                        .onHttpIncident { incident, _ in
                            guard incident.defaultStatus == .notFound else { return nil }
                            return .notFound.string { Self.notFoundString2 }
                        }

                        KvGroup("c") {
                            KvGroup("c") {
                                greetingResponse
                            }
                        }
                    }
                    .onHttpIncident { incident, _ in
                        guard incident.defaultStatus == .notFound else { return nil }
                        return .notFound.string { Self.notFoundString1 }
                    }

                    KvGroup("d") {
                        greetingResponse
                    }
                    .onHttpIncident { incident, _ in
                        guard incident.defaultStatus == .notFound else { return nil }
                        return .notFound.string { Self.notFoundString3 }
                    }
                }
            }

            private var greetingResponse: some KvResponse {
                KvHttpResponse { .string { Self.greetingString } }
            }

            static let bodyLimit: UInt = 16

            static func countResponseString(_ count: Int?) -> String { count.map(String.init(_:)) ?? "nil" }

            static let greetingString = "Hello!"
            static let notFoundStringGlobal = "/"
            static let notFoundString1 = "/"
            static let notFoundString2 = "/a/"
            static let notFoundString3 = "/d/"
            static let contentTooLargeString = "Body limit is \(bodyLimit) bytes."

        }

        try await TestKit.withRunningServer(of: IncidentServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert404(path: String, response: String) async throws {
                try await TestKit.assertResponse(
                    baseURL, path: path,
                    status: .notFound, contentType: .text(.plain), expecting: response
                )
            }

            func Assert413(path: String, contentLength: UInt, response: String) async throws {
                try await TestKit.assertResponse(
                    baseURL, method: "POST", path: path, query: .raw("count"), body: contentLength > 0 ? Data(count: numericCast(contentLength)) : nil,
                    status: .contentTooLarge, contentType: .text(.plain), expecting: response
                )
            }

            try await Assert404(path: "/", response: IncidentServer.notFoundString1)

            try await Assert404(path: "/a/b/x", response: IncidentServer.notFoundString2)
            try await Assert404(path: "/a/x", response: IncidentServer.notFoundString2)

            try await Assert404(path: "/c", response: IncidentServer.notFoundString1)
            try await Assert404(path: "/c/c/x", response: IncidentServer.notFoundString1)
            try await Assert404(path: "/c/x", response: IncidentServer.notFoundString1)

            try await Assert404(path: "/d/x", response: IncidentServer.notFoundString3)

            try await Assert404(path: "/x", response: IncidentServer.notFoundString1)
            try await Assert404(path: "/x/a", response: IncidentServer.notFoundString1)
            try await Assert404(path: "/x/a/x", response: IncidentServer.notFoundString1)
            try await Assert404(path: "/x/c/x", response: IncidentServer.notFoundString1)

            try await Assert413(path: "/a", contentLength: IncidentServer.bodyLimit + 1, response: IncidentServer.contentTooLargeString)
        }
    }



    // MARK: - testUrlDeclarations()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testUrlDeclarations() async throws {

        struct UrlDeclarationServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("directory") {
                        TestKit.htmlDirectoryURL
                    }
                    KvGroup("file") {
                        Bundle.module.url(forResource: "sample", withExtension: "txt")
                    }
                    KvGroup("files") {
                        Bundle.module.urls(forResourcesWithExtension: "html", subdirectory: "html_status")
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: UrlDeclarationServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(section: String, path: String, expectedPath: String) async throws {
                let url = TestKit.htmlDirectoryURL.appendingPathComponent(expectedPath)
                let expected = try Data(contentsOf: url)

                try await TestKit.assertResponse(baseURL, path: section + "/" + path, contentType: nil, expecting: expected)
            }

            func Assert(section: String, path: String, status: KvHttpStatus) async throws {
                let url = TestKit.htmlStatusDirectoryURL.appendingPathComponent("\(status.rawValue).html")
                let expected = try Data(contentsOf: url)

                try await TestKit.assertResponse(baseURL, path: section + "/" + path, status: status, contentType: nil, expecting: expected)
            }

            try await Assert(section: "directory", path: "", expectedPath: "index.html")
            try await Assert(section: "directory", path: "index.html", expectedPath: "index.html")
            try await Assert(section: "directory", path: "uuid.txt", expectedPath: "uuid.txt")
            try await Assert(section: "directory", path: "a", expectedPath: "a/index")
            try await Assert(section: "directory", path: "a/index", expectedPath: "a/index")

            try await Assert(section: "directory", path: "sample.txt", status: .notFound)
            try await Assert(section: "directory", path: ".uuid.txt", status: .notFound)
            try await Assert(section: "directory", path: "a/index.html", status: .notFound)

            try await Assert(section: "file", path: "sample.txt", expectedPath: "../sample.txt")

            try await Assert(section: "files", path: "400.html", expectedPath: "../html_status/400.html")
            try await Assert(section: "files", path: "404.html", expectedPath: "../html_status/404.html")
        }
    }



    // MARK: Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
