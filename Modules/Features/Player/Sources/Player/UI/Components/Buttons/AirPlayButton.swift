//
//  AirPlayButton.swift
//  cisum
//
//  Created by Aarav Gupta on 27/03/26.
//

import AVKit
import SwiftUI

#if os(iOS)
import UIKit

struct AirPlayButton: UIViewRepresentable {
    var activeTintColor: UIColor = Color.dynamicAccent.uiColor

    func makeUIView(context _: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = .white
        routePickerView.activeTintColor = .white
//        routePickerView.activeTintColor = activeTintColor
        routePickerView.prioritizesVideoDevices = false
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context _: Context) {
        uiView.activeTintColor = .white
//        uiView.activeTintColor = activeTintColor
    }
}

#elseif os(macOS)
import AppKit

struct AirPlayButton: NSViewRepresentable {
    var activeTintColor: NSColor = Color.dynamicAccent.uiColor

    func makeNSView(context _: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }

    func updateNSView(_: AVRoutePickerView, context _: Context) {}
}
#endif
