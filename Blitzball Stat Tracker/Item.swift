//
//  Item.swift
//  Blitzball Stat Tracker
//
//  Created by James Heatherly on 7/9/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
