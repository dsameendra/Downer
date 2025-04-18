//
//  DownloadType.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//


import Foundation

enum DownloadType: String, CaseIterable, Identifiable {
    case both  = "Video + Audio"
    case audio = "Audio Only"
    case video = "Video Only"
    var id: String { rawValue }
}