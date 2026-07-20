//
//  TeamLogo.swift
//  Blitzball Stat Tracker
//
//  The bundled team logos (transparent PNGs in Assets), a reusable view to render one next to a
//  team, and a picker grid for choosing one. `Team.logoName` stores the chosen asset name (or nil).
//

import SwiftUI
import PhotosUI
import UIKit

enum TeamLogo {
    /// Asset names of the bundled logos, in menu order. These MUST match the imageset names in
    /// Assets.xcassets — they're what `Image(_:)` loads and what `Team.logoName` stores.
    static let all = ["Banana", "BlitzDragons", "Bobcats", "Dragons",
                      "Elephants", "MightyFish", "Peppers", "Sharks"]

    /// The friendly, on-screen team name for each asset. Kept separate from the asset name so we
    /// can show fun labels without breaking image lookups (which key off the asset name).
    private static let displayNames: [String: String] = [
        "Banana":       "Banana Splits",
        "BlitzDragons": "Blitz Lizards",
        "Bobcats":      "Blitzed Bobcats",
        "Dragons":      "Knuckle Dragons",
        "Elephants":    "Homerun Elephants",
        "MightyFish":   "BlitzFish",
        "Peppers":      "Spicy Peppers",
        "Sharks":       "Whiffle Sharks",
    ]

    /// The label to show for a logo. Falls back to splitting camelCase (e.g. "MightyFish" →
    /// "Mighty Fish") for any asset not in the map.
    static func displayName(_ name: String) -> String {
        if let friendly = displayNames[name] { return friendly }
        return name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    /// Per-logo visual scale. Wide/short artwork fits its width in a square frame and ends up
    /// looking small, so we nudge those up so every logo reads at a similar size.
    static func visualScale(_ name: String?) -> CGFloat {
        switch name {
        case "Peppers":    return 1.35
        case "Dragons":    return 1.20
        default:           return 1.0
        }
    }

    /// Turn an imported photo into a small SQUARE logo thumbnail we can store on the team.
    ///
    /// We (1) center-crop the photo to a square so it fills the logo slot without distortion, and
    /// (2) downscale to `maxSize` and re-encode as JPEG so the stored blob stays tiny (tens of KB).
    /// Baking the square crop in here keeps every render site simple — the image is already square,
    /// so `TeamLogoView` just draws it. Returns nil if the data isn't a decodable image.
    static func squareThumbnail(from data: Data, maxSize: CGFloat = 256, jpegQuality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        // Center-crop to a square using the shorter side.
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
        let target = min(side, maxSize)

        // Draw the cropped square into a `target`×`target` canvas (downscaling in one step).
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1               // we want exactly `target` pixels, not @2x/@3x
        format.opaque = false          // keep any transparency
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let square = renderer.image { _ in
            // Offset the source so the crop rect lands at (0,0), scaled to fill the canvas.
            let scale = target / side
            let drawRect = CGRect(
                x: -origin.x * scale,
                y: -origin.y * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            image.draw(in: drawRect)
        }
        return square.jpegData(compressionQuality: jpegQuality)
    }
}

/// Renders a team's logo fitted into a square, or a neutral placeholder when none is set.
///
/// Render priority: a custom imported photo (`imageData`) wins, then a bundled asset (`logoName`),
/// then a neutral placeholder. Most call sites have a `Team` and should use `init(team:size:)`,
/// which reads both fields; the `init(logoName:...)` form stays for the few places that only have a
/// name (or local picker state not yet attached to a team).
struct TeamLogoView: View {
    let logoName: String?
    let imageData: Data?
    var size: CGFloat = 28

    init(logoName: String?, imageData: Data? = nil, size: CGFloat = 28) {
        self.logoName = logoName
        self.imageData = imageData
        self.size = size
    }

    /// Convenience: read both the bundled name and any custom photo straight off the team.
    init(team: Team?, size: CGFloat = 28) {
        self.logoName = team?.logoName
        self.imageData = team?.logoImageData
        self.size = size
    }

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                // Custom photo — already a square thumbnail, so just fit it to the frame.
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            } else if let logoName, !logoName.isEmpty {
                Image(logoName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(TeamLogo.visualScale(logoName))
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A grid to choose a team's logo: "None", an imported photo, or one of the bundled logos.
struct TeamLogoPicker: View {
    @Binding var logoName: String?
    @Binding var logoImageData: Data?
    @Environment(\.dismiss) private var dismiss

    // The photo the user picked from their library (before we downscale + store it).
    @State private var photoItem: PhotosPickerItem?
    // Surfaced if a chosen photo can't be read as an image.
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    cell(name: nil)
                    importPhotoCell
                    // If a custom photo is set, show it as its own selected cell.
                    if logoImageData != nil { customPhotoCell }
                    ForEach(TeamLogo.all, id: \.self) { cell(name: $0) }
                }
                .padding()
            }
            .navigationTitle("Team Logo")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPhoto(newItem) }
            }
            .alert("Couldn't Use Photo", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Cells

    /// A bundled-logo (or "None") cell. Choosing one clears any custom photo — they're exclusive.
    @ViewBuilder
    private func cell(name: String?) -> some View {
        let isSelected = logoImageData == nil && (logoName ?? "") == (name ?? "")
        Button {
            logoName = name
            logoImageData = nil
            dismiss()
        } label: {
            logoCellLabel(TeamLogoView(logoName: name, size: 76),
                          title: name.map(TeamLogo.displayName) ?? "None",
                          isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    /// Opens the system photo picker. Selecting a photo bakes a square thumbnail and stores it.
    private var importPhotoCell: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            logoCellLabel(
                Image(systemName: "photo.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(18)
                    .frame(width: 76, height: 76),
                title: "Import Photo",
                isSelected: false
            )
        }
        .buttonStyle(.plain)
    }

    /// Shows the currently-set custom photo as a selected cell (tap to re-confirm/close).
    private var customPhotoCell: some View {
        Button {
            dismiss()
        } label: {
            logoCellLabel(TeamLogoView(logoName: nil, imageData: logoImageData, size: 76),
                          title: "Your Photo",
                          isSelected: true)
        }
        .buttonStyle(.plain)
    }

    /// Shared card chrome for every cell: the artwork on a dark card + a caption, with a selection ring.
    private func logoCellLabel(_ artwork: some View, title: String, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            artwork
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Photo import

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importError = "That photo couldn't be loaded. Try a different one."
                return
            }
            guard let thumbnail = TeamLogo.squareThumbnail(from: data) else {
                importError = "That file isn't a supported image. Try a different photo."
                return
            }
            logoImageData = thumbnail
            logoName = nil          // custom photo replaces any bundled logo
            photoItem = nil
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }
}
