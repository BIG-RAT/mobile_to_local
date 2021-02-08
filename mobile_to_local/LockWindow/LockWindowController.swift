//
//  LockWindowController.swift
//  Mobile to Local
//
//  Created by Leslie Helou on 2/7/21.
//  Copyright © 2021 jamf. All rights reserved.
//

import Cocoa

class LockWindowController: NSWindowController, NSWindowDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.setIsVisible(false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        self.window?.orderOut(sender)
        return false
    }

    func show() {
        var lwc: NSWindowController?
        if !(lwc != nil) {
            print("[show] set window visible")
            let storyboard = NSStoryboard(name: "LockWindow", bundle: nil)
            lwc = storyboard.instantiateInitialController() as? NSWindowController
//            lwc?.window?.setIsVisible(false)
            lwc?.window?.makeKeyAndOrderFront(self)
        }
    }
}
