//
//  Router.swift
//  Blitzball Stat Tracker
//
//  A tiny navigation coordinator for the main-menu stack. MainMenuView owns it and shares it via
//  the environment, so a deep screen (like the Game Summary after a game ends) can pop all the
//  way back to the menu in one tap.
//
//  Our menu uses view-based NavigationLinks, which don't register with a NavigationPath binding.
//  So instead of driving a path, we pop to root by changing the stack's `.id` — that rebuilds the
//  NavigationStack, which snaps it back to its root (the menu).
//

import SwiftUI

@Observable
final class Router {
    /// Changing this rebuilds the menu's NavigationStack, returning to the root (menu).
    var resetID = UUID()

    func popToRoot() {
        resetID = UUID()
    }
}
