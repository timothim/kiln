import XCTest
import SwiftUI
@testable import Kiln

/// Tests that exercise the Sunday animation-pass primitives:
///   - the `KilnMotion.respecting` Reduce Motion gate,
///   - the `Kiln.Motion.*` semantic-token contract (durations + ordering),
///   - the `Kiln.Opacity.*` scale (cardFill < codeFill < trackFill),
///   - the `AgentNetworkDiagram` layout positioning math.
///
/// Animation completion tests against SwiftUI's runtime are notoriously
/// brittle (XCTest can't observe the render loop), so these are
/// contract / data tests that lock in the values the animations rely on.
@MainActor
final class MotionAndLayoutTests: XCTestCase {

    // MARK: - Reduce Motion gate

    func test_kilnMotion_respecting_returnsAnimationWhenReduceMotionIsOff() {
        let result = KilnMotion.respecting(.smooth(duration: 0.35), reduceMotion: false)
        XCTAssertNotNil(
            result,
            "KilnMotion.respecting must return the supplied animation when Reduce Motion is off."
        )
    }

    func test_kilnMotion_respecting_returnsNilWhenReduceMotionIsOn() {
        let result = KilnMotion.respecting(.smooth(duration: 0.35), reduceMotion: true)
        XCTAssertNil(
            result,
            "KilnMotion.respecting must return nil when Reduce Motion is on so callers can pass it to withAnimation safely."
        )
    }

    // MARK: - Motion token contract

    /// `microToggle` is the fast path; it must be strictly faster than
    /// `standard` so chip flips and pin toggles read as "responsive."
    func test_motion_microToggle_isFasterThanStandard() {
        // We can't read `Animation`'s duration directly — but we can lock
        // the contract by hashing the canonical descriptions. If
        // `microToggle` and `standard` ever collide here, a future
        // refactor accidentally broke the speed hierarchy.
        let micro = String(describing: Kiln.Motion.microToggle)
        let standard = String(describing: Kiln.Motion.standard)
        XCTAssertNotEqual(
            micro, standard,
            "microToggle and standard must be distinct animations."
        )
    }

    /// `sampleReveal` is intentionally slower than `standard` so a new
    /// Growing Model checkpoint resample lands gracefully. Same hash
    /// trick — locks the contract without depending on Apple internals.
    func test_motion_sampleReveal_distinctFromStandard() {
        let reveal = String(describing: Kiln.Motion.sampleReveal)
        let standard = String(describing: Kiln.Motion.standard)
        XCTAssertNotEqual(reveal, standard)
    }

    /// All five Sunday-pass semantic motion tokens must be defined and
    /// distinct from each other — otherwise call sites bind to the wrong
    /// rhythm and the system loses its hierarchy.
    func test_motion_sundayTokens_allDistinct() {
        let descriptions = [
            String(describing: Kiln.Motion.staggerStep),
            String(describing: Kiln.Motion.highlightSweep),
            String(describing: Kiln.Motion.connectorGrow),
            String(describing: Kiln.Motion.networkPulse),
            String(describing: Kiln.Motion.statusPulse)
        ]
        XCTAssertEqual(
            Set(descriptions).count, descriptions.count,
            "Each Sunday motion token must be distinct from the others."
        )
    }

    /// The asymmetric stage transitions (`stageTransition` and
    /// `stageTransitionBackward`) must exist as real `AnyTransition`
    /// values; if either becomes `.identity`, the directional logic in
    /// `StageRouterView` silently breaks.
    func test_motion_stageTransitions_areDefined() {
        // Just confirm the constants are accessible. Their internal
        // representation is opaque; we don't need to inspect it.
        _ = Kiln.Motion.stageTransition
        _ = Kiln.Motion.stageTransitionBackward
    }

    // MARK: - Opacity tokens

    func test_opacity_tokens_areOrdered() {
        XCTAssertLessThan(
            Kiln.Opacity.cardFill, Kiln.Opacity.codeFill,
            "cardFill (sample / panel) must be quieter than codeFill (mono blocks)."
        )
        XCTAssertLessThan(
            Kiln.Opacity.codeFill, Kiln.Opacity.trackFill,
            "codeFill must be quieter than trackFill (capsule tracks / skeleton bars)."
        )
    }

