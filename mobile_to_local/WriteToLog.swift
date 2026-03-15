//
//  WriteToLog.swift
//  Mobile to Local
//
//  Copyright © 2024 jamf. All rights reserved.
//

import Foundation

//let logFilePath = "/Users/Shared/mobile.to.local.log"
let logFilePath = "/private/var/log/mobile.to.local.log"
var logFileW: FileHandle? = FileHandle(forUpdatingAtPath: logFilePath)

class WriteToLog {
    
    static let shared = WriteToLog()
    
    func message(stringOfText: String) {
        let logString = "\(TimeDelegate().getCurrent()) \(stringOfText)\n"

        logFileW?.seekToEndOfFile()
        if let historyText = (logString as NSString).data(using: String.Encoding.utf8.rawValue) {
            logFileW?.write(historyText)
        }
    }
}
