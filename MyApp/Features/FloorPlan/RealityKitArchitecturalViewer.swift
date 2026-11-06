import Combine
import RealityKit
import SwiftUI
import UIKit

enum ArchitecturalModelLoadState: Equatable {
    case loading
    case ready
    case failed
}

/// A non-AR RealityKit presentation that leaves the original USDZ untouched.
struct RealityKitArchitecturalViewer: UIViewRepresentable {
    let url: URL
    let resetID: Int
    @Binding var loadState: ArchitecturalModelLoadState

    func makeCoordinator() -> Coordinator {
        Coordinator(loadState: $loadState)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.082, blue: 0.09, alpha: 1)
                : UIColor(red: 0.82, green: 0.81, blue: 0.78, alpha: 1)
        })
        context.coordinator.attach(to: view)
        context.coordinator.load(url)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.load(url)
        }
        if context.coordinator.resetID != resetID {
            context.coordinator.resetID = resetID
            context.coordinator.resetCamera()
        }
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.tearDown()
        view.scene.anchors.removeAll()
    }

    @MainActor
    final class Coordinator: NSObject {
        var url: URL?
        var resetID = 0

        private var loadSubscription: AnyCancellable?
        private weak var view: ARView?
        private var contentAnchor: AnchorEntity?
        private var modelRoot: Entity?
        private var camera: PerspectiveCamera?
        private var initialTransform: Transform?
        private var initialScale: SIMD3<Float> = .one
        private var panStartOrientation: simd_quatf?
        private var pinchStartScale: SIMD3<Float>?
        private var loadState: Binding<ArchitecturalModelLoadState>

        init(loadState: Binding<ArchitecturalModelLoadState>) {
            self.loadState = loadState
        }

        func attach(to view: ARView) {
            self.view = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
            pan.maximumNumberOfTouches = 1
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
        }

        func load(_ url: URL) {
            tearDownScene()
            self.url = url
            loadState.wrappedValue = .loading
            loadSubscription = Entity.loadAsync(contentsOf: url)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    if case .failure = completion {
                        self?.loadState.wrappedValue = .failed
                    }
                } receiveValue: { [weak self] entity in
                    self?.install(entity)
                }
        }

        private func install(_ entity: Entity) {
            guard let view else { return }
            applyPresentationMaterials(to: entity)

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            view.scene.addAnchor(anchor)
            contentAnchor = anchor
            modelRoot = entity

            let bounds = entity.visualBounds(relativeTo: nil)
            guard let framing = ArchitecturalCameraFraming.frame(center: bounds.center, extents: bounds.extents) else {
                loadState.wrappedValue = .failed
                return
            }

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 50
            camera.camera.near = framing.near
            camera.camera.far = framing.far
            camera.look(at: framing.target, from: framing.position, relativeTo: nil)
            anchor.addChild(camera)
            self.camera = camera

            let keyLight = DirectionalLight()
            keyLight.light.intensity = 2_400
            keyLight.look(at: framing.target, from: framing.position + SIMD3<Float>(-1, 2, 1), relativeTo: nil)
            anchor.addChild(keyLight)

            let fillLight = PointLight()
            fillLight.light.intensity = 800
            fillLight.light.attenuationRadius = max(length(bounds.extents) * 3, 5)
            fillLight.position = framing.target + SIMD3<Float>(-2, 2.5, 2)
            anchor.addChild(fillLight)

            initialTransform = entity.transform
            initialScale = entity.scale
            loadState.wrappedValue = .ready
        }

        private func applyPresentationMaterials(to entity: Entity) {
            if let model = entity as? ModelEntity, var component = model.model {
                let isFloor = model.name.localizedCaseInsensitiveContains("floor")
                let color = isFloor
                    ? UIColor(red: 0.42, green: 0.40, blue: 0.36, alpha: 1)
                    : UIColor(red: 0.72, green: 0.70, blue: 0.65, alpha: 1)
                component.materials = component.materials.map { _ in
                    SimpleMaterial(color: color, roughness: isFloor ? 0.92 : 0.8, isMetallic: false)
                }
                model.model = component
            }
            entity.children.forEach(applyPresentationMaterials)
        }

        @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
            guard let root = modelRoot, let view else { return }
            switch gesture.state {
            case .began:
                panStartOrientation = root.orientation
            case .changed:
                let translation = gesture.translation(in: view)
                let yaw = Float(translation.x / max(view.bounds.width, 1)) * .pi * 1.4
                let pitch = Float(translation.y / max(view.bounds.height, 1)) * .pi * 0.45
                let horizontal = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
                let vertical = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
                root.orientation = horizontal * vertical * (panStartOrientation ?? root.orientation)
            default:
                panStartOrientation = nil
            }
        }

        @objc private func didPinch(_ gesture: UIPinchGestureRecognizer) {
            guard let root = modelRoot else { return }
            switch gesture.state {
            case .began:
                pinchStartScale = root.scale
            case .changed:
                let value = min(max(Float(gesture.scale), 0.45), 3.5)
                root.scale = (pinchStartScale ?? initialScale) * value
            default:
                pinchStartScale = nil
            }
        }

        func resetCamera() {
            guard let root = modelRoot, let transform = initialTransform else { return }
            root.transform = transform
        }

        func tearDown() {
            loadSubscription?.cancel()
            loadSubscription = nil
            tearDownScene()
            view = nil
        }

        private func tearDownScene() {
            loadSubscription?.cancel()
            loadSubscription = nil
            contentAnchor?.removeFromParent()
            contentAnchor = nil
            modelRoot = nil
            camera = nil
            initialTransform = nil
        }
    }
}
