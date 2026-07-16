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

/// The Season area IS value-based (unlike the rest of the menu), so we can push these onto a real
/// NavigationPath and pop several levels at once — a single smooth animation back to the hub.
enum SeasonRoute: Hashable {
    case menu           // the Season Mode hub
    case newSeason
    case resume
    case games(Season)  // a specific season's week-by-week list
}

@Observable
final class Router {
    /// Changing this rebuilds the menu's NavigationStack, returning to the root (menu).
    var resetID = UUID()

    /// The Season area's navigation stack. Setting/truncating this pops season screens in one go.
    var seasonPath: [SeasonRoute] = []

    /// Bumped to ask RootView to replay the launch splash animation (used on "Back to Main Menu").
    var splashRequestID = UUID()

    func popToRoot() {
        // Clear the season stack too, so a rebuild doesn't immediately re-push season screens.
        seasonPath.removeAll()
        resetID = UUID()
    }

    /// Pop all the way to the main menu AND replay the Blitzball splash animation over the return.
    func returnToMainMenu() {
        popToRoot()
        splashRequestID = UUID()
    }

    /// Unwind the Season area back to its hub (Season Mode) in a single animation.
    func goToSeasonMenu() {
        seasonPath = [.menu]
    }
}
