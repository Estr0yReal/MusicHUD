// DragProbe — Phase 6.2 validation of the window-drag coordinate model.
//
// WHAT IT PROVES
// The app's drag maths, driven by *real* pointer positions read from AppKit and
// applied to a *real* NSWindow, preserves the pointer-to-window offset exactly:
// no accumulation, no jump when the drag threshold is crossed, and correct
// handling of negative deltas.
//
// WHAT IT DOES NOT PROVE
// It does not exercise SwiftUI's gesture delivery — it calls the same
// `WindowDragMath` the modifier calls, with pointer positions obtained the same
// way (`NSEvent.mouseLocation`), but the gesture plumbing itself needs a human
// at the mouse. Stated plainly in the Phase 6.2 report.
//
// Build:
//   swiftc -O tools/DragProbe.swift Sources/MusicHUDCore/Interaction/WindowDragMath.swift \
//          -o build/DragProbe

import AppKit
import CoreGraphics
import Foundation

let threshold: CGFloat = 4

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var failures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 500, y: 400, width: 300, height: 428),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.orderFrontRegardless()
        usleep(400_000)

        run()
        NSApp.terminate(nil)
    }

    private func check(_ label: String, _ condition: Bool, _ detail: String) {
        print("  \(condition ? "PASS" : "FAIL")  \(label)  \(detail)")
        if !condition { failures += 1 }
    }

    /// Drives one gesture from a list of pointer positions and verifies that the
    /// pointer-to-window offset never changes.
    private func gesture(
        name: String,
        path: [CGPoint],
        applyThreshold: Bool
    ) {
        // --- pointer down ---
        let startPointer = NSEvent.mouseLocation
        let initialOrigin = window.frame.origin
        let initialOffset = CGPoint(
            x: startPointer.x - initialOrigin.x,
            y: startPointer.y - initialOrigin.y
        )

        var isDragging = !applyThreshold
        var maxOffsetError: CGFloat = 0
        var firstDraggedOffsetError: CGFloat?
        var jumped = false
        var previousTarget = initialOrigin

        for step in path {
            CGWarpMouseCursorPosition(CGPoint(x: step.x, y: step.y))
            usleep(60_000)

            let pointer = NSEvent.mouseLocation

            if applyThreshold, !isDragging {
                let travel = WindowDragMath.travel(from: startPointer, to: pointer)
                if travel >= threshold {
                    isDragging = true
                    // The first dragged frame must already account for the travel
                    // that happened below the threshold: no snap.
                    let expected = WindowDragMath.origin(
                        initialOrigin: initialOrigin,
                        initialPointer: startPointer,
                        currentPointer: pointer
                    )
                    let jump = hypot(expected.x - previousTarget.x, expected.y - previousTarget.y)
                    jumped = jump > 40
                    firstDraggedOffsetError = abs(
                        (pointer.x - expected.x) - initialOffset.x
                    ) + abs((pointer.y - expected.y) - initialOffset.y)
                } else {
                    continue
                }
            }

            let target = WindowDragMath.origin(
                initialOrigin: initialOrigin,
                initialPointer: startPointer,
                currentPointer: pointer
            )
            window.setFrameOrigin(target)
            previousTarget = target
            usleep(20_000)

            // Re-read the pointer *after* the move: this is the check that the
            // window following the pointer does not disturb the measurement.
            let after = NSEvent.mouseLocation
            let offset = CGPoint(x: after.x - window.frame.origin.x, y: after.y - window.frame.origin.y)
            let error = abs(offset.x - initialOffset.x) + abs(offset.y - initialOffset.y)
            maxOffsetError = max(maxOffsetError, error)
        }

        print("\n[\(name)]  \(path.count) pointer steps")
        check("offset preserved (no accumulation)", maxOffsetError < 0.5,
              String(format: "max error %.3f pt", maxOffsetError))
        if let firstErr = firstDraggedOffsetError {
            check("no jump when the drag begins", !jumped && firstErr < 0.5,
                  String(format: "first dragged frame offset error %.3f pt", firstErr))
        }
        check("window actually moved", window.frame.origin != initialOrigin,
              "origin \(initialOrigin) -> \(window.frame.origin)")
    }

    private func run() {
        let base = window.frame.origin
        let start = CGPoint(x: base.x + 150, y: base.y + 200)

        CGWarpMouseCursorPosition(start)
        usleep(200_000)

        // 1. Horizontal, positive then negative.
        gesture(name: "horizontal + and -", path: [
            CGPoint(x: start.x + 5, y: start.y),
            CGPoint(x: start.x + 30, y: start.y),
            CGPoint(x: start.x + 120, y: start.y),
            CGPoint(x: start.x + 40, y: start.y),
            CGPoint(x: start.x - 60, y: start.y),
        ], applyThreshold: false)

        // 2. Vertical, positive then negative.
        window.setFrameOrigin(base)
        CGWarpMouseCursorPosition(start)
        usleep(200_000)
        gesture(name: "vertical + and -", path: [
            CGPoint(x: start.x, y: start.y + 25),
            CGPoint(x: start.x, y: start.y - 90),
            CGPoint(x: start.x, y: start.y - 10),
        ], applyThreshold: false)

        // 3. Diagonal.
        window.setFrameOrigin(base)
        CGWarpMouseCursorPosition(start)
        usleep(200_000)
        gesture(name: "diagonal", path: [
            CGPoint(x: start.x + 40, y: start.y + 60),
            CGPoint(x: start.x + 170, y: start.y + 130),
            CGPoint(x: start.x - 30, y: start.y - 70),
        ], applyThreshold: false)

        // 4. Through the threshold: 1, 2, 3 pt are below it, then it is crossed.
        window.setFrameOrigin(base)
        CGWarpMouseCursorPosition(start)
        usleep(200_000)
        gesture(name: "crossing the \(Int(threshold))pt threshold", path: [
            CGPoint(x: start.x + 1, y: start.y),
            CGPoint(x: start.x + 2, y: start.y),
            CGPoint(x: start.x + 3, y: start.y),
            CGPoint(x: start.x + 6, y: start.y),
            CGPoint(x: start.x + 90, y: start.y),
        ], applyThreshold: true)

        print("\n\(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")")
    }
}

@main
enum DragProbeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
