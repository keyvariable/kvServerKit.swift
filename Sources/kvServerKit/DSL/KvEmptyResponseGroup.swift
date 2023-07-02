//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2023 Svyatoslav Popov.
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
//  KvEmptyResponseGroup.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 03.07.2023.
//

/// It's designated to explicitely declare empty response groups.
public struct KvEmptyResponseGroup : KvResponseGroup {

    public typealias Body = KvNeverResponseGroup


    @inlinable
    public init() { }

}



// MARK: : KvResponseGroupInternalProtocol

extension KvEmptyResponseGroup : KvResponseGroupInternalProtocol {

    func insertResponses<A : KvResponseAccumulator>(to accumulator: A) {
        // Nothing to do
    }

}
