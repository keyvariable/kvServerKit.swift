//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2021 Svyatoslav Popov (info@keyvar.com).
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
//  KvServerTestKit.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 05.07.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit

import kvHttpKit



class KvServerTestKit {

    typealias Configuration = KvHttpChannel.Configuration



    private init() { }



    // MARK: Constants

    static let htmlDirectoryURL = Bundle.module.resourceURL!.appendingPathComponent("html", isDirectory: true)
    static let htmlStatusDirectoryURL = htmlDirectoryURL.appendingPathComponent("status", isDirectory: true)
    static let externalHtmlStatusDirectoryURL = Bundle.module.resourceURL!.appendingPathComponent("html_status", isDirectory: true)

    /// Data at /uuid.txt.
    static let data_uuid_txt = try! Data(contentsOf: htmlDirectoryURL.appendingPathComponent("uuid.txt"))



    // MARK: Configurations

    static var ssl: KvHttpChannel.Configuration.SSL {
        try! .init(pemPath: Bundle.module.url(forResource: "https", withExtension: "pem")!.path)
    }

    static var testConfigurations: [KvHttpChannel.Configuration] {
        let ssl = self.ssl

        return [
            .init(port: nextPort(), http: .v1_1(ssl: nil)),
            .init(port: nextPort(), http: .v1_1(ssl: ssl)),
            .init(port: nextPort(), http: .v2(ssl: ssl)),
        ]
    }


    static func description(of http: Configuration.HTTP) -> String {
        switch http {
        case .v1_1(.none):
            return "insecure HTTP/1.1"
        case .v1_1(.some):
            return "secure HTTP/1.1"
        case .v2:
            return "secure HTTP/2.0"
        }
    }


    private static func nextPort() -> UInt16 {

        struct Scope { static var nextPort: UInt16 = 8080 }


        defer { Scope.nextPort += 1 }

        return Scope.nextPort
    }


    /// - Returns: Insecure HTTP/1.1 on a unique port configuration.
    static func insecureHttpConfiguration() -> Configuration { return .init(port: nextPort(), http: .v1_1(ssl: nil)) }


    /// - Returns: Secure HTTP/2.0 on a unique port configuration.
    static func secureHttpConfiguration() -> Configuration { return .init(port: nextPort(), http: .v2(ssl: ssl)) }


    static func baseURL(for configuration: Configuration, host: String? = nil) -> URL {
        var components = URLComponents()

        components.scheme = {
            switch configuration.http {
            case .v1_1(.none):
                return "http"
            case .v1_1(.some), .v2:
                return "https"
            }
        }()

        assert(configuration.endpoint.address == "::1")
        components.host = host ?? {
            switch $0 {
            case "::1":
                return "localhost"
            default:
                return $0
            }
        }(configuration.endpoint.address)

        components.port = numericCast(configuration.endpoint.port)

        return components.url!
    }



    // MARK: Response Execution

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    static func queryDataIgnoringCertificate(from url: URL, in urlSession: URLSession? = nil) async throws -> (Data, URLResponse) {
        try await (urlSession ?? URLSession.init(configuration: .ephemeral)).data(from: url, delegate: IgnoringCertificateTaskDelegate())
    }


    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    static func queryDataIgnoringCertificate(for request: URLRequest, in urlSession: URLSession? = nil) async throws -> (Data, URLResponse) {
        try await (urlSession ?? URLSession.init(configuration: .ephemeral)).data(for: request, delegate: IgnoringCertificateTaskDelegate())
    }



    // MARK: Validation Auxiliaries

