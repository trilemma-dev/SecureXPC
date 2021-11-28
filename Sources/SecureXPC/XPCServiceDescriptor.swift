//
//  XPCServiceDescriptor.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

internal enum XPCServiceDescriptor {
    case anonymous
    case xpcService(name: String)
    case machService(name: String)
}
