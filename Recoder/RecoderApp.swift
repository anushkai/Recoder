//
//  RecoderApp.swift
//  Recoder
//
//  Created by Anushka Idamekorala on 7/13/25.
//

import SwiftUI

@main
struct RecoderApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(macOS 12.3, *) {
                ContentView()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Unsupported macOS Version")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("This app requires macOS 12.3 or later to use audio transcription features.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
