//
//  SettingsView.swift
//  MineekStore
//
//  Created by Mineek on 02/07/2023.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section(header: Text("App Management")) {
                Button(action: {
                    refreshAll()
                }) {
                    Text("Refresh All")
                }
                Button(action: {
                    installLdid() { success in
                        NSLog("install ldid: \(success)")
                        if success {
                            let alert = UIAlertController(title: "Success", message: "ldid installed successfully", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                        } else {
                            let alert = UIAlertController(title: "Error", message: "ldid failed to install", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                        }
                    }
                }) {
                    Text("Install ldid")
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Settings")
    }
}
