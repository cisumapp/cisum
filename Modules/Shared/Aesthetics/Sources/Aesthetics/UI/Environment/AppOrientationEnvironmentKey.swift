//
//  AppOrientationEnvironmentKey.swift
//  cisum
//
//  Created by Codex on 02/06/26.
//

#if os(iOS)

import SwiftUI
import UIKit

public enum AppOrientation: Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
    case flat
    case unknown

    public var isPortrait: Bool {
        switch self {
        case .portrait, .portraitUpsideDown:
            true
        default:
            false
        }
    }

    public var isLandscape: Bool {
        switch self {
        case .landscapeLeft, .landscapeRight:
            true
        default:
            false
        }
    }

    public init(_ deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .faceUp, .faceDown:
            self = .flat
        case .unknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

public struct AppOrientationEnvironmentKey: EnvironmentKey {
    public static let defaultValue: AppOrientation = .unknown
}

public extension EnvironmentValues {
    var appOrientation: AppOrientation {
        get { self[AppOrientationEnvironmentKey.self] }
        set { self[AppOrientationEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func appOrientation(_ orientation: AppOrientation) -> some View {
        environment(\.appOrientation, orientation)
    }
}

#endif
