//
//  PlayerCardView.swift
//  Blitzball Stat Tracker
//
//  The full-screen presentation shell for a player's baseball card: a flip card (see FlipCard) whose
//  front/back come from the player's chosen template (see CardTemplate + the per-template files like
//  ClassicCardTemplate / WoodCardTemplate), plus the Add/Change Photo (with crop) and Choose Card
//  Template controls. The card designs themselves live in their own template files.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct PlayerCardView: View {
    @Bindable var player: Player
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    // A freshly picked photo waiting to be framed in the crop screen.
    @State private var pendingCrop: PendingCrop?
    @State private var choosingTemplate = false
    @State private var confirmingPhotoRemoval = false

    /// The player's chosen card template (falls back to Classic).
    private var template: CardTemplateID {
        CardTemplateID(rawValue: player.cardTemplate ?? "") ?? .classic
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            GeometryReader { geo in
                // Fill more of the screen (0.84 of width) while keeping side margins; the height cap
                // keeps it clear of the controls below on shorter screens.
                let cardW = min(geo.size.width * 0.84, (geo.size.height - 180) / CardMetrics.ratio)
                let cardH = cardW * CardMetrics.ratio
                // Lay the card out at the canonical native size and SCALE to fit — identical to how
                // the picker previews render, so a template looks the same on the big card and the tile.
                let scale = cardW / CardMetrics.nativeWidth
                VStack(spacing: 18) {
                    FlipCard {
                        cardFrontView(template, player: player)
                    } back: {
                        cardBackView(template, player: player)
                    }
                    .frame(width: CardMetrics.nativeWidth, height: CardMetrics.nativeHeight)
                    .scaleEffect(scale)
                    .frame(width: cardW, height: cardH)   // collapse layout to the scaled size
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 10)

                    Text("Tap the card to flip")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label(player.photoData == nil ? "Add Photo" : "Change Photo",
                                  systemImage: "photo.badge.plus")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        // Only offered once there's a photo to remove.
                        if player.photoData != nil {
                            Button {
                                confirmingPhotoRemoval = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .accessibilityLabel("Remove Photo")
                        }

                        Button {
                            choosingTemplate = true
                        } label: {
                            Label("Choose Card Template", systemImage: "rectangle.on.rectangle.angled")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
        // Frame the freshly picked photo before saving it.
        .sheet(item: $pendingCrop) { pending in
            PhotoCropView(image: pending.image) { data in
                player.photoData = data
            }
        }
        .sheet(isPresented: $choosingTemplate) {
            CardTemplatePicker(player: player)
        }
        .alert("Remove Photo?", isPresented: $confirmingPhotoRemoval) {
            Button("Remove Photo", role: .destructive) { player.photoData = nil }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(player.name)'s card will show the placeholder until you add another photo. Their stats aren't affected.")
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        pendingCrop = PendingCrop(image: ui)
        photoItem = nil
    }
}

/// A picked photo held while the crop screen frames it.
private struct PendingCrop: Identifiable {
    let id = UUID()
    let image: UIImage
}
