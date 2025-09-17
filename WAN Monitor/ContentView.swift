//
//  ContentView.swift
//  WAN Monitor
//
//  Created by Curtis Netterville on 9/16/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            Text("WAN Monitor")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Running in menu bar")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(minWidth: 200)
    }
}

#Preview {
    ContentView()
}