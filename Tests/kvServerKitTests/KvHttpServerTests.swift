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
//  KvHttpServerTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 01.05.2020.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit

import kvHttpKit



final class KvHttpServerTests : XCTestCase {

    // MARK: - testHttpServer()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testHttpServer() async throws {
        try await onImperativeHttpServer(with: KvServerTestKit.testConfigurations) { channel in
            let configuration = channel.configuration
            let baseURL = KvServerTestKit.baseURL(for: configuration)
            let httpDescription = KvServerTestKit.description(of: configuration.http)

            // ##  Root
            for url in [ baseURL, URL(string: "/", relativeTo: baseURL)! ] {
                try await KvServerTestKit.assertResponse(
                    url,
                    contentType: .text(.plain), expecting: ImperativeHttpServer.Constants.Greeting.content, message: httpDescription
                )
            }

            // ##  404 at unexpected path
            try await KvServerTestKit.assertResponse(
                baseURL, path: ImperativeHttpServer.Constants.NotFound.path,
                status: .notFound,
                contentType: .text(.plain), expecting: ImperativeHttpServer.Constants.NotFound.content, message: httpDescription
            )

            // ##  Echo
            do {
                let body = Data((0 ..< Int.random(in: (1 << 16)...numericCast(ImperativeHttpServer.Constants.Echo.bodyLimit)))
                    .lazy.map { _ in UInt8.random(in: .min ... .max) })

                try await KvServerTestKit.assertResponse(
                    baseURL, method: "POST", path: ImperativeHttpServer.Constants.Echo.path, body: body,
                    contentType: .application(.octetStream), expecting: body, message: httpDescription
                )
            }

            // ##  Generator
            do {
                typealias T = ImperativeHttpServer.NumberGeneratorStream.Element

                let range: ClosedRange<T> = T.random(in: -100_000 ... -10_000) ... T.random(in: 10_000 ... 100_000)
                let queryItems = [ URLQueryItem(name: ImperativeHttpServer.Constants.Generator.argFrom, value: String(range.lowerBound)),
                                   URLQueryItem(name: ImperativeHttpServer.Constants.Generator.argThrough, value: String(range.upperBound)), ]

                try await KvServerTestKit.assertResponse(
                    baseURL, path: ImperativeHttpServer.Constants.Generator.path,
                    query: .items(queryItems),
                    contentType: nil, message: httpDescription
                ) { data, request, message in
                    data.withUnsafeBytes { buffer in
                        XCTAssertTrue(buffer.assumingMemoryBound(to: T.self).elementsEqual(range), message())
                    }
                }
            }
        }
    }



    // MARK: - testByteLimitExceededIncident()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testByteLimitExceededIncident() async throws {
        try await onImperativeHttpServer(with: KvServerTestKit.secureHttpConfiguration(), { channel in
            let baseURL = KvServerTestKit.baseURL(for: channel.configuration)

            // ##  Echo with exceeding body.
            try await KvServerTestKit.assertResponse(
                baseURL, method: "POST", path: ImperativeHttpServer.Constants.Echo.path,
                body: .init(count: numericCast(ImperativeHttpServer.Constants.Echo.bodyLimit + 1)),
                status: .contentTooLarge,
                contentType: .text(.plain), expecting: ImperativeHttpServer.Constants.Echo.payloadTooLargeContent
            )
        })
    }



    // MARK: - testHeadMethod()

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testHeadMethod() async throws {
        try await onImperativeHttpServer(with: KvServerTestKit.secureHttpConfiguration(), { channel in
            let baseURL = KvServerTestKit.baseURL(for: channel.configuration)

            // ##  Root
            do {
                let urlSession = URLSession(configuration: .ephemeral)

                try await KvServerTestKit.assertResponse(
                    urlSession: urlSession,
                    baseURL, method: "HEAD",
                    contentType: .text(.plain), expecting: ""
                )

                try await KvServerTestKit.assertResponse(
                    urlSession: urlSession,
                    baseURL,
                    contentType: .text(.plain), expecting: ImperativeHttpServer.Constants.Greeting.content
                )
            }

            // ##  Echo
            do {
                let body = Data((0 ..< Int.random(in: (1 << 8)...(1 << 10)))
                    .lazy.map { _ in UInt8.random(in: .min ... .max) })

                let urlSession = URLSession(configuration: .ephemeral)

                try await KvServerTestKit.assertResponse(
                    urlSession: urlSession,
                    baseURL, method: "HEAD", path: ImperativeHttpServer.Constants.Echo.path, body: body,
                    contentType: .application(.octetStream), expecting: ""
                )

                try await KvServerTestKit.assertResponse(
                    urlSession: urlSession,
                    baseURL, method: "POST", path: ImperativeHttpServer.Constants.Echo.path, body: body,
                    contentType: .application(.octetStream), expecting: body
                )
            }

            // ##  Echo with exceeding body.
            do {
                let data = Data(count: numericCast(ImperativeHttpServer.Constants.Echo.bodyLimit + 1))

                try await KvServerTestKit.assertResponse(
                    baseURL, method: "HEAD", path: ImperativeHttpServer.Constants.Echo.path,
                    body: data,
                    status: .contentTooLarge,
                    contentType: .text(.plain), expecting: ""
                )

                try await KvServerTestKit.assertResponse(
                    baseURL, method: "POST", path: ImperativeHttpServer.Constants.Echo.path,
                    body: data,
                    status: .contentTooLarge,
                    contentType: .text(.plain), expecting: ImperativeHttpServer.Constants.Echo.payloadTooLargeContent
                )
            }
        })
    }

}



