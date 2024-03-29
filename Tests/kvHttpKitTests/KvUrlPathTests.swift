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
//  KvUrlPathTests.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 29.10.2023.
//

import XCTest

@testable import kvHttpKit



final class KvHttpKitTests : XCTestCase {

    // MARK: - testStandardization()

    func testStandardization() {

        func Assert(path: String..., expected: String...) {
            XCTAssertEqual(KvUrlPath(safeComponents: path).standardized, KvUrlPath(safeComponents: expected), "path: «\(path)»")
            XCTAssertEqual(KvUrlPath.Slice(safeComponents: path).standardized, KvUrlPath.Slice(safeComponents: expected), "path: «\(path)»")
        }

        Assert()
        Assert(path: "a", expected: "a")

        Assert(path: "a", ".", expected: "a")
        Assert(path: "a", ".b", expected: "a", ".b")
        Assert(path: "a", ".", "b", expected: "a", "b")
        Assert(path: ".", "a", "b", expected: "a", "b")

        Assert(path: "a", "..")
        Assert(path: "..", "a", expected: "a")
        Assert(path: "a", "..", "b", expected: "b")
        Assert(path: "a", "..", "..", "b", expected: "b")
        Assert(path: "a", "..", ".", "..", "b", expected: "b")
        Assert(path: "a", "..", "b", "..", "c", expected: "c")
        Assert(path: "a", "..", "..", "b", ".", "c", expected: "b", "c")
    }

}
