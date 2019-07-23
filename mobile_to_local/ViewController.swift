//
//  ViewController.swift
//  mobile_to_local
//
//  Created by Leslie Helou on 4/25/18.
//  Copyright © 2018 jamf. All rights reserved.
//

import AppKit
import Cocoa
import Foundation

class ViewController: NSViewController {
    
    @IBOutlet weak var newUser_TextField: NSTextField!
    @IBOutlet weak var updateHomeDir_button: NSButton!
    @IBOutlet weak var password: NSSecureTextField!
    
    var LogFileW: FileHandle?  = FileHandle(forUpdatingAtPath: "/private/var/log/jamf.log")
    var newUser                = ""
    var userType               = ""
    
    let fm = FileManager()
    let migrationScript = Bundle.main.bundlePath+"/Contents/Resources/scripts/mobileToLocal.sh"
    let passCheckScript = Bundle.main.bundlePath+"/Contents/Resources/scripts/passCheck.sh"
    
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
        allowedCharacters.insert(charactersIn: "-_")
        newUser = newUser_TextField.stringValue
        if newUser.rangeOfCharacter(from: allowedCharacters.inverted) != nil || newUser == "" {
            alert_dialog(header: "Alert", message: "Only numbers and letters are allowed in the username.")
            return
        }
        (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: "-c", "'"+passCheckScript+"' '"+password.stringValue+"'")
//        let verifyPassword = shell(cmd: "/bin/bash", args: "-c", "'"+passCheckScript+"' '"+password.stringValue+"'")[0] as! Int32