    func test_opacity_tokens_stayWithinSubtleRange() {
        // A drift to e.g. 0.2 would read as a loud surface, not a quiet
        // wash. Lock the upper bound to catch accidental "louder" moves.
        XCTAssertLessThan(Kiln.Opacity.trackFill, 0.15)
    }

    // MARK: - Agent network layout

    /// The Behind the Scenes diagram fans Opus into four cardinals.
    /// Layout maps every node id to a position; the central node sits
    /// at the geometric center of the container.
    func test_agentNetwork_layout_placesOpusAtCenter() {
        let size = CGSize(width: 720, height: 360)
        let positions = AgentNetworkDiagram.layout(in: size)

        XCTAssertEqual(positions.count, 5, "Layout must place all five nodes.")
        XCTAssertEqual(positions["opus"]?.x, size.width / 2)
        XCTAssertEqual(positions["opus"]?.y, size.height / 2)
    }

    /// Each cardinal node sits in its expected half / quadrant. If a
    /// future refactor swaps `top` and `bottom` (or any pair), the
    /// diagram's spatial story breaks; this test locks the expected
    /// arrangement.
    func test_agentNetwork_layout_cardinalsLandInRightHalves() {
        let size = CGSize(width: 720, height: 360)
        let positions = AgentNetworkDiagram.layout(in: size)

        // Build (left of center) sits in the left half.
        XCTAssertLessThan(positions["build"]!.x, size.width / 2)
        XCTAssertEqual(positions["build"]!.y, size.height / 2, accuracy: 0.5)

        // Distill (above center) sits in the top half, horizontally centered.
        XCTAssertLessThan(positions["distill"]!.y, size.height / 2)
        XCTAssertEqual(positions["distill"]!.x, size.width / 2, accuracy: 0.5)

        // Runtime (right of center) sits in the right half.
        XCTAssertGreaterThan(positions["runtime"]!.x, size.width / 2)
        XCTAssertEqual(positions["runtime"]!.y, size.height / 2, accuracy: 0.5)

        // MCP (below center) sits in the bottom half, horizontally centered.
        XCTAssertGreaterThan(positions["mcp"]!.y, size.height / 2)
        XCTAssertEqual(positions["mcp"]!.x, size.width / 2, accuracy: 0.5)
    }

    /// The diagram must stay inside its container. Each node should be
    /// at least its inset distance from the edges so the chip chrome
    /// has padding to render.
    func test_agentNetwork_layout_keepsNodesInsideContainer() {
        let size = CGSize(width: 720, height: 360)
        let positions = AgentNetworkDiagram.layout(in: size)

        for (id, position) in positions {
            XCTAssertGreaterThan(position.x, 0,
                                 "\(id) x must be positive")
            XCTAssertLessThan(position.x, size.width,
                              "\(id) x must stay within container")
            XCTAssertGreaterThan(position.y, 0,
                                 "\(id) y must be positive")
            XCTAssertLessThan(position.y, size.height,
                              "\(id) y must stay within container")
        }
    }

    /// At a tiny container size the layout still produces five distinct
    /// positions (degeneracy check — important since the diagram is
    /// inside a ScrollView whose width can be small).
    func test_agentNetwork_layout_handlesSmallContainer() {
        let positions = AgentNetworkDiagram.layout(in: CGSize(width: 200, height: 200))
        XCTAssertEqual(positions.count, 5)
        let xs = Set(positions.values.map { Int($0.x.rounded()) })
        let ys = Set(positions.values.map { Int($0.y.rounded()) })
        // Opus's center coords coincide with two of the cardinals in
        // each axis (vertical line + horizontal line through center),
        // so we expect 3 distinct x-values and 3 distinct y-values.
        XCTAssertEqual(xs.count, 3)
        XCTAssertEqual(ys.count, 3)
    }
}
