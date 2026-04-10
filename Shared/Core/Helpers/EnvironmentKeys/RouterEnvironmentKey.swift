//
//  RouterEnvironmentKey.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import SwiftUI

private struct RouterEnvironmentKey: EnvironmentKey {
    static var defaultValue: Router {
        fatalError("Missing Router environment value. Inject it with .environment(\\.router, ...).")
    }
}

extension EnvironmentValues {
    var router: Router {
        get { self[RouterEnvironmentKey.self] }
        set { self[RouterEnvironmentKey.self] = newValue }
    }
}
