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
//  KvHttpRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 30.05.2023.
//

import kvHttpKit



/// Protocol for request handlers. See provided common request handlers.
public protocol KvHttpRequestHandler : AnyObject {

    /// Maximum acceptable number of bytes in request body. Zero means that request must have no body or empty body.
    var bodyLengthLimit: UInt { get }


    /// It's invoked when server receives bytes from the client related with the request.
    /// This method can be invoked multiple times for each received part of the request body.
    /// When all the request body bytes are passed to request handler, ``httpClientDidReceiveEnd(_:completion:)`` method is invoked.
    ///
    /// - Tip: Thrown errors cause ``KvHttpChannel/RequestIncident/requestProcessingError(_:)`` incident.
    func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) throws

    /// It's invoked when the request is completely received (including it's body bytes) and is ready to be handled.
    ///
    /// - Parameter completion: A callable instance to be invoked with the result of prequest processing.
    ///
    /// - Important: Given *completion* is also a token.
    ///     If it's released before invocation then ``KvHttpChannel/RequestIncident/noResponse`` incident is triggered.
    ///
    /// - Tip: If *completion* is invoked with an error then ``KvHttpChannel/RequestIncident/requestProcessingError(_:)`` incident is triggered.
    func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client, completion: KvHttpResponseProvider)

    /// - Returns:  Optional custom response for an incident related to the request on a client.
    ///             If `nil` is returned then ``KvHttpIncident/defaultStatus`` is submitted to client.
    ///
    /// Use ``KvHttpIncident/defaultStatus`` to compose responses with default status codes for incidents.
    /// Also you can return custom responses depending on default status.
    ///
    /// - Note: Server will close connection to the client just after the response will be submitted.
    ///
    /// - Important: Provided response should provide a valid optional body. If error occurs then server omits body.
    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseContent?

    /// - Note: The client will continue to process requests.
    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error)
    
}
