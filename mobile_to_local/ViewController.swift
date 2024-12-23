//
//  ViewController.swift
//  Mobile to Local
//
//  Copyright © 2024 jamf. All rights reserved.
//

import AppKit
import Cocoa
import Foundation
import OpenDirectory
import SystemConfiguration

class ViewController: NSViewController {
    
    @IBOutlet weak var newUser_TextField: NSTextField!
    @IBOutlet weak var password_TextField: NSSecureTextField!
    
    var writeToLogQ = DispatchQueue(label: "com.jamf.writeToLogQ", qos: .default)
    var LogFileW: FileHandle? = FileHandle(forUpdatingAtPath: "/private/var/log/mobile.to.local.log")

    var userType         = "current"
    var allowNewUsername = false
    var mode             = "interactive"
    var silent           = false
    var unbind           = true
    var listType         = "keeplist"
    var plistData        = [String:Any]()
    
    // OS version info
    let os = ProcessInfo().operatingSystemVersion
    
    let fm = FileManager()
    let migrationScript = Bundle.main.bundlePath+"/Contents/Resources/scripts/mobileToLocal.sh"

    let myNotification = Notification.Name(rawValue:"MyNotification")
    
    // variables used in shell function
    var shellResult = [String]()
    var errorResult = [String]()
    var exitResult:Int32 = 0

    
    let userDefaults = UserDefaults.standard
    // determine if we're using dark mode
    var isDarkMode: Bool {
        let mode = userDefaults.string(forKey: "AppleInterfaceStyle")
        return mode == "Dark"
    }

    @IBAction func migrate(_ sender: Any) {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-_.")
        let newUser = newUser_TextField.stringValue
        if newUser.rangeOfCharacter(from: allowedCharacters.inverted) != nil || newUser == "" {
            WriteToLog.shared.message(stringOfText: "Invalid username: \(newUser).  Only numbers and letters are allowed in the username.")
            alert_dialog(header: "Alert", message: "Only numbers and letters are allowed in the username.")
            return
        }

        let loggedInUser = Function.shared.currentUser()
        let password     = password_TextField.stringValue
        if Function.shared.passwordIsCorrect(username: loggedInUser, password: password) {

            WriteToLog.shared.message(stringOfText: "Password verified for \(loggedInUser).")

            DispatchQueue.main.async {
                self.completeMigration(loggedInUser: loggedInUser, newUser: newUser, password: password)
            }

            showLockWindow()

        } else {
            WriteToLog.shared.message(stringOfText: "Unable to verify password for \(loggedInUser).")
            alert_dialog(header: "Alert", message: "Unable to verify password for \(loggedInUser).  Please re-enter the password.")
            view.window?.makeKeyAndOrderFront(self)
            return
        }
    }

    func completeMigration(loggedInUser: String, newUser: String, password: String) {
        
        // see is user is an admin
        let isAdmin = Function.shared.isAdmin(username: loggedInUser)
        WriteToLog.shared.message(stringOfText: "isAdmin: \(isAdmin)")
        if userType == "current" {
            userType = isAdmin ? "admin":"standard"
        }
        if !["admin", "standard"].contains(userType.lowercased()) {
            WriteToLog.shared.message(stringOfText: "Unknown user type (\(userType)) requested, user type will remain unchanged.")
            userType = isAdmin ? "admin":"standard"
        }
        WriteToLog.shared.message(stringOfText: "Type of local user to convert to: \(userType).")
        
        let isMobile = Function.shared.isMobile(username: loggedInUser)
        if !isMobile {
            WriteToLog.shared.message(stringOfText: "You are not logged in with a mobile account: \(loggedInUser)")
            alert_dialog(header: "Alert", message: "You are not logged in with a mobile account: \(loggedInUser)")
            NSApplication.shared.terminate(self)
        }
        
        WriteToLog.shared.message(stringOfText: "Clean up AuthenticationAuthority")
        let cleanupResult = Function.shared.aaCleanup(username: loggedInUser)
        WriteToLog.shared.message(stringOfText: "Clean up result: \(cleanupResult)")

        WriteToLog.shared.message(stringOfText: "Delete Attributes - start")
        Function.shared.deleteAttributes(username: loggedInUser)
        

//         reset local user's password if needed
        if !hasSecureToken(username: newUser) {
            WriteToLog.shared.message(stringOfText: "Reset password")
                resetUserPassword(username: newUser, originalPassword: password_TextField.stringValue)
                WriteToLog.shared.message(stringOfText: "Password reset successfully.")
        }
        
        WriteToLog.shared.message(stringOfText: "Call demobilization script.")
        (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: ["-c", "'\(migrationScript)' '\(newUser)' \(userType) \(unbind) \(silent)"])
        
        WriteToLog.shared.message(stringOfText: "Logging the user out.")
        (exitResult, errorResult, shellResult) = shell(cmd: "/usr/bin/sudo", args: ["/bin/launchctl", "reboot", "user"])
        logMigrationResult(exitValue: exitResult)
        
    }
    
