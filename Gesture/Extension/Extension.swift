//
//  Extension.swift
//  Extension
//
//  Created by Abhinav Pottabathula on 5/18/23.
//

import AppIntents

struct Extension: AppIntent {
    static var title: LocalizedStringResource = "Extension"
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
