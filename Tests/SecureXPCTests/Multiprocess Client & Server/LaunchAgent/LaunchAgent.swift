//
//  LaunchAgent.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-23
//

import Foundation

/// The entry point for interacting with a launch agent which runs the code in `main.swift` (and `Shared.swift`) and links against the SecureXPC module.
struct LaunchAgent {
    let machServiceName: String
    private let temporaryDirectory: URL
    private let launchdPropertyList: URL
    
    static func setUp(existingSecureXPCModule: URL?) throws -> LaunchAgent {
        let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workingDirectory,
                                                withIntermediateDirectories: false,
                                                attributes: nil)
        
        // Use the path to the SecureXPC module if one was provide, otherwise compile from source
        let moduleDefinitionDirectory: URL
        let secureXPCPath: URL
        if let existingSecureXPCModule = existingSecureXPCModule {
            moduleDefinitionDirectory = existingSecureXPCModule.deletingLastPathComponent()
            secureXPCPath = existingSecureXPCModule
        } else {
            moduleDefinitionDirectory = workingDirectory
            secureXPCPath = try compileSecureXPC(workingDirectory: workingDirectory)
        }
        
        // Don't use `.` in the name as this will be the same name for the Swift module and `.` is not a valid character
        // for a Swift module
        let executableName = "SecureXPC_Test_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let executablePath = try compileLaunchAgent(executableName: executableName,
                                                    workingDirectory: workingDirectory,
                                                    moduleDefinitionDirectory: moduleDefinitionDirectory,
                                                    secureXPCModule: secureXPCPath)
        // Use the name of the executable as the mach service name as that provides a convenient way to have a
        // dynamically generated service name which the launch agent can derive at run time
        let launchdPropertyList = try loadLaunchAgent(executablePath: executablePath, machServiceName: executableName)
        
        return LaunchAgent(machServiceName: executableName,
                           temporaryDirectory: workingDirectory,
                           launchdPropertyList: launchdPropertyList)
    }
    
    func tearDown() throws {
        try LaunchAgent.unloadLaunchAgent(plistLocation: self.launchdPropertyList)
        try FileManager.default.removeItem(at: self.temporaryDirectory)
    }
    
    // MARK: implementation
    
    /// The path to this source file
    private static func currentPath(filePath: String = #filePath) -> String { filePath }
    
    /// The path to the directory containing SecureXPC's sources
    private static func sourcesPath(filePath: String = #filePath) -> URL {
        let currentURL = URL(fileURLWithPath: filePath)
        let components = currentURL.pathComponents
        guard let testsIndex = components.lastIndex(of: "Tests"),
              components[components.index(before: testsIndex)] == "SecureXPC" else {
            fatalError("Unable to find Tests directory in SecureXPC directory")
        }
        
        return URL(fileURLWithPath: "/" + components[1..<testsIndex].joined(separator: "/") + "/Sources")
    }
    
    /// Compiles SecureXPC, returning the path to static library `libSecureXPC.a`
    ///
    /// This requires Xcode command line developer tools to be installed; this is distinct from having Xcode itself installed.
    private static func compileSecureXPC(workingDirectory: URL) throws -> URL {
        // SecureXPC's source files (which are all .swift)
        let enumerator = FileManager.default.enumerator(at: sourcesPath(), includingPropertiesForKeys: nil)!
        let swiftPaths = enumerator.compactMap { (file: Any) -> String? in
            if let file = file as? URL, file.lastPathComponent.hasSuffix(".swift") {
                return file.path
            }
    
            return nil
        }
        
        // Compile as a library
        let compileProcess = createSwiftcProcess()
        compileProcess.currentDirectoryURL = workingDirectory
        var compileArgs = ["-c"]
        compileArgs.append(contentsOf: swiftPaths )
        compileArgs.append(contentsOf: ["-parse-as-library", "-module-name", "SecureXPC"])
        compileProcess.arguments = compileArgs
        try compileProcess.run()
        compileProcess.waitUntilExit()
        
        // Create the module information and static library
        let emitProcess = createSwiftcProcess()
        emitProcess.currentDirectoryURL = workingDirectory
        var emitArgs = ["-emit-module", "-emit-library", "-static"]
        emitArgs.append(contentsOf: swiftPaths )
        emitArgs.append(contentsOf: ["-module-name", "SecureXPC"])
        emitProcess.arguments = emitArgs
        try emitProcess.run()
        emitProcess.waitUntilExit()
        
        return workingDirectory.appendingPathComponent("libSecureXPC.a")
    }
    
    private static func compileLaunchAgent(
        executableName: String,
        workingDirectory: URL,
        moduleDefinitionDirectory: URL,
        secureXPCModule: URL
    ) throws -> URL {
        // The launch agent is expected to consist of the main.swift and Shared.swift files in this folder
        let mainURL = URL(fileURLWithPath: currentPath()).deletingLastPathComponent()
                                                         .appendingPathComponent("main.swift")
        let sharedURL = URL(fileURLWithPath: currentPath()).deletingLastPathComponent()
                                                           .appendingPathComponent("Shared.swift")
        
        // Compile, but don't link
        let compileProcess = createSwiftcProcess()
        compileProcess.currentDirectoryURL = workingDirectory
        compileProcess.arguments = ["-c", mainURL.path, sharedURL.path,
                                    "-module-name", executableName,
                                    "-I", moduleDefinitionDirectory.path]
        try compileProcess.run()
        compileProcess.waitUntilExit()
        
        // Link
        let linkProcess = createSwiftcProcess()
        linkProcess.currentDirectoryURL = workingDirectory
        linkProcess.arguments = ["-emit-executable", "main.o", "Shared.o", secureXPCModule.path, "-o", executableName]
        try linkProcess.run()
        linkProcess.waitUntilExit()
        
        return workingDirectory.appendingPathComponent(executableName)
    }
    
    private static func createSwiftcProcess() -> Process {
        let process = Process()
        process.launchPath = "/usr/bin/swiftc"
        
        // See https://stackoverflow.com/questions/67595371/
        if ProcessInfo.processInfo.environment.keys.contains("OS_ACTIVITY_DT_MODE") {
            var env = ProcessInfo.processInfo.environment
            env["OS_ACTIVITY_DT_MODE"] = nil
            process.environment = env
        }
        
        return process
    }
    
    /// Uses `launchctl`  to load the launch agent, returning the URL to the property list used to load it
    private static func loadLaunchAgent(executablePath: URL, machServiceName: String) throws -> URL {
        // Create property list
        let plistLocation = executablePath.deletingLastPathComponent()
                                          .appendingPathComponent(executablePath.lastPathComponent + ".plist")
        if FileManager.default.fileExists(atPath: plistLocation.path) {
            try unloadLaunchAgent(plistLocation: plistLocation)
        }
        let plist: [String : AnyHashable] = [
            "Label" : executablePath.lastPathComponent,
            "Program" : executablePath.path,
            "MachServices": [machServiceName : true]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: plistLocation)

        // Load
        let launchctlProcess = Process()
        launchctlProcess.launchPath = "/bin/launchctl"
        launchctlProcess.arguments = ["load", plistLocation.path]
        try launchctlProcess.run()
        launchctlProcess.waitUntilExit()
        
        return plistLocation
    }
    
    /// Uses `launchctl`  to unload the launch agent
    private static func unloadLaunchAgent(plistLocation: URL) throws {
        let launchctlProcess = Process()
        launchctlProcess.launchPath = "/bin/launchctl"
        launchctlProcess.arguments = ["unload", plistLocation.path]
        try launchctlProcess.run()
        launchctlProcess.waitUntilExit()
    }
}
