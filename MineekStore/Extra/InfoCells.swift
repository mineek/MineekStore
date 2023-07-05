//
//  InfoCells.swift
//  Nucleus
//
//  Created by Mineek on 25/06/2023.
//

import Foundation
import SwiftUI

func createInfoCell(title: String, middletext: String, footer: String) -> some View {
    VStack {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .fontWeight(.semibold)
        Text(middletext)
            .font(.system(size: 16))
            .fontWeight(.semibold)
            .frame(height: 20)
            .opacity(0.8)
        Text(footer)
            .font(.caption)
            .foregroundColor(.secondary)
            .fontWeight(.semibold)
    }
}

func createInfoCellPicture(title: String, image: String, footer: String) -> some View {
    VStack {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .fontWeight(.semibold)
        Image(systemName: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .opacity(0.8)
        Text(footer)
            .font(.caption)
            .foregroundColor(.secondary)
            .fontWeight(.semibold)
    }
}
