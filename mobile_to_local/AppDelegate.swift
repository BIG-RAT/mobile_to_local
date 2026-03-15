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
        
//        if !FileManager.default.fileExists(atPath: logFilePath) {
//            var secondsWaited = 0
//            FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: [.ownerAccountID:0, .groupOwnerAccountID:0, .posixPermissions:0o644])
//            while !FileManager.default.fileExists(atPath: logFilePath) {
//                if secondsWaited < 10 {
//                    secondsWaited+=1
//                } else {
//                    break
//                }
//            }
//            if FileManager.default.isWritableFile(atPath: logFilePath) {
//                print("log is writeable")
//            } else {
//                print("log is not writeable")
//            }
//            WriteToLog.shared.message(stringOfText: "New log file created.")
//        }
        
        configureTelemetryDeck()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
}
