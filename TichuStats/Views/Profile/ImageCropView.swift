//
//  ImageCropView.swift
//  TichuStats
//
//  Created by Leon on 12.10.2026.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Entry point used in ProfileView
extension View {
    func imageCropPicker(
        isPresented: Binding<Bool>,
        croppedImage: Binding<UIImage?>
    ) -> some View {
        modifier(
            ImageCropPickerModifier(
                isPresented: isPresented,
                croppedImage: croppedImage
            )
        )
    }
}

private struct PickedPhoto: Identifiable {
    let id = UUID()
    let item: PhotosPickerItem
}

struct ImageCropPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var croppedImage: UIImage?

    @State private var pickerItem: PhotosPickerItem?
    @State private var picked: PickedPhoto?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }

                Task { @MainActor in
                    /*var waited = 0
                    while isPresented && waited < 40 {
                        try? await Task.sleep(for: .milliseconds(50))
                        waited += 1
                    }
                    try? await Task.sleep(for: .milliseconds(250))*/

                    picked = PickedPhoto(item: item)
                    pickerItem = nil
                }
            }
            .sheet(item: $picked) { photo in
                ImageCropView(
                    item: photo.item,
                    croppedImage: $croppedImage
                )
            }
    }
}

// MARK: - Crop screen
struct ImageCropView: View {
    @Environment(\.dismiss) private var dismiss

    let item: PhotosPickerItem
    @Binding var croppedImage: UIImage?

    // Image state
    @State private var source: UIImage?
    @State private var isLoading = true
    @State private var loadError: String?

    // Transformation
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero

    // Temporary gesture state
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    // Configuration
    private let inset: CGFloat = 16
    private let maxZoom: CGFloat = 4
    private let maxSourceDimension: CGFloat = 2048
    private let outputDimension: CGFloat = 1024

    var body: some View {
        NavigationStack {
            cropScreen
        }
        .statusBarHidden()
        .task {
            await load(item)
        }
        .alert(
            String(localized: "crop.unableToLoad"),
            isPresented: Binding(
                get: { loadError != nil },
                set: { presented in
                    if !presented {
                        loadError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "general.alert.ok"), role: .cancel) {
                loadError = nil
                dismiss()
            }
        } message: {
            Text(
                loadError ?? String(localized: "crop.pleaseTryOther")
            )
        }
    }

    // MARK: CropScreen
    private var cropScreen: some View {
        GeometryReader { geometry in
            let diameter = max(
                min(
                    geometry.size.width,
                    geometry.size.height
                ) - inset * 2,
                1
            )

            let liveZoom = min(
                max(zoom * pinch, 1),
                maxZoom
            )

            let liveOffset = clamped(
                CGSize(
                    width: offset.width + drag.width,
                    height: offset.height + drag.height
                ),
                zoom: liveZoom,
                diameter: diameter
            )

            ZStack {
                if let source {
                    let scale = baseScale(
                        source,
                        diameter: diameter
                    ) * liveZoom

                    Image(uiImage: source)
                        .resizable()
                        .frame(
                            width: source.size.width * scale,
                            height: source.size.height * scale
                        )
                        .offset(liveOffset)

                    CircleCutout(diameter: diameter)
                        .fill(
                            .black.opacity(0.55),
                            style: FillStyle(eoFill: true)
                        )
                        .allowsHitTesting(false)

                    Circle()
                        .strokeBorder(
                            .white.opacity(0.01),
                            lineWidth: 1
                        )
                        .frame(
                            width: diameter,
                            height: diameter
                        )
                        .allowsHitTesting(false)
                }

                if isLoading {
                    ProgressView()
                        .padding(24)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .clipped()
            .contentShape(Rectangle())
            .gesture(magnify(diameter: diameter))
            .simultaneousGesture(pan(diameter: diameter))
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(.snappy) {
                            zoom = 1
                            offset = .zero
                        }
                    }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        save(diameter: diameter)
                    }
                    .disabled(source == nil || isLoading)
                }
            }
        }
        .ignoresSafeArea()
        .navigationTitle(String(localized: "crop.moveAndScale"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Gesture Transaction
    private func commitWithoutAnimation(
        _ changes: () -> Void
    ) {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            changes()
        }
    }

    // MARK: Magnification
    private func magnify(diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, transaction in
                transaction.animation = nil
                state = value.magnification
            }
            .onEnded { value in
                let newZoom = min(
                    max(zoom * value.magnification, 1),
                    maxZoom
                )

                commitWithoutAnimation {
                    zoom = newZoom
                    offset = clamped(
                        offset,
                        zoom: newZoom,
                        diameter: diameter
                    )
                }
            }
    }

