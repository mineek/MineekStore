//
//  AppsView.swift
//  MineekStore
//
//  Created by Mineek on 01/07/2023.
//

import SwiftUI
import SDWebImageSwiftUI

struct AppSmallView: View {
    @State var app: StoreApp
    @State var isInstalling: Bool = false
    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack {
                        if app.Icon != nil {
                            WebImage(url: URL(string: app.Icon!))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundColor(.red)
                        }
                        else {
                            Image(systemName: "wrench.and.screwdriver")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundColor(.red)
                        }
                        VStack(alignment: .leading) {
                            Text(app.Name)
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(UIColor.label))
                                .alignmentGuide(.leading) { _ in 0 }
                            Text("\(app.Developer ?? "Unknown Developer")")
                                .font(.subheadline)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .alignmentGuide(.leading) { _ in 0 }
                        }
                        Spacer()
                        Button(action: {
                            if isInstalling {
                                return
                            }
                            isInstalling = true
                            installApp(appRelease: app.Releases.last!) { success in
                                isInstalling = false
                            }
                        }) {
                            if isInstalling {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                                    .frame(width: 24, height: 24)
                            }
                            else {
                                Text("GET")
                                    .font(.system(size: 14))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(23)
                }
                .padding()
            }
        }
    }
}

struct AppFullView: View {
    @State var app: StoreApp
    @State var isInstalling: Bool = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    AppSmallView(app: app)
                    .padding()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            createInfoCell(title: "VERSION", middletext: app.Releases.last?.Version ?? "Unknown", footer: "")
                        }
                        .padding(.horizontal)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading) { // Set alignment to leading
                            Text("Description")
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(UIColor.label))
                            
                            Text(app.Description ?? "An awesome app!")
                                .font(.subheadline)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal)
                }
                Divider()
                if app.Screenshot != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(app.Screenshot!, id: \.self) { screenshot in
                                WebImage(url: URL(string: screenshot))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 200, height: 400)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppListCell: View {
    @State var app: StoreApp
    var body: some View {
        NavigationLink(destination: AppFullView(app: app)) {
            VStack(alignment: .leading) {
                HStack {
                    HStack {
                        if app.Icon != nil {
                            WebImage(url: URL(string: app.Icon!))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundColor(.red)
                        }
                        else {
                            Image(systemName: "wrench.and.screwdriver")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundColor(.red)
                        }
                        VStack(alignment: .leading) {
                            Text(app.Name)
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(UIColor.label))
                                .alignmentGuide(.leading) { _ in 0 }
                            Text("\(app.Developer ?? "Unknown Developer")")
                                .font(.subheadline)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .alignmentGuide(.leading) { _ in 0 }
                        }
                        Spacer()
                    }
                }
                .padding(0.6)
            }
        }
    }
}

struct AppsView: View {
    @State var repo: String = "https://mineek.github.io/mineekstoreapi/apps.json"
    @State var apps: [StoreApp] = []
    @State var searchText: String = ""
    var body: some View {
        NavigationView {
            if #available(iOS 15.0, *) {
                List {
                    ForEach(apps.filter {
                        searchText.isEmpty ? true : $0.Name.localizedCaseInsensitiveContains(searchText)
                    }, id: \.self) { app in
                        AppListCell(app: app)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .navigationBarTitle("Apps")
                .onAppear {
                    fetchPackages()
                }
            } else {
                List {
                    ForEach(apps.filter {
                        searchText.isEmpty ? true : $0.Name.localizedCaseInsensitiveContains(searchText)
                    }, id: \.self) { app in
                        AppSmallView(app: app)
                    }
                }
                .listStyle(.plain)
                .navigationBarTitle("Apps")
                .onAppear {
                    fetchPackages()
                }
            }
        }
    }

    private func fetchPackages() {
        let dispatchGroup = DispatchGroup()
        guard let url = URL(string: repo) else {
            NSLog("Error: Cannot load apps data!")
            return
        }
        dispatchGroup.enter()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { dispatchGroup.leave() }
            guard let data = data else {
                NSLog("Error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            do {
                let repo = try JSONDecoder().decode(Repo.self, from: data)
                DispatchQueue.main.async {
                    apps = []
                    self.apps.append(contentsOf: repo.apps)
                }
            } catch {
                NSLog("Error: \(error.localizedDescription)")
            }
        }
        task.resume()
    }
}
