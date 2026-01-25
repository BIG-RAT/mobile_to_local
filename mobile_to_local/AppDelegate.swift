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

    private var userInputSourceID: String?
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Capture the ACTUAL user's input source
        // This happens before macOS security policies interfere
        userInputSourceID = captureUserInputSource()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Restore after a brief delay to ensure system is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.restoreUserInputSource()
        }
        
        // Also restore when window becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        configureTelemetryDeck()
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
            restoreUserInputSource()
        }
        
    private func captureUserInputSource() -> String? {
        // Try multiple methods to get the REAL user's input source
        
        // Method 1: From current process
        if let sourceID = getCurrentInputSourceID() {
            return sourceID
        }
        
        // Method 2: From saved defaults (if previously saved)
        if let saved = UserDefaults.standard.string(forKey: "LastKnownInputSource") {
            return saved
        }
        
        // Method 3: From environment or launch arguments
        if let fromArgs = CommandLine.arguments.first(where: { $0.hasPrefix("--input-source=") }) {
            return String(fromArgs.dropFirst("--input-source=".count))
        }
        
        return nil
    }
    
    private func getCurrentInputSourceID() -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let sourceIDPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
        
        // Save for future reference
        UserDefaults.standard.set(sourceID, forKey: "LastKnownInputSource")
        
        return sourceID
    }
    
    private func restoreUserInputSource() {
        guard let targetSourceID = userInputSourceID else {
            return
        }
        
        // Don't change if we're already on the correct layout
        if getCurrentInputSourceID() == targetSourceID {
            return
        }
        
        setInputSource(targetSourceID)
    }
    
    private func setInputSource(_ sourceID: String) {
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        
        for inputSource in inputSourceList {
            guard let idPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
                continue
            }
            
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            
            if id == sourceID {
                let result = TISSelectInputSource(inputSource)
                if result == noErr {
                    print("✅ Successfully restored input source: \(sourceID)")
                } else {
                    print("⚠️ Failed to restore input source: \(result)")
                }
                break
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

