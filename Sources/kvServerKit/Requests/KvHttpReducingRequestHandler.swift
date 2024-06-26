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
//  KvHttpReducingRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 23.06.2023.
//

import kvHttpKit



/// Processes request body fragments when they are received and collects the result until the body is completely processed.
///
/// This handler is designated to process request bodies on the fly minimizing memory usage and improving performance of large body processing.
///
/// See: ``init(bodyLengthLimit:initial:nextPartialResult:responseBlock:)``, ``init(bodyLengthLimit:into:updateAccumulatingResult:responseBlock:)``.
open class KvHttpReducingRequestHandler<PartialResult> : KvHttpRequestHandler {

    public typealias ResponseBlock = (PartialResult, KvHttpResponseProvider) -> Void



    /// See ``KvHttpRequestHandler/bodyLengthLimit`` for details.
    public let bodyLengthLimit: UInt



    @usableFromInline
    let bodyCallback: (UnsafeRawBufferPointer) throws -> Void

    @usableFromInline
    let responseBlock: (KvHttpResponseProvider) -> Void



    /// - Parameter bodyLengthLimit: see ``KvHttpRequestHandler/bodyLengthLimit`` for details. Default value is ``KvHttpRequest/Constants/bodyLengthLimit``.
    ///
    /// The partial result and received body fragments are passed to *nextPartialResult* block and partial result is replaced with value returned by *nextPartialResult*.
    /// When entire body is processed, last partial result is passed to *responseBlock*.
    ///
    /// - SeeAlso: ``init(bodyLengthLimit:into:updateAccumulatingResult:responseBlock:)``.
    @inlinable
    public init(bodyLengthLimit: UInt = KvHttpRequest.Constants.bodyLengthLimit,
                initial initialResult: PartialResult,
                nextPartialResult: @escaping (PartialResult, UnsafeRawBufferPointer) throws -> PartialResult,
                responseBlock: @escaping ResponseBlock)
    {
        var partialResult = initialResult

        self.bodyLengthLimit = bodyLengthLimit
        self.bodyCallback = { bytes in
            partialResult = try nextPartialResult(partialResult, bytes)
        }
        self.responseBlock = { completion in
            responseBlock(partialResult, completion)
        }
    }


    /// - Parameter bodyLengthLimit: see ``KvHttpRequestHandler/bodyLengthLimit`` for details. Default value is ``KvHttpRequest/Constants/bodyLengthLimit``.
    ///
    /// The mutable partial result and received body fragments are passed to *updateAccumulatingResult* block.
    /// When entire body is processed, partial result is passed to *responseBlock*.
    ///
    /// - SeeAlso: ``init(bodyLengthLimit:initial:nextPartialResult:responseBlock:)``.
    @inlinable
    public init(bodyLengthLimit: UInt = KvHttpRequest.Constants.bodyLengthLimit,
                into initialResult: PartialResult,
                updateAccumulatingResult: @escaping (inout PartialResult, UnsafeRawBufferPointer) throws -> Void,
                responseBlock: @escaping ResponseBlock)
    {
        var partialResult = initialResult

        self.bodyLengthLimit = bodyLengthLimit
        self.bodyCallback = { bytes in
            try updateAccumulatingResult(&partialResult, bytes)
        }
        self.responseBlock = { completion in
            responseBlock(partialResult, completion)
        }
    }



    // MARK: : KvHttpRequestHandler

    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) throws {
        try bodyCallback(bytes)
    }


    /// Invokes the receiver's `.responseBlock` passed with the colleted body data and returns the result.
    ///
    /// - Returns: Invocation result of the receiver's `.responseBlock` passed with the colleted body data.
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client, completion: KvHttpResponseProvider) {
        responseBlock(completion)
    }


    /// A trivial implementation of ``KvHttpRequestHandler/httpClient(_:didCatch:)-32d8h``.
    /// Override it to provide custom incident handling. 
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseContent? {
        return nil
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
