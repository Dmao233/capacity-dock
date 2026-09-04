import CoreGraphics
import Testing
@testable import CapacityDock

@Suite("Capacity Dock motion")
struct CapacityDockMotionTests {
    @Test("rail and bubble durations stay mac-like and vanish under Reduce Motion")
    func durations() {
        #expect(CapacityDockMotion.duration(for: .railExpand) == 0.52)
        #expect(CapacityDockMotion.duration(for: .railCollapse) == 0.44)
        #expect(CapacityDockMotion.duration(for: .dockAttach) == 0.28)
        #expect(CapacityDockMotion.duration(for: .dockDetach) == 0.24)
        #expect(CapacityDockMotion.duration(for: .detailPresent) == 0.20)
        #expect(CapacityDockMotion.duration(for: .detailFollow) == 0.16)
        #expect(CapacityDockMotion.duration(for: .detailDismiss) == 0.14)
        #expect(CapacityDockMotion.duration(for: .preferredReorder) == 0.35)
        #expect(CapacityDockMotion.duration(for: .immediate) == 0)

        for transaction in [
            CapacityDockMotion.Transaction.railExpand,
            .railCollapse,
            .dockAttach,
            .dockDetach,
            .detailPresent,
            .detailFollow,
            .detailDismiss,
            .preferredReorder,
            .immediate,
        ] {
            #expect(CapacityDockMotion.duration(for: transaction, reduceMotion: true) == 0)
            #expect(!CapacityDockMotion.shouldAnimate(transaction, reduceMotion: true))
        }

        #expect(CapacityDockMotion.shouldAnimate(.railExpand))
        #expect(!CapacityDockMotion.shouldAnimate(.immediate))
    }

    @Test("hover intent is quick to open and forgiving to leave")
    func hoverIntentTiming() {
        #expect(CapacityDockMotion.railHoverOpenDelay == 0.08)
        #expect(CapacityDockMotion.railHoverCloseDelay == 0.18)
    }

