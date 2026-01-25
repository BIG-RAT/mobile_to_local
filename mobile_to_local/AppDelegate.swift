//
//  AppDelegate.swift
//  Mobile to Local
//
//  Copyright © 2024 jamf. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        configureTelemetryDeck()
        
        // Prevent keyboard layout switching
        setupInputSourceHandling()
    }

    private func setupInputSourceHandling() {
        // Disable automatic input source switching
        let workspace = NSWorkspace.shared
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: workspace
        )
    }
    
    @objc private func applicationActivated(_ notification: Notification) {
        // Ensure we don't force keyboard change
        if let textInputContext = NSTextInputContext.current {
            textInputContext.invalidateCharacterCoordinates()
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