    // MARK: Dragging
    private func pan(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .updating($drag) { value, state, transaction in
                transaction.animation = nil
                state = value.translation
            }
            .onEnded { value in
                let proposedOffset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )

                commitWithoutAnimation {
                    offset = clamped(
                        proposedOffset,
                        zoom: zoom,
                        diameter: diameter
                    )
                }
            }
    }

    // MARK: Geometry
    private func baseScale(
        _ image: UIImage,
        diameter: CGFloat
    ) -> CGFloat {
        guard image.size.width > 0,
              image.size.height > 0 else {
            return 1
        }

        return max(
            diameter / image.size.width,
            diameter / image.size.height
        )
    }

    private func clamped(
        _ proposedOffset: CGSize,
        zoom: CGFloat,
        diameter: CGFloat
    ) -> CGSize {
        guard let source,
              source.size.width > 0,
              source.size.height > 0 else {
            return .zero
        }

        let scale = baseScale(
            source,
            diameter: diameter
        ) * zoom

        let maxX = max(
            0,
            (source.size.width * scale - diameter) / 2
        )

        let maxY = max(
            0,
            (source.size.height * scale - diameter) / 2
        )

        return CGSize(
            width: min(
                max(proposedOffset.width, -maxX),
                maxX
            ),
            height: min(
                max(proposedOffset.height, -maxY),
                maxY
            )
        )
    }

    // MARK: Image Loading
    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }

        do {
            var data = try await item.loadTransferable(
                type: Data.self
            )

            if data == nil {
                try? await Task.sleep(for: .milliseconds(200))
                data = try await item.loadTransferable(
                    type: Data.self
                )
            }

            guard let data else {
                loadError = String(localized: "crop.selectedPhoto")
                return
            }

            guard let image = UIImage(data: data) else {
                loadError = String(localized: "crop.notValid")
                return
            }

            let prepared = image.normalized(
                maxDimension: maxSourceDimension
            )

            guard prepared.size.width > 0,
                  prepared.size.height > 0 else {
                loadError = String(localized: "crop.invalidDimension")
                return
            }

            commitWithoutAnimation {
                source = prepared
                zoom = 1
                offset = .zero
            }
        } catch {
            loadError = String(localized: "crop.unableToLoadtryAgain")
        }
    }

    // MARK: Save Cropped Image
    @MainActor
    private func save(diameter: CGFloat) {
        guard let source,
              diameter > 0,
              source.size.width > 0,
              source.size.height > 0 else {
            return
        }

        let scale = baseScale(
            source,
            diameter: diameter
        ) * zoom

        guard scale > 0 else { return }

        let cropSide = diameter / scale

        let origin = CGPoint(
            x: source.size.width / 2
                - (diameter / 2 + offset.width) / scale,
            y: source.size.height / 2
                - (diameter / 2 + offset.height) / scale
        )

        let outputSide = min(
            cropSide,
            outputDimension
        )

        let outputScale = outputSide / cropSide

        let outputSize = CGSize(
            width: outputSide,
            height: outputSide
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(
            size: outputSize,
            format: format
        )

        let result = renderer.image { _ in
            let imageRect = CGRect(
                x: -origin.x * outputScale,
                y: -origin.y * outputScale,
                width: source.size.width * outputScale,
                height: source.size.height * outputScale
            )

            source.draw(in: imageRect)
        }

        croppedImage = result
        dismiss()
    }
}

// MARK: Circular Cutout Shape
private struct CircleCutout: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)

        path.addEllipse(
            in: CGRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
        )

        return path
    }
}

// MARK: Image Normalization
private extension UIImage {
    @MainActor
    func normalized(maxDimension: CGFloat) -> UIImage {
        let originalSize = size

        guard originalSize.width > 0,
              originalSize.height > 0,
              maxDimension > 0 else {
            return self
        }

        let longestSide = max(
            originalSize.width,
            originalSize.height
        )

        let ratio = min(
            1,
            maxDimension / longestSide
        )

        let targetSize = CGSize(
            width: max(
                1,
                (originalSize.width * ratio).rounded()
            ),
            height: max(
                1,
                (originalSize.height * ratio).rounded()
            )
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            draw(
                in: CGRect(
                    origin: .zero,
                    size: targetSize
                )
            )
        }
    }
}
