//
//  CustomRowView.swift
//  MacBox
//
//  Created by Strongbox on 19/01/2022.
//  Copyright © 2022 Mark McGuill. All rights reserved.
//

import AppKit
import Foundation

class CustomRowView: NSTableRowView {
    // MMcG: Required or drawSelection is not called!!!
    override var backgroundColor: NSColor {
        get {
            return .red
        }
        set {}
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        return .normal 
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            if isEmphasized {
                let selectionRect = bounds.insetBy(dx: 2.5, dy: 2.5)

                NSColor.keyboardFocusIndicatorColor.setStroke()

                let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5)

                selectionPath.lineWidth = 3.0
                selectionPath.stroke()
            } else {
                
            }
        } else {
            super.drawSelection(in: dirtyRect)
        }
    }
}
