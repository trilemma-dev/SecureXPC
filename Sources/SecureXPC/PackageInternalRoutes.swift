//
//  PackageInternalRoutes.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-06
//

import Foundation

enum PackageInternalRoutes {
    
    /// A route which does nothing on the server when called.
    ///
    /// This is useful because the client can use this to know the server exists and get information about it such as its `SecCode`.
    static let noopRoute = XPCRoute.named("noop").packageInternal
}
