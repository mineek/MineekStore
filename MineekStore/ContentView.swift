//
//  ContentView.swift
//  MineekStore
//
//  Created by Mineek on 05/07/2023.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            AppsView().tabItem {
                Label("Apps", systemImage: "rectangle.stack")
            }
            SettingsView().tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
