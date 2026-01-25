//
//  AppDelegate.swift
//  Mobile to Local
//
//  Copyright © 2024 jamf. All rights reserved.
//

import Cocoa
import Carbon.HIToolbox

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var targetInputSourceID: String?

    func applicationWillFinishLaunching(_ notification: Notification) {
        targetInputSourceID = getKeyboardFromArguments()
        
        if targetInputSourceID == nil {
            // Fallback: try to get from current (but this will be US)
            targetInputSourceID = getCurrentInputSourceID()
        }
        
        print("🎯 Target keyboard: \(targetInputSourceID ?? "none")")
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // List all available keyboards for debugging
        listAllInputSources()
        
        // Restore the correct keyboard
        if let targetID = targetInputSourceID {
            attemptRestoreInputSource(targetID: targetID, attempt: 0)
        }
        
        configureTelemetryDeck()
    }

    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    private func getKeyboardFromArguments() -> String? {
        let arguments = CommandLine.arguments
        
        // Look for --keyboard argument
        if let index = arguments.firstIndex(of: "--keyboard"),
           index + 1 < arguments.count {
            let keyboard = arguments[index + 1]
            print("✅ Keyboard from arguments: \(keyboard)")
            return keyboard
        }
        
        return nil
    }

    private func attemptRestoreInputSource(targetID: String, attempt: Int) {
        let delays: [Double] = [0.2, 0.5, 1.0, 2.0, 3.0]
        
        guard attempt < delays.count else {
            print("❌ Failed to restore keyboard after all attempts")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self = self else { return }
            
            let currentID = self.getCurrentInputSourceID()
            print("🔍 Attempt \(attempt + 1): Current=\(currentID ?? "none"), Target=\(targetID)")
            
            if currentID == targetID {
                print("✅ Keyboard already correct!")
                return
            }
            
            // Try to set it
            if self.setInputSourceViaCarbon(targetID) {
                print("✅ Restored via Carbon API")
                return
            }
            
            if self.setInputSourceViaDefaults(targetID) {
                print("✅ Restored via defaults command")
                
                // Verify after a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let newID = self.getCurrentInputSourceID()
                    print("🔍 Verification: \(newID ?? "none")")
                }
                return
            }
            
            // Try again
            self.attemptRestoreInputSource(targetID: targetID, attempt: attempt + 1)
        }
    }
    
    
    private func setInputSourceViaDefaults(_ sourceID: String) -> Bool {
        // Determine the actual user (not root)
        let actualUser = ProcessInfo.processInfo.environment["SUDO_USER"] ?? NSUserName()
        let userHome = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(actualUser)"
        
        print("🏠 User home: \(userHome)")
        print("👤 User: \(actualUser)")
        
        // Use defaults command to modify the plist
        let script = """
        #!/bin/bash
        
        # Run as the actual user, not root
        sudo -u "\(actualUser)" defaults write com.apple.HIToolbox AppleSelectedInputSources -array-add '<dict><key>InputSourceKind</key><string>Keyboard Layout</string><key>KeyboardLayout ID</key><integer>0</integer><key>KeyboardLayout Name</key><string>\(sourceID)</string></dict>'
        
        # Kill and restart the input menu
        sudo -u "\(actualUser)" killall SystemUIServer 2>/dev/null || true
        
        exit 0
        """
        
        return executeShellScript(script)
    }
    
    private func executeShellScript(_ script: String) -> Bool {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📄 Script output: \(output)")
            }
            
            return task.terminationStatus == 0
        } catch {
            print("❌ Script failed: \(error)")
            return false
        }
    }
    
    private func getCurrentInputSourceID() -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let sourceIDPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        return Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
    }
    
    private func setInputSourceViaCarbon(_ sourceID: String) -> Bool {
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        
        for inputSource in inputSourceList {
            guard let idPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
                continue
            }
            
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            
            if id == sourceID {
                let result = TISSelectInputSource(inputSource)
                print("🔧 TISSelectInputSource result: \(result)")
                return result == noErr
            }
        }
        
        print("❌ Could not find input source: \(sourceID)")
        return false
    }
    
    private func listAllInputSources() {
        print("\n📋 Available Input Sources:")
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        
        for inputSource in inputSourceList {
            if let idPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID),
               let namePtr = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                print("  - \(name) (\(id))")
            }
        }
        print("")
    }
}

