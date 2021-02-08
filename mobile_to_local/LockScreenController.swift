//
//  LockScreenController.swift
//  Mobile to Local
//
//  Created by Leslie Helou on 2/7/21.
//  Copyright © 2021 jamf. All rights reserved.
//

import Cocoa

class LockScreenController: NSViewController {

    let presOptions: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableProcessSwitching,
        .disableAppleMenu,
        .disableSessionTermination,
        .disableHideApplication,
    ]
    /*These are all of the options for NSApplicationPresentationOptions
     .autoHideDock
     .autoHideMenuBar
     .disableForceQuit
     .disableMenuBarTransparency
     .fullScreen
     .hideDock
     .hideMenuBar
     .disableAppleMenu
     .disableProcessSwitching
     .disableSessionTermination
     .disableHideApplication
     .autoHideToolbar
     .hideMenuBar
     .disableAppleMenu
     .autoHideToolbar */

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }

    override func viewDidAppear() {
        view.layer?.backgroundColor = CGColor(red: 0x66/255.0, green: 0x68/255.0, blue: 0x68/255.0, alpha: 0.8)
        let optionsDictionary = [NSView.FullScreenModeOptionKey.fullScreenModeApplicationPresentationOptions :
                    NSNumber(value: presOptions.rawValue)]

        view.enterFullScreenMode(NSScreen.main!, withOptions:optionsDictionary)
        view.wantsLayer = true
    }
    
    func hideScreen() {
        view.exitFullScreenMode()
        dismiss(self)
        view.wantsLayer = false
    }
    
}
