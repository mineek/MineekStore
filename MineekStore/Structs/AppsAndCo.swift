//
//  TweakAndCo.swift
//  MDCManagerV2
//
//  Created by Mineek on 22/06/2023.
//

import Foundation

struct StoreApp: Codable, Hashable {
    var Name: String  = "Unknown"
    var Description: String? = "Unknown"
    var Category: String? = "Unknown"
    var Caption: String? = "Unknown"
    var Releases: [Release] = []
    var Icon: String? = "Unknown"
    var Screenshot: [String]? = []
    var Developer: String? = "Unknown"
}

struct Release: Codable, Hashable {
    var Version: String? = "Unknown"
    var URL: String? = "Unknown"
    var Description: String? = "Unknown"
}

struct Repo: Codable, Hashable {
    var apps: [StoreApp] = []
}