// MARK: - Auxiliaries

extension KvHttpServerTests {

    private func onImperativeHttpServer(with configuration: KvHttpChannel.Configuration, _ callback: (KvHttpChannel) async throws -> Void) async throws {
        try await onImperativeHttpServer(with: CollectionOfOne(configuration), callback)
    }


    private func onImperativeHttpServer<C>(with configurations: C, _ callback: (KvHttpChannel) async throws -> Void) async throws
    where C : Sequence, C.Element == KvHttpChannel.Configuration
    {
        let server = ImperativeHttpServer(with: configurations)

        try server.start()
        defer {
            server.stop()
            try! server.waitUntilStopped().get()
        }

        // `channel.waitWhileStarting()` below can fail due to channels may be is in *stopped* state until server is completely started.
        // So we wait while server is starting and then wait while channels are starting.
        try server.waitWhileStarting().get()

        try await server.forEachChannel { channel in
            // Waiting for the channel.
            try channel.waitWhileStarting().get()
            XCTAssertEqual(channel.state, .running)

            try await callback(channel)
        }
    }



    // MARK: .ImperativeHttpServer

    private class ImperativeHttpServer : KvHttpServerDelegate, KvHttpChannelDelegate, KvHttpClientDelegate {

        init<C>(with configurations: C) where C : Sequence, C.Element == KvHttpChannel.Configuration {
            httpServer.delegate = self

            configurations.forEach {
                let channel = KvHttpChannel(with: $0)

                channel.delegate = self

                httpServer.addChannel(channel)
            }
        }


        convenience init(with configuration: KvHttpChannel.Configuration) { self.init(with: CollectionOfOne(configuration)) }


        private let httpServer: KvHttpServer = .init()


        // MARK: .Constats

        struct Constants {

            struct Greeting {

                static let path = "/"
                static var content: String { "Hello! It's a test server on kvServerKit framework" }

            }

            struct Echo {

                static let path = "/echo"
                static let bodyLimit: UInt = 256 << 10 // 256 KiB == (1 << 18) B

                static var payloadTooLargeContent: String { "Payload is too large" }

            }

            struct Generator {

                static let path = "/generator"
                static let argFrom = "from"
                static let argThrough = "through"

            }

            /// Constants related with 404 response on unexpected resources.
            struct NotFound {

                static let path = "/unexpected/path"
                static var content: String { "Not found (404)" }

            }

        }


        // MARK: Managing Life-cycle

        func start() throws {
            try httpServer.start()
        }


        func stop() {
            httpServer.stop()
        }


        @discardableResult
        func waitWhileStarting() -> Result<Void, Error> { httpServer.waitWhileStarting() }


        @discardableResult
        func waitUntilStopped() -> Result<Void, Error> { httpServer.waitUntilStopped() }


        // MARK: Operations

        var endpointURLs: [URL]? { httpServer.endpointURLs }


        func forEachChannel(_ body: (KvHttpChannel) async throws -> Void) async rethrows {
            for channel in httpServer.channelIDs.lazy.map({ self.httpServer.channel(with: $0)! }) {
                try await body(channel)
            }
        }


        // MARK: : KvHttpServerDelegate

        func httpServerDidStart(_ httpServer: KvHttpServer) { }


        func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>) {
            switch result {
            case .failure(let error):
                XCTFail("Simple test server did stop with error: \(error)")
            case .success:
                break
            }
        }


        func httpServer(_ httpServer: KvHttpServer, didCatch error: Error) {
            XCTFail("Simple test server did catch error: \(error)")
        }


        // MARK: : KvHttpChannelDelegate

        func httpChannelDidStart(_ httpChannel: KvHttpChannel) { }


        func httpChannel(_ httpChannel: KvHttpChannel, didStopWith result: Result<Void, Error>) {
            switch result {
            case .failure(let error):
                XCTFail("Simple test server did stop channel with error: \(error)")
            case .success:
                break
            }
        }


        func httpChannel(_ httpChannel: KvHttpChannel, didCatch error: Error) {
            XCTFail("Simple test server did catch error on channel \(httpChannel): \(error)")
        }


        func httpChannel(_ httpChannel: KvHttpChannel, didStartClient httpClient: KvHttpChannel.Client) {
            httpClient.delegate = self
        }


