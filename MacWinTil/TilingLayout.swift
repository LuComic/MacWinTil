//
//  TilingLayout.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import Foundation
import AppKit

struct TilingLayout {
    
    static func calculateFrames(for windowCount: Int, in screenFrame: NSRect) -> [NSRect] {
        guard windowCount > 0 else { return [] }
        
        switch windowCount {
        case 1:
            return [screenFrame] // Single window takes full screen
        case 2:
            return calculateTwoWindowLayout(in: screenFrame)
        case 3:
            return calculateThreeWindowLayout(in: screenFrame)
        case 4:
            return calculateFourWindowLayout(in: screenFrame)
        default:
            return calculateGridLayout(for: windowCount, in: screenFrame)
        }
    }
    
    private static func calculateTwoWindowLayout(in screenFrame: NSRect) -> [NSRect] {
        let width = screenFrame.width / 2
        
        let leftFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: width,
            height: screenFrame.height
        )
        
        let rightFrame = NSRect(
            x: screenFrame.minX + width,
            y: screenFrame.minY,
            width: width,
            height: screenFrame.height
        )
        
        return [leftFrame, rightFrame]
    }
    
    private static func calculateThreeWindowLayout(in screenFrame: NSRect) -> [NSRect] {
        // Left half for first app, right half split into top and bottom quarters
        let halfWidth = screenFrame.width / 2
        let quarterHeight = screenFrame.height / 2
        
        let leftHalfFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: halfWidth,
            height: screenFrame.height
        )
        
        let bottomRightQuarterFrame = NSRect(
            x: screenFrame.minX + halfWidth,
            y: screenFrame.minY,
            width: halfWidth,
            height: quarterHeight
        )
        
        let topRightQuarterFrame = NSRect(
            x: screenFrame.minX + halfWidth,
            y: screenFrame.minY + quarterHeight,
            width: halfWidth,
            height: quarterHeight
        )
        
        return [leftHalfFrame, bottomRightQuarterFrame, topRightQuarterFrame]
    }
    
    private static func calculateFourWindowLayout(in screenFrame: NSRect) -> [NSRect] {
        let halfWidth = screenFrame.width / 2
        let halfHeight = screenFrame.height / 2
        
        let topLeft = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY + halfHeight,
            width: halfWidth,
            height: halfHeight
        )
        
        let topRight = NSRect(
            x: screenFrame.minX + halfWidth,
            y: screenFrame.minY + halfHeight,
            width: halfWidth,
            height: halfHeight
        )
        
        let bottomLeft = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: halfWidth,
            height: halfHeight
        )
        
        let bottomRight = NSRect(
            x: screenFrame.minX + halfWidth,
            y: screenFrame.minY,
            width: halfWidth,
            height: halfHeight
        )
        
        return [topLeft, topRight, bottomLeft, bottomRight]
    }
    
    private static func calculateGridLayout(for count: Int, in screenFrame: NSRect) -> [NSRect] {
        // Simple grid layout for 5+ windows
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        
        let windowWidth = screenFrame.width / CGFloat(cols)
        let windowHeight = screenFrame.height / CGFloat(rows)
        
        var frames: [NSRect] = []
        
        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            
            let frame = NSRect(
                x: screenFrame.minX + CGFloat(col) * windowWidth,
                y: screenFrame.minY + CGFloat(row) * windowHeight,
                width: windowWidth,
                height: windowHeight
            )
            
            frames.append(frame)
        }
        
        return frames
    }
}
