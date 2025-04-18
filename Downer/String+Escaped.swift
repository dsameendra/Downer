//
//  String+Escaped.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import Foundation

extension String {
    /// Escape quotes and spaces so we can safely embed this string in a shell command
    func escaped() -> String {
        self
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: " ",  with: "\\ ")
    }
}