    func hasSecureToken(username: String) -> Bool {
        if let userRecord = try? Function.shared.getUserRecord(username: username) /*OdUserRecord(username: username)*/ {
            guard let aa = try? userRecord.recordDetails(forAttributes: ["dsAttrTypeStandard:AuthenticationAuthority"])["dsAttrTypeStandard:AuthenticationAuthority"] as? [String] else {
                WriteToLog.shared.message(stringOfText: "Unable to query user for a secure token.")
                return false
            }
            for attrib in aa {
                if attrib.contains("SecureToken") {
                    WriteToLog.shared.message(stringOfText: "User has a secure token.")
                    return true
                }
            }
        }
        WriteToLog.shared.message(stringOfText: "User does not have a secure token.")
        return false
    }

    func resetUserPassword(username: String, originalPassword: String) {
        sleep(1)
        if let userRecord = try? Function.shared.getUserRecord(username: username) {
            // Reset the password
            do {
                try userRecord.changePassword(nil, toPassword: originalPassword)
//                try userRecord.changePassword(originalPassword, toPassword: originalPassword)
                WriteToLog.shared.message(stringOfText: "Password successfully set for user \(username).")
            } catch {
                WriteToLog.shared.message(stringOfText: "Failed password set for user \(username).")
                WriteToLog.shared.message(stringOfText: "Error: \(error.localizedDescription)")
            }
        }
    }
    