    @Test("either rail axis picks expand, collapse, attach, or an atomic update")
    func railTransactionFromHeight() {
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 88, height: 100),
            toFrame: CGRect(x: 0, y: 0, width: 88, height: 100),
            attachmentFrom: 0,
            attachmentTo: 0
        ) == .immediate)
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 88, height: 100),
            toFrame: CGRect(x: 0, y: 0, width: 88, height: 360),
            attachmentFrom: 0,
            attachmentTo: 0
        ) == .railExpand)
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 88, height: 360),
            toFrame: CGRect(x: 0, y: 0, width: 88, height: 100),
            attachmentFrom: 0,
            attachmentTo: 0
        ) == .railCollapse)
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 88, height: 100),
            toFrame: CGRect(x: 0, y: 0, width: 110, height: 100),
            attachmentFrom: 0,
            attachmentTo: 1
        ) == .dockAttach)
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 110, height: 100),
            toFrame: CGRect(x: 0, y: 0, width: 88, height: 100),
            attachmentFrom: 1,
            attachmentTo: 0
        ) == .dockDetach)
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 100, height: 88),
            toFrame: CGRect(x: 0, y: 0, width: 360, height: 88),
            attachmentFrom: 1,
            attachmentTo: 1
        ) == .railExpand)
        #expect(CapacityDockMotion.railTransaction(
            fromFrame: CGRect(x: 0, y: 0, width: 360, height: 88),
            toFrame: CGRect(x: 0, y: 0, width: 100, height: 88),
            attachmentFrom: 1,
            attachmentTo: 1
        ) == .railCollapse)
    }

    @Test("bubble presentation slides out from the rail and dismisses back toward it")
    func detailOffsets() {
        let target = CGRect(x: 1042, y: 600, width: 300, height: 200)
        let start = CapacityDockMotion.detailPresentationStartFrame(from: target, side: .left)
        let dismiss = CapacityDockMotion.detailDismissalFrame(from: target, side: .left)

        #expect(start.size == target.size)
        #expect(start.minY == target.minY)
        #expect(start.minX == target.minX + 10)
        #expect(dismiss.minX > target.minX)
        #expect(dismiss.minX < start.minX)
        #expect(dismiss.size == target.size)

        let topStart = CapacityDockMotion.detailPresentationStartFrame(from: target, side: .top)
        let bottomStart = CapacityDockMotion.detailPresentationStartFrame(from: target, side: .bottom)
        #expect(topStart.minY < target.minY)
        #expect(bottomStart.minY > target.minY)
    }

    @Test("timing curves stay in a cubic-bezier range and linearize immediate updates")
    func timingControlPoints() {
        let immediate = CapacityDockMotion.timingControlPoints(for: .immediate)
        #expect(immediate == (0, 0, 1, 1))
        #expect(CapacityDockMotion.timingControlPoints(for: .railExpand) == (0.22, 1, 0.36, 1))
        #expect(CapacityDockMotion.timingControlPoints(for: .railCollapse) == (0.32, 0, 0.2, 1))

        for transaction in [
            CapacityDockMotion.Transaction.railExpand,
            .railCollapse,
            .dockAttach,
            .dockDetach,
            .detailPresent,
            .detailFollow,
            .detailDismiss,
            .preferredReorder,
        ] {
            let points = CapacityDockMotion.timingControlPoints(for: transaction)
            for value in [points.0, points.1, points.2, points.3] {
                #expect(value >= 0)
                #expect(value <= 1)
            }
        }
    }

    @Test("attachment interpolation keeps every physical edge stationary")
    func attachedEdgeInterpolation() {
        let from = CGRect(x: 10, y: 20, width: 88, height: 100)
        let targets: [(CapacityDockEdge, CGRect)] = [
            (.left, CGRect(x: 0, y: 20, width: 110, height: 100)),
            (.right, CGRect(x: 1330, y: 20, width: 110, height: 100)),
            (.top, CGRect(x: 10, y: 790, width: 100, height: 110)),
            (.bottom, CGRect(x: 10, y: 0, width: 100, height: 110)),
        ]

        for (edge, target) in targets {
            let mid = CapacityDockMotion.interpolateAttachedEdge(
                from: from,
                to: target,
                edge: edge,
                progress: 0.5
            )
            switch edge {
            case .left: #expect(mid.minX == 5)
            case .right: #expect(mid.maxX == (from.maxX + target.maxX) / 2)
            case .top: #expect(mid.maxY == (from.maxY + target.maxY) / 2)
            case .bottom: #expect(mid.minY == 10)
            }
        }
    }

    @Test("center-anchored collapse keeps the preferred ring on screen")
    func centerAnchoredCollapseKeepsPreferred() {
        let expandedPreferredAlong: CGFloat = 150
        let restPreferredAlong: CGFloat = 20
        let preferredY: CGFloat = 650
        let from = CGRect(x: 1330, y: preferredY - (300 - expandedPreferredAlong), width: 72, height: 300)
        let to = CGRect(x: 1330, y: preferredY - (100 - restPreferredAlong), width: 72, height: 100)
        #expect(from.maxY - expandedPreferredAlong == preferredY)
        #expect(to.maxY - restPreferredAlong == preferredY)

        for progress: CGFloat in [0, 0.2, 0.5, 0.8, 1] {
            let frame = CapacityDockMotion.interpolateAttachedEdge(
                from: from,
                to: to,
                edge: .right,
                expansionAnchor: .center,
                progress: progress
            )
            let preferredAlong = expandedPreferredAlong
                + (restPreferredAlong - expandedPreferredAlong) * progress
            #expect(abs((frame.maxY - preferredAlong) - preferredY) < 0.000_001)
            #expect(frame.maxX == from.maxX)
        }
    }

    @Test("floating center anchors lock the preferred ring, not the window midpoint")
    func floatingLayoutAnchors() {
        let frame = CGRect(x: 500.25, y: 300.25, width: 112, height: 88)
        let preferredY: CGFloat = 640
        let verticalCenter = CapacityDockMotion.floatingRailAnchors(
            frame: frame,
            preservedTop: 420.5,
            isVertical: true,
            expansionAnchor: .center,
            preferredAxisCoordinate: preferredY
        )
        #expect(verticalCenter.top == nil)
        #expect(verticalCenter.leading == frame.minX)
        #expect(verticalCenter.axisCoordinate == preferredY)
        #expect(verticalCenter.axisCoordinate != frame.midY)

        let preferredX: CGFloat = 512
        let horizontalCenter = CapacityDockMotion.floatingRailAnchors(
            frame: frame,
            preservedTop: 420.5,
            isVertical: false,
            expansionAnchor: .center,
            preferredAxisCoordinate: preferredX
        )
        #expect(horizontalCenter.leading == nil)
        #expect(horizontalCenter.axisCoordinate == preferredX)
        #expect(horizontalCenter.axisCoordinate != frame.midX)
    }

    @Test("floating center collapse keeps the preferred ring on screen")
    func floatingCenterCollapseKeepsPreferred() {
        let expandedPreferredAlong: CGFloat = 82
        let restPreferredAlong: CGFloat = 10
        let preferredY: CGFloat = 520
        let from = CGRect(
            x: 640,
            y: preferredY - (278 - expandedPreferredAlong),
            width: 72,
            height: 278
        )
        let to = CGRect(
            x: 640,
            y: preferredY - (134 - restPreferredAlong),
            width: 72,
            height: 134
        )
        #expect(from.maxY - expandedPreferredAlong == preferredY)
        #expect(to.maxY - restPreferredAlong == preferredY)

        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchored = CapacityDockPlacement.railFrame(
            screenFrame: visible,
            visibleFrame: visible,
            size: to.size,
            dockedEdge: nil,
            normalizedHorizontalOffset: nil,
            normalizedTopOffset: nil,
            anchoredLeading: from.minX,
            anchoredAxisCoordinate: preferredY,
            expansionAnchor: .center,
            anchorAlongOffset: restPreferredAlong
        )
        #expect(abs((anchored.maxY - restPreferredAlong) - preferredY) < 0.000_001)
        #expect(anchored.minX == from.minX)

        for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            let frame = CapacityDockMotion.interpolateRail(
                from: from,
                to: to,
                dockedEdge: nil,
                expansionAnchor: .center,
                progress: progress
            )
            let preferredAlong = expandedPreferredAlong
                + (restPreferredAlong - expandedPreferredAlong) * progress
            #expect(abs((frame.maxY - preferredAlong) - preferredY) < 0.000_001)
            #expect(frame.minX == from.minX)
        }
    }

    @Test("rail frames land on backing pixels without releasing their visual anchor")
    func railFramesAlignToBackingPixels() {
        let floating = CapacityDockMotion.pixelAlignedRailFrame(
            CGRect(x: 640.13, y: 500.08, width: 88.17, height: 112.19),
            backingScale: 2,
            dockedEdge: nil,
            expansionAnchor: .center
        )
        #expect(floating.minX == 640)
        #expect(floating.minY == 500)
        #expect(floating.width == 88)
        #expect(floating.height == 112)

        let attached = CapacityDockMotion.pixelAlignedRailFrame(
            CGRect(x: 1330.08, y: 499.94, width: 109.87, height: 112.19),
            backingScale: 2,
            dockedEdge: .right,
            expansionAnchor: .center
        )
        #expect(attached.maxX == 1440)
        #expect(attached.minY == 500)
        #expect(attached.width == 110)
        #expect(attached.height == 112)
    }

    @Test("pixel-aligned reveal progress follows the frame instead of the timer")
    func alignedRevealProgressFollowsFrame() {
        let from = CGRect(x: 640.13, y: 500.08, width: 88.17, height: 112.19)
        let to = CGRect(x: 640.13, y: 224.08, width: 88.17, height: 388.19)

        let firstRaw = CapacityDockMotion.interpolateRail(
            from: from,
            to: to,
            dockedEdge: nil,
            expansionAnchor: .center,
            progress: 0.4001
        )
        let secondRaw = CapacityDockMotion.interpolateRail(
            from: from,
            to: to,
            dockedEdge: nil,
            expansionAnchor: .center,
            progress: 0.4002
        )
        let first = CapacityDockMotion.alignedRailSample(
            firstRaw,
            fromFrame: from,
            toFrame: to,
            fromPresentationProgress: 0,
            toPresentationProgress: 1,
            backingScale: 2,
            dockedEdge: nil,
            expansionAnchor: .center,
            isVertical: true
        )
        let second = CapacityDockMotion.alignedRailSample(
            secondRaw,
            fromFrame: from,
            toFrame: to,
            fromPresentationProgress: 0,
            toPresentationProgress: 1,
            backingScale: 2,
            dockedEdge: nil,
            expansionAnchor: .center,
            isVertical: true
        )

        #expect(first.frame == second.frame)
        #expect(first.presentationProgress == second.presentationProgress)
        #expect(abs(first.frame.height - (112 + 276 * first.presentationProgress)) < 0.000_001)
    }

    @Test("immediate easing is linear and other curves stay bounded")
    func easedProgressBounds() {
        #expect(CapacityDockMotion.easedProgress(for: .immediate, linear: 0.37) == 0.37)
        #expect(CapacityDockMotion.easedProgress(for: .railExpand, linear: 0) == 0)
        #expect(CapacityDockMotion.easedProgress(for: .railExpand, linear: 1) == 1)

        let mid = CapacityDockMotion.easedProgress(for: .railExpand, linear: 0.5)
        #expect(mid > 0)
        #expect(mid < 1)
        #expect(CapacityDockMotion.easedProgress(for: .railExpand, linear: 0.25) > 0.5)
    }
}