        if exitResult == 0 {
//            if verifyPassword == 0 {
//            let migrateCommand = "'"+migrationScript+"' '"+newUser+"' '"+password.stringValue+"' \(updateHomeDir_button.state)"
            (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: "-c", "'"+migrationScript+"' '"+newUser+"' '"+password.stringValue+"' \(convertFromNSControlStateValue(updateHomeDir_button.state)) "+userType)
//            (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: "-c", migrateCommand)
//            let result = shell(cmd: "/bin/bash", args: "-c", "'"+migrationScript+"' '"+newUser+"' '"+password.stringValue+"'")[0] as! Int32
            switch exitResult {
            case 0:
                writeToLog(theMessage: "successfully migrated account.")
                NSApplication.shared.terminate(self)
            case 244:
                alert_dialog(header: "Alert", message: "Account \(newUser) already exists and belongs to another user.")
                return
            case 232:
                alert_dialog(header: "Alert", message: "You are not logged in with a mobile account.")
                NSApplication.shared.terminate(self)
            default:
                alert_dialog(header: "Alert", message: "An unknown error has occured: \(exitResult).")
                return
                
            }
        } else {
            alert_dialog(header: "Alert", message: "Unable to verify password.")
            return
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
    
    func shell(cmd: String, args: String...) -> (exitCode: Int32, errorStatus: [String], localResult: [String]) {
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

    
    func writeToLog(theMessage: String) {
        LogFileW?.seekToEndOfFile()
        let fullMessage = getDateTime(x: 2) + " \(newUser)[Migration]: " + theMessage + "\n"
        let LogText = (fullMessage as NSString).data(using: String.Encoding.utf8.rawValue)
        LogFileW?.write(LogText!)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.layer?.backgroundColor = CGColor(red: 0x5C/255.0, green: 0x78/255.0, blue: 0x94/255.0, alpha: 1.0)
        
        // OS version info
        let os = ProcessInfo().operatingSystemVersion

        if os.minorVersion >= 14 {
//            self.view.layer?.backgroundColor = CGColor(red: 0x5C/255.0, green: 0x78/255.0, blue: 0x94/255.0, alpha: 1.0)
        }
        
        (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: "-c","stat -f%Su /dev/console")
//        let userArray = shell(cmd: "/bin/bash", args: "-c","stat -f%Su /dev/console")[1] as! [String]
        newUser = shellResult[0]
//        newUser = userArray[0]
        newUser_TextField.stringValue = newUser
        
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Verify we're running with elevated privileges.
        if NSUserName() != "root" {
            NSApplication.shared.mainWindow?.setIsVisible(false)
            alert_dialog(header: "Alert", message: "Assistant must be run with elevated privileges.")
            writeToLog(theMessage: "Assistant must be run with elevated privileges.")
            NSApplication.shared.terminate(self)
        }
        
        // Verify we're the only account logged in - start
        (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: "-c", "w | awk '/console/ {print $1}' | sort | uniq")
        // remove blank entry in array
        var loggedInUserArray = shellResult.dropLast()
        if let index = loggedInUserArray.firstIndex(of:"_mbsetupuser") {
            loggedInUserArray.remove(at: index)
        }
//        let loggedInUserCountArray = shell(cmd: "/bin/bash", args: "-c", "w | awk '/console/ {print $1}' | sort | uniq | wc -l")[1] as! [String]
        let loggedInUserCount = loggedInUserArray.count
//        let loggedInUserCount = Int(loggedInUserCountArray[0].replacingOccurrences(of: " ", with: ""))
        if loggedInUserCount > 1 {
            NSApplication.shared.mainWindow?.setIsVisible(false)
            writeToLog(theMessage: "Other users are currently logged into this machine (fast user switching).")
            writeToLog(theMessage: "Logged in users: \(shellResult)")
            alert_dialog(header: "Alert", message: "Other users are currently logged into this machine (fast user switching).  They must be logged out before account migration can take place.")
            NSApplication.shared.terminate(self)
        }
        // Verify we're the only account logged in - end

        
        // Verify we're not logged in with a local account
        (exitResult, errorResult, shellResult) = shell(cmd: "/bin/bash", args: "-c", "dscl . -read \"/Users/\(newUser)\" OriginalNodeName 2>/dev/null | grep -v dsRecTypeStandard")
//        let dsclLookup = shell(cmd: "/bin/bash", args: "-c", "dscl . -read \"/Users/\(newUser)\" UniqueID | awk '/: / {print $2}'")
        let accountTypeArray = shellResult
//        let accountIdArray = dsclLookup[1] as! [String]
        if accountTypeArray.count != 0 {
//            let accountType = accountTypeArray[0] {
                if accountTypeArray[0] == "" {
                    NSApplication.shared.mainWindow?.setIsVisible(false)
                    writeToLog(theMessage: "You are currently logged in with a local account, migration is not necessary.")
                    alert_dialog(header: "Alert", message: "You are currently logged in with a local account, migration is not necessary.")
                    NSApplication.shared.terminate(self)
                }
//            }   // if let accountId = Int32(accountIdArray[0]) - end
        } else {
            NSApplication.shared.mainWindow?.setIsVisible(false)
            writeToLog(theMessage: "\(errorResult[0])")
            writeToLog(theMessage: "Unable to locate account information.  You may be logged in with a network managed account.")
            alert_dialog(header: "Alert", message: "Unable to locate account information.  You may be logged in with a network managed account.")
            NSApplication.shared.terminate(self)
        }
        // Do any additional setup after loading the view.
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    override func viewDidAppear() {
        // read commandline args
        var numberOfArgs = 0
        
        //        debug = true
        
        numberOfArgs = CommandLine.arguments.count - 1  // subtract 1 as the first argument is the app itself
        if numberOfArgs > 0 {
            if (numberOfArgs % 2) == 0 {
                print("correct number of arguments")
            } else {
                alert_dialog(header: "Alert", message: "Argument error occured - Contact IT for help.")
                NSApplication.shared.terminate(self)
            }
            
            for i in stride(from: 1, through: numberOfArgs, by: 2) {
                //print("i: \(i)\t argument: \(CommandLine.arguments[i])")
                switch CommandLine.arguments[i] {
                case "-allowNewUsername":
                    if (CommandLine.arguments[i+1].lowercased() == "true") || (CommandLine.arguments[i+1].lowercased() == "yes")  {
                        newUser_TextField.isEditable    = true
                        updateHomeDir_button.isEnabled  = true
                        updateHomeDir_button.isHidden   = false
                    }
                case "-userType":
                    userType                        = CommandLine.arguments[i+1]
                default:
                    print("unknown switch passed: \(CommandLine.arguments[i])")
                }
            }
        }

//      Make sure the window is not restorable, to get the cursor in the username field
        NSApplication.shared.mainWindow?.makeFirstResponder(newUser_TextField)
        
    }

}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSControlStateValue(_ input: NSControl.StateValue) -> Int {
	return input.rawValue
}
