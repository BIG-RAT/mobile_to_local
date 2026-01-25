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
        
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        configureTelemetryDeck()
    }
    
}
