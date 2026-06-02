//
//  LyricsBundle.swift
//  Lyrics
//
//  Created by Aarav Gupta on 21/03/26.
//

import SwiftUI
import WidgetKit

@main
struct LyricsBundle: WidgetBundle {
    var body: some Widget {
        Lyrics()
        if #available(iOS 18.0, *) {
            LyricsControl()
        }
        LyricsLiveActivity()
    }
}
