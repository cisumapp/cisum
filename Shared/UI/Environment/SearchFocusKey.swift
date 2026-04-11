//
//  SearchFocusKey.swift
//  
//
//  Created by Aarav Gupta on 09/04/26.
//

import SwiftUI

extension EnvironmentValues {
    var isSearchExpanded: Binding<Bool> {
        get { self[SearchExpandedKey.self] }
        set { self[SearchExpandedKey.self] = newValue }
    }
}

private struct SearchExpandedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}
