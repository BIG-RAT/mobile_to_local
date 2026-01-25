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
        targetInputSourceID = getCurrentInputSourceID()
        print("📝 Captured input source: \(targetInputSourceID ?? "none")")
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Try multiple times with increasing delays
        attemptRestoreInputSource(attempt: 0)
        configureTelemetryDeck()
    }

    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    private func attemptRestoreInputSource(attempt: Int) {
        let delays: [Double] = [0.1, 0.5, 1.0, 2.0]
        
        guard attempt < delays.count else {
            print("❌ Failed to restore input source after all attempts")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self = self, let targetID = self.targetInputSourceID else { return }
            
            let currentID = self.getCurrentInputSourceID()
            print("🔍 Attempt \(attempt + 1): Current=\(currentID ?? "none"), Target=\(targetID)")
            
            if currentID == targetID {
                print("✅ Input source already correct")
                return
            }
            
            // Try methods in order of preference
            
            // Method 1: Carbon API (fastest, but may fail with elevation)
            if self.setInputSourceViaCarbon(targetID) {
                print("✅ Restored via Carbon API")
                return
            }
            
            // Method 2: Shell script (THIS IS WHERE SOLUTION 8 IS CALLED)
            if self.setInputSourceViaShellScript(targetID) {
                print("✅ Restored via Shell Script")
                return
            }
            
            // Try again with next delay
            self.attemptRestoreInputSource(attempt: attempt + 1)
        }
    }
    
    // SOLUTION 8 - Shell Script Method
    private func setInputSourceViaShellScript(_ sourceID: String) -> Bool {
        // Get the localized name for the input source
        guard let localizedName = getInputSourceLocalizedName(sourceID) else {
            print("❌ Could not find localized name for \(sourceID)")
            return false
        }
        
        // Method A: Try setting via defaults and restart
        let script = """
        #!/bin/bash
        
        # Get current user's home directory (important when running as root)
        if [ -n "$SUDO_USER" ]; then
            USER_HOME=$(eval echo ~$SUDO_USER)
        else
            USER_HOME="$HOME"
        fi
        
        # Set the input source
        defaults write "$USER_HOME/Library/Preferences/com.apple.HIToolbox.plist" AppleSelectedInputSources -array-add "{'InputSourceKind' = 'Keyboard Layout'; 'KeyboardLayout Name' = '\(localizedName)';}"
        
        # Restart the input menu
        killall SystemUIServer 2>/dev/null
        
        exit 0
        """
        
        return executeShellScript(script)
    }
    
    private func executeShellScript(_ script: String) -> Bool {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        
        // Capture output for debugging
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
            print("❌ Shell script failed: \(error)")
            return false
        }
    }
    
    // Helper functions
    
    private func getCurrentInputSourceID() -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let sourceIDPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        return Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
    }
    
    private func getInputSourceLocalizedName(_ sourceID: String) -> String? {
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        
        for inputSource in inputSourceList {
            guard let idPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
                continue
            }
            
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            
            if id == sourceID {
                if let namePtr = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
                    let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                    return name
                }
            }
        }
        
        return nil
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
                return result == noErr
            }
        }
        
        return false
    }
}

