//
//  ViewController.swift
//  mobile_to_local
//
//  Created by Leslie Helou on 4/25/18.
//  Copyright © 2018 jamf. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {
    
    @IBOutlet weak var newUser_TextField: NSTextField!
    @IBOutlet weak var password: NSSecureTextField!
    
    var LogFileW: FileHandle?  = FileHandle(forUpdatingAtPath: "/private/var/log/jamf.log")
    var newUser = ""
    
    let fm = FileManager()
    let migrationScript  = Bundle.main.bundlePath+"/Contents/Resources/scripts/mobileToLocal.sh"
    let passCheckScript  = Bundle.main.bundlePath+"/Contents/Resources/scripts/passCheck.sh"
    
    let myNotification = Notification.Name(rawValue:"MyNotification")

    @IBAction func migrate(_ sender: Any) {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-_")
        newUser = newUser_TextField.stringValue
        if newUser.rangeOfCharacter(from: allowedCharacters.inverted) != nil || newUser == "" {
            alert_dialog(header: "Alert", message: "Only numbers and letters are allowed in the username.")
            return
        }
        let verifyPassword = shell(cmd: "/bin/bash", args: "-c", "'"+passCheckScript+"' '"+password.stringValue+"'")[0] as! Int32

        if verifyPassword == 0 {
            let result = shell(cmd: "/bin/bash", args: "-c", "'"+migrationScript+"' '"+newUser+"' '"+password.stringValue+"'")[0] as! Int32
            switch result {
            case 0:
                writeToLog(theMessage: "successfully migrated account.")
                NSApplication.shared().terminate(self)
            case 244:
                alert_dialog(header: "Alert", message: "Account \(newUser) already exists and belongs to another user.")
                return
            case 232:
                alert_dialog(header: "Alert", message: "You are not logged in with a mobile account.")
                NSApplication.shared().terminate(self)
            default:
                alert_dialog(header: "Alert", message: "An unknown error has occured: \(result).")
                return
                
            }
        } else {
            alert_dialog(header: "Alert", message: "Unable to verify password.")
            return
        }
    }

    @IBAction func cancel(_ sender: Any) {
        NSApplication.shared().terminate(self)
    }
    
    func alert_dialog(header: String, message: String) {
        let dialog: NSAlert = NSAlert()
        dialog.messageText = header
        dialog.informativeText = message
        dialog.alertStyle = NSAlertStyle.warning
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
    
    func shell(cmd: String, args: String...) -> [AnyObject] {
        var localStatus     = [String]()
        let pipe            = Pipe()
        let task            = Process()
        task.launchPath     = cmd
        task.arguments      = args
        task.standardOutput = pipe
        
        task.launch()
        
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        if let result = String(data: outData, encoding: .utf8) {
//          result = result.trimmingCharacters(in: .newlines)
            localStatus = result.components(separatedBy: "\n")
        }
        
        task.waitUntilExit()
        let returnArray = [task.terminationStatus,localStatus] as [Any]
        
        return(returnArray as [AnyObject])
    }
    
    func writeToLog(theMessage: String) {
        LogFileW?.seekToEndOfFile()
        let fullMessage = getDateTime(x: 2) + " \(newUser)[Migration]: " + theMessage + "\n"
        let LogText = (fullMessage as NSString).data(using: String.Encoding.utf8.rawValue)
        LogFileW?.write(LogText!)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let userArray = shell(cmd: "/bin/bash", args: "-c","stat -f%Su /dev/console")[1] as! [String]
        newUser = userArray[0]
        newUser_TextField.stringValue = newUser
        
        
        NSApplication.shared().activate(ignoringOtherApps: true)
        // Verify we're running with elevated privileges.
        if NSUserName() != "root" {
            NSApplication.shared().mainWindow?.setIsVisible(false)
            alert_dialog(header: "Alert", message: "Assistant must be run with elevated privileges.")
            writeToLog(theMessage: "Assistant must be run with elevated privileges.")
            NSApplication.shared().terminate(self)
        }
        
        // Verify we're the only account logged in - start
        let loggedInUserCountArray = shell(cmd: "/bin/bash", args: "-c", "w | awk '/console/ {print $1}' | sort | uniq | wc -l")[1] as! [String]
        let loggedInUserCount = Int(loggedInUserCountArray[0].replacingOccurrences(of: " ", with: ""))
        if loggedInUserCount! > 1 {
            NSApplication.shared().mainWindow?.setIsVisible(false)
            alert_dialog(header: "Alert", message: "Other users are currently logged into this machine (fast user switching).  They must be logged out before account migration can take place.")
            writeToLog(theMessage: "Other users are currently logged into this machine (fast user switching).")
            NSApplication.shared().terminate(self)
        }
        // Verify we're the only account logged in - end

        
        // Verify we're not logged in with a local account
        let accountIdArray = shell(cmd: "/bin/bash", args: "-c", "dscl . -read \"/Users/\(newUser)\" UniqueID | awk '/: / {print $2}'")[1] as! [String]
        if accountIdArray.count > 1 {
            if let accountId = Int32(accountIdArray[0]) {
                if accountId < 1000 {
                    NSApplication.shared().mainWindow?.setIsVisible(false)
                    alert_dialog(header: "Alert", message: "You are currently logged in with a local account, migration is not necessary.")
                    writeToLog(theMessage: "You are currently logged in with a local account, migration is not necessary.")
                    NSApplication.shared().terminate(self)
                }
            }   // if let accountId = Int32(accountIdArray[0]) - end
        } else {
            NSApplication.shared().mainWindow?.setIsVisible(false)
            alert_dialog(header: "Alert", message: "Unable to locate account information.  You may be logged in with a network managed account.")
            writeToLog(theMessage: "Unable to locate account information.  You may be logged in with a network managed account.")
            NSApplication.shared().terminate(self)
        }
        // Do any additional setup after loading the view.
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    override func viewDidAppear() {
        self.view.layer?.backgroundColor = CGColor(red: 0xF2/255.0, green: 0xF2/255.0, blue: 0xF2/255.0, alpha: 1.0)
//      Make sure the window is not restorable, to get the cursor in the username field
        NSApplication.shared().mainWindow?.makeFirstResponder(newUser_TextField)
    }

}
