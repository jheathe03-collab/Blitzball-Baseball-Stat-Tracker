//
//  SeasonNavigator.swift
//  Blitzball Stat Tracker
//
//  A tiny shared signal for the Season area. SeasonGamesView sits two screens below the Season
//  Mode menu, and a view's own `dismiss()` only pops ONE level (and only works while that view is
//  on top). So to jump all the way back to the hub we relay intent: the games screen flips
//  `exitRequested` and pops itself; when the intermediate screen (Resume Season / New Season)
//  reappears on top, it sees the flag and pops itself too — landing on the Season Mode menu.
//

import Foundation

@Observable
final class SeasonNavigator {
    /// Set true to request unwinding back to the Season Mode menu.
    var exitRequested = false
}
