//
//  Item.swift
//  ErgScan1
//
//  Created by Owen O'Malley on 2/7/26.
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
