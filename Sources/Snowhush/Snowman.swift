import Foundation
import simd

/// Uniforms passed to Metal for a single snowman, partial stack, or snowball in hand.
/// All fields are `SIMD4<Float>` so Swift and Metal share identical 16-byte alignment.
struct SnowmanUniforms {
    /// `(anchor.x, anchor.y, groundY, facing)`
    var anchorAndMeta: SIMD4<Float>
    /// `(r0, r1, r2, snapRingAlpha)`
    var radii: SIMD4<Float>
    /// `(seed, wobble, wave, pop)`
    var params: SIMD4<Float>
    /// `(age, scale, alpha, isBallOnly)`
    var state: SIMD4<Float>
    /// `(minX, minY, maxX, maxY)` in overlay world coordinates
    var bounds: SIMD4<Float>
}

/// Everything the renderer needs to draw a snowman or snowball with proper window occlusion.
struct SnowmanSprite {
    var uniforms: SnowmanUniforms
    var occluders: [SIMD4<Float>]
}

/// A snowman (or 1-ball / 2-ball stack in progress) anchored on a snow layer.
struct Snowman {
    let id = UUID()
    var layer: SnowLayer
    /// Offset along `layer.base.x`.
    var x: Float
    /// 1 to 3 ball radii from bottom to top.
    var balls: [Float]
    let seed: Float
    var facing: Float
    var age: Float = 0
    var wobble: Float = 0
    var wobbleVel: Float = 0
    var waveAt: Float = -10
    var pop: Float = 1
    var meltScale: Float = 1
    var snowTaken: Float
    var snapHighlight: Float = 0

    var isComplete: Bool { balls.count >= 3 }

    /// World position of the base contact point on the snow surface.
    func anchor() -> (ground: Float, origin: SIMD2<Float>) {
        let col = layer.clampedIndex(at: layer.base.x + x)
        let surface = layer.surface(col)
        return (surface, SIMD2(layer.base.x + x, surface))
    }

    /// Relative ball centers from `anchor`, matching the Metal shader layout.
    func ballCenters(scale: Float? = nil) -> [(center: SIMD2<Float>, radius: Float)] {
        let s = scale ?? meltScale
        guard !balls.isEmpty else { return [] }
        var result: [(SIMD2<Float>, Float)] = []
        let r0 = balls[0] * s
        let c0 = SIMD2<Float>(0, r0 * 0.82)
        result.append((c0, r0))
        if balls.count >= 2 {
            let r1 = balls[1] * s
            let c1 = SIMD2<Float>(0, c0.y + r0 * 0.74 + r1 * 0.74)
            result.append((c1, r1))
        }
        if balls.count >= 3 {
            let r2 = balls[2] * s
            let c1 = result[1].0
            let r1 = result[1].1
            let c2 = SIMD2<Float>(0, c1.y + r1 * 0.74 + r2 * 0.74)
            result.append((c2, r2))
        }
        return result
    }

    /// World-space centers of the balls.
    func worldBalls() -> [(center: SIMD2<Float>, radius: Float)] {
        let base = anchor().origin
        return ballCenters().map { (base + $0.center, $0.radius) }
    }

    /// Where the next ball should snap if stacked onto this incomplete snowman.
    func nextSnapCenter(for incomingRadius: Float) -> SIMD2<Float>? {
        guard balls.count < 3, let top = worldBalls().last else { return nil }
        let clamped = Self.clampedStackedRadius(incomingRadius, onto: top.radius)
        return SIMD2(top.center.x, top.center.y + top.radius * 0.74 + clamped * 0.74)
    }

    static func clampedStackedRadius(_ incoming: Float, onto below: Float) -> Float {
        let minR = max(8, below * 0.45)
        let maxR = max(minR, below * 0.94)
        return min(max(incoming, minR), maxR)
    }

    func contains(_ point: SIMD2<Float>, padding: Float = 6) -> Bool {
        for (center, radius) in worldBalls() {
            if simd_distance(point, center) <= radius + padding { return true }
        }
        return false
    }

    var waveWeight: Float {
        let since = age - waveAt
        guard since >= 0, since < 2.6 else { return 0 }
        let fadeIn = min(max(since / 0.25, 0), 1)
        let fadeOut = 1 - min(max((since - 2.1) / 0.5, 0), 1)
        return fadeIn * fadeOut
    }

    func sprite(dragOffset: SIMD2<Float>? = nil) -> SnowmanSprite {
        let (ground, origin) = anchor()
        let centerOrigin = dragOffset.map { origin + $0 } ?? origin
        let r0 = balls.count > 0 ? balls[0] : 0
        let r1 = balls.count > 1 ? balls[1] : 0
        let r2 = balls.count > 2 ? balls[2] : 0
        let s = meltScale
        let maxR = max(r0, max(r1, r2)) * s
        let topR = (r2 > 0 ? r2 : r1 > 0 ? r1 : r0) * s
        let previewExtra: Float = (r2 == 0 && snapHighlight > 0) ? max(10, topR * 0.78) * 2.1 : 0
        let totalHeight = (r0 * 1.56 + (r1 > 0 ? r1 * 1.48 : 0) + (r2 > 0 ? r2 * 2.35 : 0)) * s + previewExtra + 28
        let halfW = max(maxR * 2.5, r1 * s * 2.6) + 26
        let minY = centerOrigin.y - max(r0 * s * 0.35, 10)
        let bounds = SIMD4<Float>(
            centerOrigin.x - halfW,
            minY,
            centerOrigin.x + halfW,
            centerOrigin.y + totalHeight
        )
        let uniforms = SnowmanUniforms(
            anchorAndMeta: SIMD4(centerOrigin.x, centerOrigin.y, dragOffset == nil ? ground : centerOrigin.y - 100, facing),
            radii: SIMD4(r0, r1, r2, snapHighlight),
            params: SIMD4(seed, wobble, waveWeight, pop),
            state: SIMD4(age, s, 1, 0),
            bounds: bounds
        )
        return SnowmanSprite(uniforms: uniforms, occluders: dragOffset == nil ? layer.occluders : [])
    }
}

/// A snowball released from the cursor that is flying or dropping toward a surface or snowman.
struct ThrownSnowball {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var radius: Float
    var area: Float
    var seed: Float
    var age: Float = 0
    /// True if dropped gently rather than flung; gentle drops settle into snowman bases.
    var gentle: Bool
}

/// Active sculpting state while the user holds the mouse button down.
struct SculptHand {
    var position: SIMD2<Float>
    var lastPosition: SIMD2<Float>
    var radius: Float
    var area: Float
    var seed: Float
    var snapTargetID: UUID?
    var snapPosition: SIMD2<Float>?
    var draggingSnowmanID: UUID?
    var tapStart: SIMD2<Float>
    var didDrag: Bool = false
    var dragOffset: SIMD2<Float> = .zero
    var lastVelocity: SIMD2<Float> = .zero
}
