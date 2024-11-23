//
//  WriteToLog.swift
//  Mobile to Local
//
//  Copyright © 2024 jamf. All rights reserved.
//

import Foundation

var logFileW = FileHandle(forUpdatingAtPath: "/var/log/mobile.to.local.log")

class WriteToLog {
    
    static let shared = WriteToLog()
    
//    var logFileW: FileHandle? = FileHandle(forUpdatingAtPath: "")

    func message(stringOfText: String) {
        let logString = "\(TimeDelegate().getCurrent()) \(stringOfText)\n"

//        logFileW = FileHandle(forUpdatingAtPath: (History.logPath! + History.logFile))

        logFileW?.seekToEndOfFile()
        if let historyText = (logString as NSString).data(using: String.Encoding.utf8.rawValue) {
            logFileW?.write(historyText)
        }
    }
}