        func httpChannel(_ httpChannel: KvHttpChannel, didStopClient httpClient: KvHttpChannel.Client, with result: Result<Void, Error>) {
            switch result {
            case .failure(let error):
                XCTFail("Simple test server did stop client with error: \(error)")
            case .success:
                break
            }
        }


        // MARK: : KvHttpClientDelegate

        func httpClient(_ httpClient: KvHttpChannel.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler? {
            let uri = requestHead.uri

            guard let urlComponents = URLComponents(string: uri) else {
                XCTFail("Failed to parse request URI: \(uri)")
                return KvHttpRequest.HeadOnlyHandler(response: .badRequest)
            }

            switch urlComponents.path {
            case Constants.Greeting.path:
                return KvHttpRequest.HeadOnlyHandler(response: .string { Constants.Greeting.content })

            case Constants.Echo.path:
                return EchoRequestHandler()

            case Constants.Generator.path:
                guard let bodyStream = NumberGeneratorStream(queryItems: urlComponents.queryItems)
                else { return nil }

                return KvHttpRequest.HeadOnlyHandler(response: .bodyCallback { buffer in
                    return .success(bodyStream.read(buffer))
                })

            default:
                break
            }

            return KvHttpRequest.HeadOnlyHandler(response: .notFound.string { Constants.NotFound.content })
        }


        func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.ClientIncident) -> KvHttpResponseContent? {
            return nil
        }


        func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
            XCTFail("Simple test server did catch client error: \(error)")
        }


        // MARK: .EchoRequestHandler

        fileprivate class EchoRequestHandler : KvHttpRequest.CollectingBodyHandler {

            init() {
                super.init(bodyLengthLimit: Constants.Echo.bodyLimit) { body, completion in
                    guard let body = body else { return }

                    completion(
                        .binary { body }
                            .contentLength(body.count)
                    )
                }
            }


            // MARK: : KvHttpRequestHandler

            override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseContent? {
                switch incident {
                case .byteLimitExceeded:
                    return .status(incident.defaultStatus)
                        .string { Constants.Echo.payloadTooLargeContent }
                default:
                    return super.httpClient(httpClient, didCatch: incident)
                }
            }

        }


        // MARK: .NumberGeneratorStream

        /// Input stream returning memory of array of consequent 32-bit signed numbers.
        fileprivate class NumberGeneratorStream {

            typealias Element = Int32


            init(on range: ClosedRange<Element>) {
                next = range.lowerBound
                count = 1 + UInt32(bitPattern: range.upperBound) &- UInt32(bitPattern: range.lowerBound)

                buffer = .allocate(capacity: 1024)

                slice = buffer.withMemoryRebound(to: UInt8.self, {
                    return .init(start: $0.baseAddress, count: 0)
                })
                cursor = slice.startIndex
            }


            convenience init?(queryItems: [URLQueryItem]?) {

                func TakeValue(from queryItem: URLQueryItem, to dest: inout Element?) {
                    guard let value = queryItem.value.map(Element.init(_:)) else { return }

                    dest = value
                }


                guard let queryItems = queryItems else { return nil }

                var bounds: (from: Element?, through: Element?) = (nil, nil)

                for queryItem in queryItems {
                    switch queryItem.name {
                    case Constants.Generator.argFrom:
                        TakeValue(from: queryItem, to: &bounds.from)
                    case Constants.Generator.argThrough:
                        TakeValue(from: queryItem, to: &bounds.through)
                    default:
                        // Unexpected query items are prohibited
                        return nil
                    }
                }

                guard let from = bounds.from,
                      let through = bounds.through,
                      from <= through
                else { return nil }

                self.init(on: from...through)
            }


            deinit {
                buffer.deallocate()
            }


            /// Next value to write in buffer.
            private var next: Element
            /// Number of values to write in buffer from *next*.
            private var count: UInt32

            private var buffer: UnsafeMutableBufferPointer<Element>

            private var slice: UnsafeMutableBufferPointer<UInt8>
            private var cursor: UnsafeMutableBufferPointer<UInt8>.Index


            // MARK: Operations

            var hasBytesAvailable: Bool { cursor < slice.endIndex || count > 0 }


            func read(_ buffer: UnsafeMutableRawBufferPointer) -> Int {
                updateBufferIfNeeded()

                guard hasBytesAvailable else { return 0 }

                let bytesToCopy = min(buffer.count, slice.endIndex - cursor)

                buffer.copyMemory(from: .init(start: slice.baseAddress, count: bytesToCopy))
                cursor += bytesToCopy

                return bytesToCopy
            }


            private func updateBufferIfNeeded() {
                guard cursor >= slice.endIndex, count > 0 else { return }

                let rangeCount: Int = min(numericCast(count), buffer.count)
                let range = next ..< (next + numericCast(rangeCount))

                _ = buffer.update(fromContentsOf: range)

                slice = .init(start: slice.baseAddress, count: rangeCount * MemoryLayout<Element>.size)

                cursor = slice.startIndex
                next = range.upperBound
                count -= numericCast(rangeCount)
            }

        }

    }

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
