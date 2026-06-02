//
//  Tab.swift
//  cisum
//
//  Created by Aarav Gupta on 05/12/25.
//

import SwiftUI

/// A custom implementation of `Tab` that works on iOS 17+.
public struct Tab<SelectionValue: Hashable> {
    public let data: TabViewData<SelectionValue>

    public init(_ title: String, systemImage: String, value: SelectionValue, role: TabRole? = nil, @ViewBuilder content: () -> some View) {
        self.data = TabViewData(
            title: title,
            icon: systemImage,
            value: value,
            role: role,
            content: AnyView(content())
        )
    }
}