    @IBAction func cancel(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    func alert_dialog(header: String, message: String) {
        let dialog: NSAlert = NSAlert()
        dialog.messageText = header
        dialog.informativeText = message
        dialog.alertStyle = NSAlert.Style.warning
        dialog.addButton(withTitle: "OK")
        dialog.runModal()
        //return true
    }   // func alert_dialog - end
    
    func getDateTime(x: Int8) -> String {
        let date = Date()
        let date_formatter = DateFormatter()
        if x == 1 {
            date_formatter.dateFormat = "YYYYMMdd_HHmmss"
        } else {
            date_formatter.dateFormat = "E MMM d yyyy HH:mm:ss"
        }
        let stringDate = date_formatter.string(from: date)
        
        return stringDate
    }

    func logMigrationResult(exitValue: Int32, newUser: String = "") {
        switch exitValue {
        case 0:
            WriteToLog.shared.message(stringOfText: "successfully migrated account.")
            NSApplication.shared.terminate(self)
        case 100:
            NSApplication.shared.terminate(self)
        case 244:
            WriteToLog.shared.message(stringOfText: "Account \(newUser) already exists and belongs to another user.")
            if !silent {
                alert_dialog(header: "Alert", message: "Account \(newUser) already exists and belongs to another user.")
            } else {
                NSApplication.shared.terminate(self)
            }
            return
        case 232:
            WriteToLog.shared.message(stringOfText: "You are not logged in with a mobile account: \(newUser)")
            if !silent {
                alert_dialog(header: "Alert", message: "You are not logged in with a mobile account: \(newUser)")
            } else {
                NSApplication.shared.terminate(self)
            }
            NSApplication.shared.terminate(self)
        default:
            WriteToLog.shared.message(stringOfText: "An unknown error has occured: \(exitResult).")
            if !silent {
                alert_dialog(header: "Alert", message: "An unknown error has occured: \(exitResult).")
            } else {
                NSApplication.shared.terminate(self)
            }
            return
        }
    }
    
    func shell(cmd: String, args: [String]) -> (exitCode: Int32, errorStatus: [String], localResult: [String]) {
        var localResult  = [String]()
        var errorStatus  = [String]()
        
        let pipe        = Pipe()
        let errorPipe   = Pipe()
        let task        = Process()
        
        task.launchPath     = cmd
        task.arguments      = args
        task.standardOutput = pipe
        task.standardError  = errorPipe
        
        task.launch()
        
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        if let result = String(data: outData, encoding: .utf8) {
            localResult = result.components(separatedBy: "\n")
        }
        
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if var result = String(data: errorData, encoding: .utf8) {
            result = result.trimmingCharacters(in: .newlines)
            errorStatus = result.components(separatedBy: "\n")
        }
        
        task.waitUntilExit()
        let exitStatus = task.terminationStatus
        
        return(exitStatus,errorStatus, localResult)
    }

    func showLockWindow() {
//        print("[showLockWindow] enter function")

        if !silent {
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            let LockScreenWindowController = storyboard.instantiateController(withIdentifier: "LockScreen") as! NSWindowController
            if let lockWindow = LockScreenWindowController.window {

                let application = NSApplication.shared
                application.runModal(for: lockWindow)
                lockWindow.close()
            }
        }

//        print("[showLockWindow] lock window shown")
    }
    
    func writeToLog(theMessage: String) {
        writeToLogQ.sync {
            LogFileW?.seekToEndOfFile()
            let fullMessage = getDateTime(x: 2) + " [Migration]: " + theMessage + "\n"
            let LogText = (fullMessage as NSString).data(using: String.Encoding.utf8.rawValue)
            LogFileW?.write(LogText!)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let admin = Function.shared.isAdmin(username: NSUserName())
        WriteToLog.shared.message(stringOfText: "\(NSUserName()) is an admin: \(admin)")
        
        DispatchQueue.main.async { [self] in
            if !FileManager.default.fileExists(atPath: "/private/var/log/mobile.to.local.log") {
                var secondsWaited = 0
                FileManager.default.createFile(atPath: "/private/var/log/mobile.to.local.log", contents: nil, attributes: [.ownerAccountID:0, .groupOwnerAccountID:0, .posixPermissions:0o644])
                while !FileManager.default.fileExists(atPath: "/private/var/log/mobile.to.local.log") {
                    if secondsWaited < 10 {
                        secondsWaited+=1
                    } else {
                        break
                    }
                }
                LogFileW = FileHandle(forUpdatingAtPath: "/private/var/log/mobile.to.local.log")
                if FileManager.default.isWritableFile(atPath: "/private/var/log/mobile.to.local.log") {
                    print("log is writeable")
                } else {
                    print("log is not writeable")
                }
                WriteToLog.shared.message(stringOfText: "New log file created.")
            }
            
            // read environment settings - start
            if FileManager.default.fileExists(atPath: "/Library/Managed Preferences/pse.jamf.mobile-to-local.plist") {
                plistData = (NSDictionary(contentsOf: URL(fileURLWithPath: "/Library/Managed Preferences/pse.jamf.mobile-to-local.plist")) as? [String : Any])!
            }
            if plistData.count == 0 {
                WriteToLog.shared.message(stringOfText: "No configuration file found.")
            } else {
    //            print("settings: \(plistData)")
                allowNewUsername = plistData["allowNewUsername"] as? Bool ?? false
                userType         = plistData["userType"] as? String ?? "current"
                unbind           = plistData["unbind"] as? Bool ?? true
                mode             = plistData["mode"] as? String ?? "interactive"
                if mode == "silent" {
                    silent = true
                }
//                listType         = plistData["listType"] as? String ?? "keeplist"
//                print("allowNewUsername: \(allowNewUsername)")
//                print("        userType: \(userType)")
//                print("          unbind: \(unbind)")
//                print("          silent: \(silent)")
            }
            
            // read commandline args
            var numberOfArgs = 0

            //        debug = true

            numberOfArgs = CommandLine.arguments.count - 1  // subtract 1 as the first argument is the app itself
            if numberOfArgs > 0 {
                if (numberOfArgs % 2) != 0 {
                    WriteToLog.shared.message(stringOfText: "Argument error occured - Contact IT for help.")
                    alert_dialog(header: "Alert", message: "Argument error occured - Contact IT for help.")
                    NSApplication.shared.terminate(self)
                }

                for i in stride(from: 1, through: numberOfArgs, by: 2) {
                    //print("i: \(i)\t argument: \(CommandLine.arguments[i])")
                    switch CommandLine.arguments[i] {
                    case "-allowNewUsername":
                        if (CommandLine.arguments[i+1].lowercased() == "true") || (CommandLine.arguments[i+1].lowercased() == "yes")  {
                            allowNewUsername = true
                        }
                    case "-mode":
                        if (CommandLine.arguments[i+1].lowercased() == "silent") {
                            silent = true
                        }
                    case "-userType":
                        userType = CommandLine.arguments[i+1]
                        userType = (userType.lowercased() == "admin") ? "admin":"standard"
                    case "-unbind":
                        if (CommandLine.arguments[i+1].lowercased() == "false") || (CommandLine.arguments[i+1].lowercased() == "no")  {
                            unbind = false
                        }
//                    case "-listType":
//                        if ["removelist", "keeplist"].contains(CommandLine.arguments[i+1].lowercased()) {
//                            listType = CommandLine.arguments[i+1].lowercased()
//                        } else {
//                            listType = "keeplist"
//                        }
                    default:
                        WriteToLog.shared.message(stringOfText: "unknown switch passed: \(CommandLine.arguments[i])")
//                        print("unknown switch passed: \(CommandLine.arguments[i])")
                    }
                }
            }
            
            if silent {
                allowNewUsername = false
                // hide the app UI
                self.view.isHidden = true
                NSApplication.shared.mainWindow?.setIsVisible(false)
            } else {
                self.view.isHidden = false
                NSApplication.shared.mainWindow?.setIsVisible(true)
            }
            if allowNewUsername {
                self.newUser_TextField.isEditable   = true
            }
            let newUser = Function.shared.currentUser()
//            (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: ["-c","stat -f%Su /dev/console"])
//            newUser = shellResult[0]
            newUser_TextField.stringValue = newUser

            // Verify we're running with elevated privileges.
            if NSUserName() != "root" {
                NSApplication.shared.mainWindow?.setIsVisible(false)
                WriteToLog.shared.message(stringOfText: "Assistant must be run with elevated privileges.")
                alert_dialog(header: "Alert", message: "Assistant must be run with elevated privileges.")
                NSApplication.shared.terminate(self)
            }

            // Verify we're the only account logged in - start
            (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: ["-c", "w | awk '/console/ {print $1}' | sort | uniq"])
            // remove blank entry in array
            var loggedInUserArray = shellResult.dropLast()
            if let index = loggedInUserArray.firstIndex(of:"_mbsetupuser") {
                loggedInUserArray.remove(at: index)
            }

            let loggedInUserCount = loggedInUserArray.count

            if loggedInUserCount > 1 {
                NSApplication.shared.mainWindow?.setIsVisible(false)
                WriteToLog.shared.message(stringOfText: "Other users are currently logged into this machine (fast user switching).")
                WriteToLog.shared.message(stringOfText: "Logged in users: \(shellResult)")
                alert_dialog(header: "Alert", message: "Other users are currently logged into this machine (fast user switching).  They must be logged out before account migration can take place.")
                NSApplication.shared.terminate(self)
            }
            // Verify we're the only account logged in - end
            WriteToLog.shared.message(stringOfText: "No other logins detected.")


            // Verify we're not logged in with a local account
            (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: ["-c", "dscl . -read \"/Users/\(newUser)\" OriginalNodeName 2>/dev/null | grep -v dsRecTypeStandard"])

            let accountTypeArray = shellResult

            if accountTypeArray.count != 0 {
                    if accountTypeArray[0] == "" {
                        NSApplication.shared.mainWindow?.setIsVisible(false)
                        WriteToLog.shared.message(stringOfText: "You are currently logged in with a local account, migration is not necessary.")
                        alert_dialog(header: "Alert", message: "You are currently logged in with a local account, migration is not necessary.")
                        NSApplication.shared.terminate(self)
                    }
            } else {
                NSApplication.shared.mainWindow?.setIsVisible(false)
                WriteToLog.shared.message(stringOfText: "\(errorResult[0])")
                WriteToLog.shared.message(stringOfText: "Unable to locate account information.  You may be logged in with a network managed account.")
                alert_dialog(header: "Alert", message: "Unable to locate account information.  You may be logged in with a network managed account.")
                NSApplication.shared.terminate(self)
            }
            
            // Do any additional setup after loading the view.

            if silent {
                if hasSecureToken(username: newUser) {
                    self.showLockWindow()
                    
                    (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: ["-c", "'\(migrationScript)' '\(newUser)' \(userType) \(unbind) \(silent)"])
                    
                    logMigrationResult(exitValue: exitResult, newUser: newUser)
                } else {
                    WriteToLog.shared.message(stringOfText: "\(newUser) does not have a secure token, cannot run silently.")
                }

                NSApplication.shared.terminate(self)
            } else {
                // show the dock icon
                view.wantsLayer = true
                NSApp.setActivationPolicy(.regular)
                view.layer?.backgroundColor = CGColor(red: 0x5C/255.0, green: 0x78/255.0, blue: 0x94/255.0, alpha: 1.0)
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }

    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    override func viewDidAppear() {

//      Make sure the window is not restorable, to get the cursor in the username field
        NSApplication.shared.mainWindow?.makeFirstResponder(password_TextField)
        
    }

}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSControlStateValue(_ input: NSControl.StateValue) -> Int {
	return input.rawValue
}