    /// - Parameter contentType: If `nil` then it's ignored.
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    static func assertResponse(
        urlSession: URLSession? = nil,
        _ baseURL: URL, method: String? = nil, path: String? = nil, query: Query? = nil, body: Data? = nil,
        onRequest: ((inout URLRequest) -> Void)? = nil,
        status: KvHttpStatus = .ok,
        contentType: KvHttpContentType? = .text(.plain),
        message: @escaping @autoclosure () -> String = "",
        bodyBlock: ((Data, URLRequest, () -> String) throws -> Void)? = nil
    ) async throws {
        let url: URL = {
            guard path?.isEmpty == false || query != nil else { return baseURL }

            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!

            components.path += path.map { $0.first != "/" ? "/" + $0 : $0 } ?? ""

            switch query {
            case .none:
                components.query = nil
            case .items(let items):
                components.queryItems = items
            case .raw(let value):
                components.query = value
            }

            return components.url!
        }()

        var request = URLRequest(url: url)

        if let method = method {
            request.httpMethod = method
        }
        if let body = body {
            request.httpBody = body
        }
        onRequest?(&request)

        let message = { [ "\(request)", message() ].joined(separator: ". ") }
        let (data, response) = try await queryDataIgnoringCertificate(for: request, in: urlSession)

        do {
            guard let httpResponse = response as? HTTPURLResponse
            else { return XCTFail([ "Unexpected type of response: \(type(of: response))", message() ].lazy.filter({ !$0.isEmpty }).joined(separator: ". ")) }

            XCTAssertEqual(httpResponse.statusCode, numericCast(status.rawValue), message())
            if let contentType = contentType {
                XCTAssertEqual(httpResponse.mimeType, contentType.components.mimeType, message())
            }
        }

        try bodyBlock?(data, request, message)
    }


    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    static func assertResponse(
        urlSession: URLSession? = nil,
        _ baseURL: URL, method: String? = nil, path: String? = nil, query: Query? = nil, body: Data? = nil,
        onRequest: ((inout URLRequest) -> Void)? = nil,
        status: KvHttpStatus = .ok,
        contentType: KvHttpContentType? = .text(.plain),
        expecting expected: String,
        message: @escaping @autoclosure () -> String = ""
    ) async throws {
        try await assertResponse(urlSession: urlSession, baseURL, method: method, path: path, query: query, body: body, onRequest: onRequest, status: status, contentType: contentType, message: message()) { data, request, message in
            let result = String(data: data, encoding: .utf8)
            XCTAssertEqual(result, expected, message())
        }
    }


    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    static func assertResponse(
        urlSession: URLSession? = nil,
        _ baseURL: URL, method: String? = nil, path: String? = nil, query: Query? = nil, body: Data? = nil,
        onRequest: ((inout URLRequest) -> Void)? = nil,
        status: KvHttpStatus = .ok,
        contentType: KvHttpContentType? = .application(.octetStream),
        expecting expected: Data,
        message: @escaping @autoclosure () -> String = ""
    ) async throws {
        try await assertResponse(urlSession: urlSession, baseURL, method: method, path: path, query: query, body: body, onRequest: onRequest, status: status, contentType: contentType, message: message()) { data, request, message in
            XCTAssertEqual(data, expected, message())
        }
    }


    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    static func assertResponseJSON<T : Decodable & Equatable>(
        urlSession: URLSession? = nil,
        _ baseURL: URL, method: String? = nil, path: String? = nil, query: Query? = nil, body: Data? = nil,
        onRequest: ((inout URLRequest) -> Void)? = nil,
        status: KvHttpStatus = .ok,
        contentType: KvHttpContentType? = .application(.json),
        expecting expected: T,
        message: @escaping @autoclosure () -> String = ""
    ) async throws {
        try await assertResponse(urlSession: urlSession, baseURL, method: method, path: path, query: query, body: body, onRequest: onRequest, status: status, contentType: contentType, message: message()) { data, request, message in
            let result = try JSONDecoder().decode(T.self, from: data)
            XCTAssertEqual(result, expected, message())
        }
    }



    // MARK: .Query

    enum Query : ExpressibleByStringLiteral {

        case items([URLQueryItem])
        case raw(String)


        init(stringLiteral value: StringLiteralType) {
            self = .raw(value)
        }

    }



    // MARK: .IgnoringCertificateTaskDelegate

    class IgnoringCertificateTaskDelegate : NSObject, URLSessionTaskDelegate {

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Trust the certificate even if not valid
            let urlCredential = URLCredential(trust: challenge.protectionSpace.serverTrust!)

            completionHandler(.useCredential, urlCredential)
        }

    }

}



// MARK: DSL Auxiliaries

extension KvServerTestKit {

    static func withRunningServer<S, T>(of serverType: S.Type, context contextBlock: (S) -> T, body: (T) async throws -> Void) async throws
    where S : KvServer
    {
        let context: T
        let token: KvServerToken
        do {
            let server = serverType.init()

            context = contextBlock(server)
            token = try server.start()
        }


        try token.waitWhileStarting().get()

        try await body(context)
    }


    static func withRunningServer<S>(of serverType: S.Type, body: () async throws -> Void) async throws
    where S : KvServer
    {
        try await withRunningServer(of: S.self, context: { _ in }, body: body)
    }



    // MARK: .NetworkGroup

    /// Applies given configuration to given content.
    struct NetworkGroup<Configurations, Content> : KvResponseRootGroup
    where Configurations : Sequence, Configurations.Element == KvHttpChannel.Configuration,
          Content : KvResponseRootGroup
    {

        let configurations: Configurations

        @KvResponseRootGroupBuilder
        let content: () -> Content


        init(with configurations: Configurations, @KvResponseRootGroupBuilder content: @escaping () -> Content) {
            self.configurations = configurations
            self.content = content
        }


        // MARK: : KvResponseRootGroup

        var body: some KvResponseRootGroup {
            KvGroup(httpEndpoints: configurations.lazy.map { ($0.endpoint, .init(http: $0.http, connection: $0.connection)) },
                    content: content)
        }

    }

}



// MARK: .NetworkGroup + CollectionOfOne

extension KvServerTestKit.NetworkGroup where Configurations == CollectionOfOne<KvHttpChannel.Configuration> {

    init(with configuration: KvHttpChannel.Configuration, @KvResponseRootGroupBuilder content: @escaping () -> Content) {
        self.init(with: CollectionOfOne(configuration), content: content)
    }

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
