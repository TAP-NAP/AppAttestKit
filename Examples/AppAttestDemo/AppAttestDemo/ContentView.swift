//
//  ContentView.swift
//  AppAttestDemo
//
//  Created by Harold on 2026/4/24.
//

import SwiftUI

struct ContentView: View {
    private let runtime: AppAttestRuntime

    init() {
        do {
            self.runtime = try AppAttestRuntimeFactory.make()
        } catch {
            self.runtime = AppAttestRuntimeFactory.fallbackRuntime(error: error)
        }
    }

    var body: some View {
        AppAttestDemoView(runtime: runtime)
    }
}
