//
//  PhotoCropView.swift
//  Blitzball Stat Tracker
//
//  A pan/zoom framing screen shown after a player photo is picked. The user positions the photo
//  inside a card-shaped window; "Use Photo" renders exactly that window (via ImageRenderer) into a
//  small JPEG that gets stored — so the framing is baked in and the card just displays the result.
//

import SwiftUI
import UIKit

struct PhotoCropView: View {
    let image: UIImage
    /// Crop-window aspect (width / height) — matches the card's photo area so it's WYSIWYG.
    var aspect: CGFloat = 0.70
    let onCrop: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    // Committed transform.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    // Live gesture deltas.
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let cropW: CGFloat = 300
    private var cropH: CGFloat { cropW / aspect }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                framedImage(zoom: zoom * pinch,
                            offset: CGSize(width: offset.width + drag.width,
                                           height: offset.height + drag.height))
                    .frame(width: cropW, height: cropH)
                    .clipped()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                    .gesture(dragGesture.simultaneously(with: magnifyGesture))

                VStack {
                    Spacer()
                    Text("Pinch to zoom · drag to reposition")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Frame Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        if let data = renderCrop() { onCrop(data) }
                        dismiss()
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func framedImage(zoom: CGFloat, offset: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: cropW, height: cropH)   // fill the window as the base
            .scaleEffect(zoom)
            .offset(offset)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
                clampOffset()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                zoom = min(max(zoom * value, 1), 5)
                clampOffset()
            }
    }

    /// Keep the image from being dragged off the crop window (which would expose the black ZStack
    /// background and bake it into the saved JPEG).
    ///
    /// The previous limit `cropW * zoom` was orders of magnitude too generous — it let the whole
    /// photo slide out of the window at zoom = 1. The correct slack is HALF of the *rendered*
    /// image's overflow past the window: `(renderedDim * zoom - cropDim) / 2`, clamped at 0.
    /// `.scaledToFill()` in a cropW × cropH inner frame scales the image so its short axis exactly
    /// matches the window and the long axis extends beyond (so `renderedW`/`renderedH` depend on
    /// the source aspect vs the crop aspect).
    private func clampOffset() {
        let imageAspect = image.size.width / max(image.size.height, 1)
        let cropAspect = cropW / cropH
        // How large the image is actually drawn (before scaleEffect) inside the cropW × cropH frame.
        let renderedW: CGFloat = imageAspect > cropAspect ? cropH * imageAspect : cropW
        let renderedH: CGFloat = imageAspect < cropAspect ? cropW / imageAspect : cropH
        let limitX = max(0, (renderedW * zoom - cropW) / 2)
        let limitY = max(0, (renderedH * zoom - cropH) / 2)
        offset.width = min(max(offset.width, -limitX), limitX)
        offset.height = min(max(offset.height, -limitY), limitY)
    }

    @MainActor
    private func renderCrop() -> Data? {
        let content = framedImage(zoom: zoom, offset: offset)
            .frame(width: cropW, height: cropH)
            .clipped()
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3   // render at ~3x for a crisp thumbnail
        guard let ui = renderer.uiImage else { return nil }
        return Self.downscaled(ui, maxDimension: 560).jpegData(compressionQuality: 0.85)
    }

    /// Shrink so the stored blob stays small (a few tens of KB).
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
