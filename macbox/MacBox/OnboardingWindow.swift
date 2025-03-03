//
//  OnboardingWindow.swift
//  MacBox
//
//  Created by Strongbox on 19/06/2022.
//  Copyright © 2022 Mark McGuill. All rights reserved.
//

import Cocoa

class OnboardingWindow : NSWindow {
    var onboardingDoneCompletion : (() -> Void)? = nil
    
    class func createOnboardingWindow( vc : NSViewController, onboardingDoneCompletion : @escaping () -> Void ) -> OnboardingWindow {
        let win = OnboardingWindow(contentViewController: vc)

        win.onboardingDoneCompletion = onboardingDoneCompletion
        
        win.isReleasedWhenClosed = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true

        win.styleMask.remove(.miniaturizable)
        
        win.makeKeyAndOrderFront(self)
        
        return win
    }
    
    override func cancelOperation(_ sender: Any?) { 
        close()
    }
    
    override func close() {
        super.close()

        onboardingDoneCompletion? ()
    }
}
