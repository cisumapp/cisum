//
//  Constants.swift
//
//
//  Created by Aarav Gupta on 08/04/26.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public enum Constants {}

public extension Constants {
    static let playerCardPaddings: CGFloat = 32
    static let screenPaddings: CGFloat = 20
    static let itemPeekAmount: CGFloat = 36
    static let dynamicPlayerIslandHeight: CGFloat = 45

    static var safeAreaInsets: EdgeInsets {
#if canImport(UIKit)
        MainActor.assumeIsolated {
            EdgeInsets(UIApplication.keyWindow?.safeAreaInsets ?? .zero)
        }
#else
        EdgeInsets()
#endif
    }

    static func itemWidth(
        forItemsPerScreen count: Int,
        spacing: CGFloat = 0,
        containerWidth: CGFloat
    ) -> CGFloat {
        let totalSpacing = spacing * CGFloat(count)
        let availableWidth = containerWidth - screenPaddings - itemPeekAmount - totalSpacing
        return availableWidth / CGFloat(count)
    }
}

#if canImport(UIKit)
public extension EdgeInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }
}
#endif

public extension EdgeInsets {
    static let rowInsets: EdgeInsets = .init(
        top: 0,
        leading: Constants.screenPaddings,
        bottom: 0,
        trailing: Constants.screenPaddings
    )
}
