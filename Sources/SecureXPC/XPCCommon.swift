//
//  XPCCommon.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// A key into the XPC dictionary.
///
/// Instances of this type are part of the "packaging" format used by `Request` and `Response`.
typealias XPCDictionaryKey = UnsafeMutablePointer<CChar>
