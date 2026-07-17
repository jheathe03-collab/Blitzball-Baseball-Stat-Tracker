# Blitzball Stat Tracker

An iOS app for tracking stats in a friendly Blitzball league (a backyard-baseball variant that uses standard baseball statistics). Built with SwiftUI and SwiftData.

## What it does

**Players & Teams**
- Add, edit, and archive players (archiving preserves stat history instead of deleting it)
- Build teams from your player pool, complete with a pick of mascot logos
- View a player's career stats and a team-by-team leaderboard across the league

**Games**
- Set up an Exhibition (one-off) game: pick two teams, batting order, designated hitter, and starting pitcher
- Track a game live with an on-screen bases diamond, plate-appearance-by-plate-appearance outcomes, and mid-game substitutions
- Review and edit completed games from a game summary screen

**Seasons**
- Create a new season or resume one in progress
- Auto-generated weekly schedule, with a pregame setup screen for each week's matchup
- Season-scoped stat leaderboards, separate from career/all-time totals

**Stats**
- Raw counting stats (AB, H, 2B, 3B, HR, BB, SO, RBI, saves, quality starts, etc.) are entered live; rate stats (AVG, OBP, SLG, OPS, BB%, K%, ERA, WHIP, K/BB, BAA) are computed automatically
- A scrolling stat-leaders ticker on the main menu
- Export player data or team/season stats to CSV

**Coming later**
- Tournament bracket play (stubbed for now)

## Stack

- SwiftUI + SwiftData (local, on-device persistence)
- iOS 17+
- Swift Testing / XCTest for stat-math and app tests
