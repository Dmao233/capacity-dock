import AppKit
import Observation
import SwiftUI

private extension Color {
    /// Warm off-white for Capacity Dock text: a very mild orange tint so bright
    /// labels on the dark card read softer than pure white and do not stress the eyes.
    static let capacityDockText = Color(red: 0.98, green: 0.95, blue: 0.90)
}

enum CapacityDockMetrics {
    // Codenotch side-notch: a solid black blob flush to the screen edge,
    // rings inside, settings orb revealed with the expand animation.
    private static let baseRailWidth: CGFloat = 72
    private static let baseHorizontalRailWidth: CGFloat = 78
    private static let baseEdgeShoulderDepth: CGFloat = 72
    private static let baseRowHeight: CGFloat = 62
    private static let baseRowSpacing: CGFloat = 10
    private static let baseRailAlongPad: CGFloat = 10
    private static let baseRailCrossPad: CGFloat = 14
    private static let baseRingSize: CGFloat = 44
    private static let baseRingStrokeWidth: CGFloat = 3
    private static let baseRingLabelSpacing: CGFloat = 4
    private static let baseProviderIconSize: CGFloat = 20
    private static let basePercentageTextSize: CGFloat = 12
    private static let baseDetailWidth: CGFloat = 280
    private static let baseSettingsCapGap: CGFloat = 2
    /// Extra panel past the tail so the nested settings orb can peek out of the scoop.
    private static let baseSettingsCapPeek: CGFloat = 12
    private static let baseSettingsCapDetachedGap: CGFloat = 8

    /// Every dock dimension lands on a whole point. Fractional sizes (85%
    /// of 88 is 74.8) made SwiftUI's fitted content disagree with the
    /// pixel-aligned panel frame on every layout pass, so the hosting view
    /// re-laid itself out at display cadence forever: 5 to 7 percent idle CPU
    /// at any scale except 100%.
    private static func points(_ base: CGFloat, _ scale: CGFloat) -> CGFloat {
        if base <= 0 { return 0 }
        return max(1, (base * scale).rounded())
    }

    static func railWidth(scale: CGFloat) -> CGFloat { points(baseRailWidth, scale) }
    static func horizontalRailWidth(scale: CGFloat) -> CGFloat { points(baseHorizontalRailWidth, scale) }
    static func edgeShoulderDepth(scale: CGFloat) -> CGFloat { points(baseEdgeShoulderDepth, scale) }
    static func rowHeight(scale: CGFloat) -> CGFloat { points(baseRowHeight, scale) }
    static func rowSpacing(scale: CGFloat) -> CGFloat { points(baseRowSpacing, scale) }
    static func railAlongPad(scale: CGFloat) -> CGFloat { points(baseRailAlongPad, scale) }
    static func railCrossPad(scale: CGFloat) -> CGFloat { points(baseRailCrossPad, scale) }
    static func ringSize(scale: CGFloat) -> CGFloat { points(baseRingSize, scale) }
    static func ringStrokeWidth(scale: CGFloat) -> CGFloat { points(baseRingStrokeWidth, scale) }
    static func ringLabelSpacing(scale: CGFloat) -> CGFloat { points(baseRingLabelSpacing, scale) }
    static func providerIconSize(scale: CGFloat) -> CGFloat { points(baseProviderIconSize, scale) }
    static func percentageTextSize(scale: CGFloat) -> CGFloat { points(basePercentageTextSize, scale) }
    static func detailWidth(scale: CGFloat) -> CGFloat { points(baseDetailWidth, scale) }
    static func settingsCapGap(scale: CGFloat) -> CGFloat { points(baseSettingsCapGap, scale) }
    static func settingsCapDetachedGap(scale: CGFloat) -> CGFloat {
        points(baseSettingsCapDetachedGap, scale)
    }
    static func settingsCapOrbSize(scale: CGFloat) -> CGFloat { ringSize(scale: scale) }
    static func settingsCapSlot(scale: CGFloat) -> CGFloat {
        points(baseSettingsCapPeek, scale)
    }
    static func settingsCapDetachedSlot(scale: CGFloat) -> CGFloat {
        settingsCapDetachedGap(scale: scale) + settingsCapOrbSize(scale: scale)
    }

    static func hoverEmphasisTravel(scale: CGFloat) -> CGFloat {
        points(CapacityDockMotion.hoverEmphasisTravel, scale)
    }

    static func railHeight(providerCount: Int, alongPad: CGFloat, scale: CGFloat) -> CGFloat {
        let count = max(providerCount, 1)
        return alongPad
            + CGFloat(count) * rowHeight(scale: scale)
            + CGFloat(max(0, count - 1)) * rowSpacing(scale: scale)
            + alongPad
    }

    static func detailHeight(
        quota: QuotaSummary?,
        activeTaskCount: Int = 0,
        scale: CGFloat
    ) -> CGFloat {
        guard let quota else { return 186 * scale }
        let rows = min(max(quota.details.count, quota.primary == nil ? 0 : 1), 5)
        let visibleFooter = CapacityDockQuotaPresentation.visibleFooterLines(
            quota.footerLines,
            connection: quota.connection
        )
        let footer = visibleFooter.isEmpty ? 0 : min(visibleFooter.count, 2) * 16 + 4
        let actionExtra: CGFloat = CapacityDockConnectionAction.resolve(quota: quota) == nil ? 0 : 38
        let connectionExtra: CGFloat = switch quota.connection {
        case .terminalFailure: 90
        case .disconnected: 18
        case .loading, .stale, .transientFailure: 16
        case .connected: 0
        }
        let taskCount = min(max(activeTaskCount, 0), CapacityDockActiveTaskSnapshot.maxTasks)
        let taskExtra: CGFloat = taskCount == 0 ? 0 : 10 + CGFloat(taskCount) * 18
        let base = min(
            470,
            max(132, 88 + CGFloat(rows) * 62 + CGFloat(footer) + actionExtra + connectionExtra + taskExtra)
        )
        return base * scale
    }
}

@MainActor
@Observable
final class CapacityDockViewModel {
    var preferences: CapacityDockPreferences.Snapshot
    var interaction = CapacityDockInteractionState()
    var hoveredProvider: CapacityDockProvider?
    var highlightedProvider: CapacityDockProvider?
    var activeTasks: [CapacityDockActiveTask] = []
    var detailHeight: CGFloat = 164
    var isRailPresentationExpanded = false
    var railPresentationProgress: CGFloat = 0
    var isRailMotionActive = false
    var hidesExtraIcons = false
    var extraIconRevealSettled = false
    var dockedEdge: CapacityDockEdge?
    var attachmentEdge: CapacityDockEdge
    var attachmentProgress: CGFloat
    var detailTailEdge: CapacityDockEdge = .right
    var detailTailPosition: CGFloat = 0.5
    var expansionAnchor: CapacityDockExpansionAnchor = .center
    var settingsCapProgress: CGFloat = 0
    var quotaEpoch: Int = 0

    init(preferences: CapacityDockPreferences.Snapshot) {
        self.preferences = preferences
        self.dockedEdge = preferences.dockedEdge
        self.attachmentEdge = preferences.attachmentEdge
        self.attachmentProgress = preferences.dockedEdge == nil ? 0 : 1
    }

    var displayedProviders: [CapacityDockProvider] {
        guard showsAllProviders else { return [preferences.preferredProvider] }
        let preferred = preferences.preferredProvider
        let others = preferences.selectedProviders.filter { $0 != preferred }
        let above = others.count / 2
        return Array(others.prefix(above)) + [preferred] + Array(others.dropFirst(above))
    }

    var preferredItemIndex: Int {
        displayedProviders.firstIndex(of: preferences.preferredProvider) ?? 0
    }

    /// Distance from the body start (top / leading) to the preferred row.
    /// Interpolates so the preferred ring stays on screen while extra rows
    /// grow both ways.
    func preferredAlongOffset(
        itemCount: Int? = nil,
        progress: CGFloat? = nil,
        bodyLength: CGFloat? = nil
    ) -> CGFloat {
        let count = itemCount ?? displayedRailItems.count
        let others = max(preferences.selectedProviders.count - 1, 0)
        let index = count <= 1 ? 0 : min(others / 2, count - 1)
        let rest = railAlongPad
        let expanded = railAlongPad + CGFloat(index) * (rowHeight + rowSpacing)
        let t: CGFloat
        if let bodyLength {
            let delta = expandedBodyLength - restingBodyLength
            t = abs(delta) < 0.000_001
                ? 1
                : min(max((bodyLength - restingBodyLength) / delta, 0), 1)
        } else if preferences.keepExpanded {
            t = 1
        } else {
            t = progress ?? min(max(railPresentationProgress, 0), 1)
        }
        return rest + (expanded - rest) * t
    }

    var showsAllProviders: Bool {
        preferences.keepExpanded || isRailPresentationExpanded
    }

    var wantsExpandedRail: Bool {
        preferences.keepExpanded || interaction.isExpanded
    }

    /// Resting notch is the pinned ring only. Expansion reveals the other
    /// rings; settings lives on the external cap, not inside the blob.
    var displayedRailItems: [CapacityDockRailItem] {
        displayedProviders.map(CapacityDockRailItem.provider)
    }

    var railShape: CapacityDockRailShape {
        CapacityDockRailShape(
            bodyWidth: railWidth,
            bodyLength: bodyLength,
            restLength: restingBodyLength,
            shoulderDepth: CapacityDockMetrics.edgeShoulderDepth(scale: scale),
            attachmentProgress: attachmentProgress,
            edge: attachmentEdge
        )
    }

    var scoopContactRadius: CGFloat {
        CapacityDockRailShape.contactRadius(
            bodyWidth: railWidth,
            restLength: restingBodyLength,
            shoulderDepth: CapacityDockMetrics.edgeShoulderDepth(scale: scale),
            attachmentProgress: attachmentProgress
        )
    }

    func orbFrames(in bounds: CGRect) -> [CGRect] {
        let body = notchBodyFrame(in: bounds)
        let frames = CapacityDockOrbStack.itemFrames(
            in: CGRect(origin: .zero, size: body.size),
            itemCount: displayedRailItems.count,
            isVertical: isVertical,
            expansionAnchor: expansionAnchor,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            alongPad: railAlongPad,
            crossPad: railCrossPad,
            crossExtent: railWidth,
            preferredIndex: preferredItemIndex,
            preferredAlong: preferredAlongOffset(bodyLength: isVertical ? body.height : body.width)
        )
        return frames.map { $0.offsetBy(dx: body.minX, dy: body.minY) }
    }

    func notchBodyFrame(in bounds: CGRect) -> CGRect {
        let cap = settingsCapRevealLength(forAttachmentProgress: attachmentProgress)
            * presentationReveal
        if isVertical {
            let length = max(0, bounds.height - cap)
            let y = expansionAnchor.packsFromStart ? bounds.minY : bounds.maxY - length
            let x: CGFloat
            switch dockedEdge {
            case .right:
                x = bounds.maxX - railWidth
            case .left:
                x = bounds.minX
            default:
                x = bounds.minX + max(0, bounds.width - railWidth) / 2
            }
            return CGRect(x: x, y: y, width: railWidth, height: length)
        }
        let length = max(0, bounds.width - cap)
        let x = expansionAnchor.packsFromStart ? bounds.minX : bounds.maxX - length
        let y: CGFloat
        switch dockedEdge {
        case .top:
            y = bounds.minY
        case .bottom:
            y = bounds.maxY - railWidth
        default:
            y = bounds.minY + max(0, bounds.height - railWidth) / 2
        }
        return CGRect(x: x, y: y, width: length, height: railWidth)
    }

    func settingsCapFrame(in bounds: CGRect) -> CGRect {
        let contact = scoopContactRadius
        return CapacityDockSettingsCapShape(
            progress: 1,
            edge: attachmentEdge,
            expansionAnchor: expansionAnchor,
            bodyRect: notchBodyFrame(in: bounds),
            contactR: contact,
            gap: contact > 1
                ? CapacityDockMetrics.settingsCapGap(scale: scale)
                : CapacityDockMetrics.settingsCapDetachedGap(scale: scale),
            orbSize: CapacityDockMetrics.settingsCapOrbSize(scale: scale)
        ).gearRect
    }

    func containsPointer(_ point: CGPoint, in bounds: CGRect) -> Bool {
        let body = notchBodyFrame(in: bounds)
        return railShape.path(in: body).contains(point)
            || containsSettingsCap(point, in: bounds)
            || pointerTarget(at: point, in: bounds, slop: 2) != nil
    }

    /// Hidden extras stay in the view tree so they can fade, but they must
    /// not steal hover or detail from the preferred ring or empty scoop.
    func pointerTarget(
        at point: CGPoint,
        in bounds: CGRect,
        slop: CGFloat,
        preferring: CapacityDockRailItem? = nil
    ) -> CapacityDockRailItem? {
        let frames = orbFrames(in: bounds)
        if let preferring,
           extraRevealVisible(for: preferring),
           let index = displayedRailItems.firstIndex(of: preferring),
           frames.indices.contains(index),
           frames[index].insetBy(dx: -slop, dy: -slop).contains(point) {
            return preferring
        }
        for (item, frame) in zip(displayedRailItems, frames) {
            guard extraRevealVisible(for: item) else { continue }
            if frame.insetBy(dx: -slop, dy: -slop).contains(point) { return item }
        }
        return nil
    }

    func settingsCapSlotFrame(in bounds: CGRect) -> CGRect {
        let body = notchBodyFrame(in: bounds)
        if isVertical {
            if expansionAnchor.packsFromStart {
                return CGRect(
                    x: bounds.minX,
                    y: body.maxY,
                    width: bounds.width,
                    height: max(0, bounds.maxY - body.maxY)
                )
            }
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: max(0, body.minY - bounds.minY)
            )
        }
        if expansionAnchor.packsFromStart {
            return CGRect(
                x: body.maxX,
                y: bounds.minY,
                width: max(0, bounds.maxX - body.maxX),
                height: bounds.height
            )
        }
        return CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(0, body.minX - bounds.minX),
            height: bounds.height
        )
    }

    func containsSettingsCap(_ point: CGPoint, in bounds: CGRect) -> Bool {
        if settingsCapFrame(in: bounds).insetBy(dx: -4, dy: -4).contains(point) {
            return true
        }
        if settingsCapSlotFrame(in: bounds).insetBy(dx: -1, dy: -1).contains(point) {
            return true
        }
        let body = notchBodyFrame(in: bounds)
        let contactR = scoopContactRadius
        guard contactR > 1 else { return false }
        let pocket: CGRect
        if isVertical {
            pocket = expansionAnchor.packsFromStart
                ? CGRect(x: body.minX, y: body.maxY - contactR - 8, width: body.width, height: contactR + 8)
                : CGRect(x: body.minX, y: body.minY, width: body.width, height: contactR + 8)
        } else {
            pocket = expansionAnchor.packsFromStart
                ? CGRect(x: body.maxX - contactR - 8, y: body.minY, width: contactR + 8, height: body.height)
                : CGRect(x: body.minX, y: body.minY, width: contactR + 8, height: body.height)
        }
        guard pocket.contains(point) else { return false }
        return !railShape.path(in: body).contains(point)
    }

    var restingBodyLength: CGFloat {
        CapacityDockMetrics.railHeight(
            providerCount: preferences.keepExpanded
                ? max(preferences.selectedProviders.count, 1)
                : 1,
            alongPad: railAlongPad,
            scale: scale
        )
    }
    var expandedBodyLength: CGFloat {
        CapacityDockMetrics.railHeight(
            providerCount: max(preferences.selectedProviders.count, 1),
            alongPad: railAlongPad,
            scale: scale
        )
    }
    var targetBodyLength: CGFloat {
        wantsExpandedRail ? expandedBodyLength : restingBodyLength
    }
    var bodyLength: CGFloat {
        restingBodyLength
            + (expandedBodyLength - restingBodyLength)
            * min(max(railPresentationProgress, 0), 1)
    }

    var scale: CGFloat { CGFloat(preferences.scale) }
    var detailScale: CGFloat { max(scale, 0.9) }
    var railWidth: CGFloat {
        isVertical
            ? CapacityDockMetrics.railWidth(scale: scale)
            : CapacityDockMetrics.horizontalRailWidth(scale: scale)
    }
    var isVertical: Bool { attachmentEdge.isVertical }
    var bodySize: CGSize {
        isVertical
            ? CGSize(width: railWidth, height: bodyLength)
            : CGSize(width: bodyLength, height: railWidth)
    }
    var panelSize: CGSize {
        panelSize(forAttachmentProgress: attachmentProgress)
    }
    func panelSize(forAttachmentProgress progress: CGFloat) -> CGSize {
        panelSize(bodyLength: bodyLength, attachmentProgress: progress, reveal: presentationReveal)
    }
    func targetPanelSize(forAttachmentProgress progress: CGFloat) -> CGSize {
        panelSize(
            bodyLength: targetBodyLength,
            attachmentProgress: progress,
            reveal: targetPresentationReveal
        )
    }
    private func panelSize(
        bodyLength: CGFloat,
        attachmentProgress progress: CGFloat,
        reveal: CGFloat
    ) -> CGSize {
        let cap = settingsCapRevealLength(forAttachmentProgress: progress) * reveal
        return isVertical
            ? CGSize(width: railWidth, height: bodyLength + cap)
            : CGSize(width: bodyLength + cap, height: railWidth)
    }

    func settingsCapRevealLength(forAttachmentProgress progress: CGFloat) -> CGFloat {
        let peek = CapacityDockMetrics.settingsCapSlot(scale: scale)
        let detached = CapacityDockMetrics.settingsCapDetachedSlot(scale: scale)
        let eased = min(max(progress, 0), 1)
        let smooth = eased * eased * (3 - 2 * eased)
        if smooth < 0.5 { return detached }
        let u = (smooth - 0.5) / 0.5
        return detached + (peek - detached) * u
    }
    var rowHeight: CGFloat { CapacityDockMetrics.rowHeight(scale: scale) }
    var rowSpacing: CGFloat { CapacityDockMetrics.rowSpacing(scale: scale) }
    // Along-axis content padding: small when floating, plus the docked concave
    // flare depth so content never crowds a necked edge. Cross-axis is a small
    // fixed margin.
    var flareCompensation: CGFloat {
        let p = min(max(attachmentProgress, 0), 1)
        let eased = p * p * (3 - 2 * p)
        return CapacityDockMetrics.edgeShoulderDepth(scale: scale) * 0.6 * eased
    }
    /// Keep first/last rings out of the scooped corners and the nested
    /// settings orb. Derived from flare depth (not live contactR) so it
    /// cannot recurse through restLength.
    var railAlongPad: CGFloat {
        let base = CapacityDockMetrics.railAlongPad(scale: scale) + flareCompensation
        guard flareCompensation > 1 else { return base }
        let orb = CapacityDockMetrics.settingsCapOrbSize(scale: scale)
        let nest = min(max(flareCompensation * 0.33, orb * 0.25), orb * 0.4)
        return max(base, nest + orb)
    }
    var railCrossPad: CGFloat { CapacityDockMetrics.railCrossPad(scale: scale) }
    var detailWidth: CGFloat { CapacityDockMetrics.detailWidth(scale: detailScale) }

    var presentationReveal: CGFloat {
        min(
            max(max(railPresentationProgress, settingsCapProgress, preferences.keepExpanded ? 1 : 0), 0),
            1
        )
    }

    var targetPresentationReveal: CGFloat {
        if preferences.keepExpanded || wantsExpandedRail { return 1 }
        return min(max(settingsCapProgress, 0), 1)
    }

    var allowsItemEmphasis: Bool {
        !isRailMotionActive
            && railPresentationProgress >= 0.999
            && (preferences.keepExpanded || extraIconRevealSettled)
            && (wantsExpandedRail || preferences.keepExpanded)
    }

    var emphasizedProvider: CapacityDockProvider? {
        guard allowsItemEmphasis else { return nil }
        return highlightedProvider ?? hoveredProvider
    }

    var emphasizedItemIndex: Int? {
        guard let provider = emphasizedProvider else { return nil }
        return displayedRailItems.firstIndex(of: .provider(provider))
    }

    func isEmphasized(_ item: CapacityDockRailItem) -> Bool {
        guard let provider = emphasizedProvider,
              case .provider(let itemProvider) = item else { return false }
        return itemProvider == provider
    }

    func itemEmphasisPeekLength() -> CGFloat {
        guard dockedEdge != nil, emphasizedProvider != nil else { return 0 }
        return CapacityDockMetrics.hoverEmphasisTravel(scale: scale)
    }

    var itemEmphasisOffset: CGSize {
        guard let edge = dockedEdge, emphasizedProvider != nil else { return .zero }
        let amount = itemEmphasisPeekLength()
        switch edge {
        case .right: return CGSize(width: -amount, height: 0)
        case .left: return CGSize(width: amount, height: 0)
        case .top: return CGSize(width: 0, height: amount)
        case .bottom: return CGSize(width: 0, height: -amount)
        }
    }

    func presentationScale(for item: CapacityDockRailItem) -> CGFloat {
        guard isEmphasized(item) else { return 1 }
        return 1 + CapacityDockMotion.hoverEmphasisScaleLift
    }

    func presentationOpacity(for provider: CapacityDockProvider) -> CGFloat {
        presentationOpacity(for: .provider(provider))
    }

    func extraSlotDistance(for item: CapacityDockRailItem) -> Int {
        guard let index = displayedRailItems.firstIndex(of: item) else { return 0 }
        return abs(index - preferredItemIndex)
    }

    func extraSlotReady(_ item: CapacityDockRailItem, bodyLength alongLength: CGFloat? = nil) -> Bool {
        let distance = extraSlotDistance(for: item)
        if distance == 0 { return true }
        let rowsNeeded = min(1 + 2 * distance, max(displayedRailItems.count, 1))
        let needed = CapacityDockMetrics.railHeight(
            providerCount: rowsNeeded,
            alongPad: railAlongPad,
            scale: scale
        )
        let start = restingBodyLength
            + (needed - restingBodyLength) * CapacityDockMotion.extraIconSlotThreshold
        return (alongLength ?? bodyLength) >= start - 0.5
    }

    func extraRevealVisible(for item: CapacityDockRailItem) -> Bool {
        if preferences.keepExpanded { return true }
        if isRestingItem(item) { return true }
        if hidesExtraIcons { return false }
        guard showsAllProviders else { return false }
        return extraSlotReady(item)
    }

    func extraAppearScale(for item: CapacityDockRailItem) -> CGFloat {
        extraRevealVisible(for: item) ? 1 : CapacityDockMotion.extraIconAppearScale
    }

    func extraAppearOffset(for item: CapacityDockRailItem) -> CGSize {
        // Collapse fades extras in place. Flying them toward preferred
        // overshoots into the scooped corners and shifts the visual mass.
        if hidesExtraIcons { return .zero }
        if extraRevealVisible(for: item) || isRestingItem(item) { return .zero }
        guard let index = displayedRailItems.firstIndex(of: item) else { return .zero }
        let along = CGFloat(preferredItemIndex - index) * (rowHeight + rowSpacing)
        return isVertical
            ? CGSize(width: 0, height: along)
            : CGSize(width: along, height: 0)
    }

    func extraRevealAnimation(for item: CapacityDockRailItem) -> Animation {
        let distance = extraSlotDistance(for: item)
        if hidesExtraIcons {
            let farthest = displayedRailItems.map(extraSlotDistance(for:)).max() ?? 0
            let delay = TimeInterval(max(farthest - distance, 0)) * CapacityDockMotion.extraIconRevealStagger
            return Animation.easeIn(duration: CapacityDockMotion.extraIconCollapseDuration)
                .delay(delay)
        }
        let points = CapacityDockMotion.timingControlPoints(for: .railExpand)
        let curve = Animation.timingCurve(
            Double(points.0),
            Double(points.1),
            Double(points.2),
            Double(points.3),
            duration: CapacityDockMotion.extraIconRevealDuration
        )
        let delay = TimeInterval(max(distance - 1, 0)) * CapacityDockMotion.extraIconRevealStagger
        return curve.delay(delay)
    }

    var extraRevealSettleDelay: TimeInterval {
        let farthest = displayedRailItems.map(extraSlotDistance(for:)).max() ?? 0
        return CapacityDockMotion.extraIconRevealDuration
            + TimeInterval(max(farthest - 1, 0)) * CapacityDockMotion.extraIconRevealStagger
    }

    func presentationOpacity(for item: CapacityDockRailItem) -> CGFloat {
        extraRevealVisible(for: item) ? 1 : 0
    }

    func isRestingItem(_ item: CapacityDockRailItem) -> Bool {
        if case .provider(let provider) = item {
            return provider == preferences.preferredProvider
        }
        return false
    }
}

enum CapacityDockRailItem: Hashable, Identifiable {
    case provider(CapacityDockProvider)

    var id: String {
        switch self {
        case .provider(let provider): provider.id
        }
    }
}

struct CapacityDockView: View {
    let model: CapacityDockViewModel
    let quota: (CapacityDockProvider) -> QuotaSummary?
    let onProviderClick: (CapacityDockProvider) -> Void
    let onOpenSettings: () -> Void
    let onDragChanged: (CGPoint, CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        let _ = model.quotaEpoch
        GeometryReader { geo in
            let railShape = model.railShape
            let bounds = CGRect(origin: .zero, size: geo.size)
            let bodyRect = model.notchBodyFrame(in: bounds)
            let frames = model.orbFrames(in: bounds)
            ZStack(alignment: .topLeading) {
                railShape.fill(Color.black)
                    .frame(width: bodyRect.width, height: bodyRect.height)
                    .position(x: bodyRect.midX, y: bodyRect.midY)
                ForEach(Array(model.displayedRailItems.enumerated()), id: \.element.id) { index, item in
                    positionedRing(item, frame: frames.indices.contains(index) ? frames[index] : .zero)
                }
            }
            .modifier(
                CapacityDockExpandClip(
                    enabled: model.railPresentationProgress < 0.999
                        || model.isRailMotionActive
                        || model.hidesExtraIcons
                        || (model.attachmentProgress > 0.001
                            && model.attachmentProgress < 0.999),
                    rail: railShape,
                    bodyRect: bodyRect
                )
            )
            .transaction { transaction in
                if model.isRailMotionActive {
                    transaction.animation = nil
                }
            }
            .animation(nil, value: model.railPresentationProgress)
            .animation(preferredReorderAnimation, value: model.preferences.preferredProvider)
            .overlay {
                let capReveal = max(
                    model.railPresentationProgress,
                    model.settingsCapProgress,
                    model.preferences.keepExpanded ? 1 : 0
                )
                CapacityDockSettingsCap(
                    progress: model.settingsCapProgress,
                    scale: model.scale,
                    edge: model.attachmentEdge,
                    expansionAnchor: model.expansionAnchor,
                    bodyRect: bodyRect,
                    contactR: model.scoopContactRadius,
                    onClick: onOpenSettings
                )
                .opacity(capReveal)
                .allowsHitTesting(capReveal > 0.15)
                .animation(
                    .timingCurve(0.22, 1, 0.36, 1, duration: 0.32),
                    value: model.settingsCapProgress
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { onDragChanged(NSEvent.mouseLocation, $0.translation) }
                .onEnded { _ in onDragEnded() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capacity Dock")
    }

    private var preferredReorderAnimation: Animation {
        .spring(
            response: CapacityDockMotion.preferredReorderResponse,
            dampingFraction: CapacityDockMotion.preferredReorderDamping
        )
    }

    private var hoverEmphasisAnimation: Animation {
        .spring(
            response: CapacityDockMotion.hoverEmphasisResponse,
            dampingFraction: CapacityDockMotion.hoverEmphasisDamping
        )
    }

    @ViewBuilder
    private func positionedRing(_ item: CapacityDockRailItem, frame: CGRect) -> some View {
        let appear = model.extraAppearOffset(for: item)
        let peek = model.isEmphasized(item) ? model.itemEmphasisOffset : .zero
        let visible = model.extraRevealVisible(for: item)
        railItem(item)
            .frame(width: frame.width, height: frame.height)
            .compositingGroup()
            .scaleEffect(model.extraAppearScale(for: item), anchor: .center)
            .offset(x: appear.width, y: appear.height)
            .opacity(model.presentationOpacity(for: item))
            .animation(model.extraRevealAnimation(for: item), value: visible)
            .scaleEffect(model.presentationScale(for: item), anchor: .center)
            .offset(x: peek.width, y: peek.height)
            .animation(hoverEmphasisAnimation, value: model.emphasizedProvider)
            .position(x: frame.midX, y: frame.midY)
            .zIndex(model.isEmphasized(item) ? 2 : (model.isRestingItem(item) ? 1 : 0))
            .allowsHitTesting(visible)
    }

    @ViewBuilder
    private func railItem(_ item: CapacityDockRailItem) -> some View {
        switch item {
        case .provider(let provider):
            CapacityDockProviderRow(
                provider: provider,
                quota: quota(provider),
                scale: model.scale,
                gaugeShape: model.preferences.gaugeShape,
                onClick: { onProviderClick(provider) }
            )
        }
    }
}

private struct CapacityDockBodyClip: Shape {
    var rail: CapacityDockRailShape
    var bodyRect: CGRect

    func path(in _: CGRect) -> Path {
        rail.path(in: bodyRect)
    }
}

private struct CapacityDockExpandClip: ViewModifier {
    var enabled: Bool
    var rail: CapacityDockRailShape
    var bodyRect: CGRect

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(CapacityDockBodyClip(rail: rail, bodyRect: bodyRect))
        } else {
            content
        }
    }
}

private struct CapacityDockSettingsCap: View {
    let progress: CGFloat
    let scale: CGFloat
    let edge: CapacityDockEdge
    let expansionAnchor: CapacityDockExpansionAnchor
    let bodyRect: CGRect
    let contactR: CGFloat
    let onClick: () -> Void

    var body: some View {
        let orb = CapacityDockMetrics.settingsCapOrbSize(scale: scale)
        let gap = contactR > 1
            ? CapacityDockMetrics.settingsCapGap(scale: scale)
            : CapacityDockMetrics.settingsCapDetachedGap(scale: scale)
        let shape = CapacityDockSettingsCapShape(
            progress: progress,
            edge: edge,
            expansionAnchor: expansionAnchor,
            bodyRect: bodyRect,
            contactR: contactR,
            gap: gap,
            orbSize: orb
        )
        let gear = shape.gearRect
        Button(action: onClick) {
            ZStack {
                shape.fill(Color.black)
                Image(systemName: "gearshape")
                    .font(.system(size: 16 * scale, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .opacity(progress)
                    .position(x: gear.midX, y: gear.midY)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capacity Dock Settings")
        .accessibilityHint("Open Capacity Dock settings")
    }
}

struct CapacityDockSettingsCapShape: Shape {
    var progress: CGFloat
    var edge: CapacityDockEdge = .right
    var expansionAnchor: CapacityDockExpansionAnchor = .start
    var bodyRect: CGRect = .zero
    var contactR: CGFloat = 0
    var gap: CGFloat = 8
    var orbSize: CGFloat = 44

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Docked rest is a short thick stroke offset along the Helm tail scoop.
    /// Detached rest is a small bar past the pill tail. Hover inflates either
    /// into a filled gear orb.
    func path(in _: CGRect) -> Path {
        let t = min(max(progress, 0), 1)
        let gear = gearRect
        if t >= 0.999 {
            return Path(ellipseIn: gear)
        }
        if contactR <= 1 {
            return detachedBarPath(progress: t, gear: gear)
        }
        let rest = restOffsetSamples(count: 16)
        guard rest.count >= 2 else { return Path(ellipseIn: gear) }
        let lineWidth = restLineWidth + (orbSize - restLineWidth) * t
        let gearCenter = CGPoint(x: gear.midX, y: gear.midY)
        let gearRadius = max(0.6, (orbSize - lineWidth) / 2)
        var path = Path()
        for (index, origin) in rest.enumerated() {
            let fraction = CGFloat(index) / CGFloat(rest.count - 1)
            let angle = Double(fraction) * 2 * Double.pi - Double.pi / 2
            let target = CGPoint(
                x: gearCenter.x + gearRadius * CGFloat(cos(angle)),
                y: gearCenter.y + gearRadius * CGFloat(sin(angle))
            )
            let point = CGPoint(
                x: origin.x + (target.x - origin.x) * t,
                y: origin.y + (target.y - origin.y) * t
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        if t > 0.62 {
            path.closeSubpath()
        }
        return path.strokedPath(
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    var gearRect: CGRect {
        if contactR <= 1 {
            return detachedGearRect
        }
        // Figma: orb sits in the tail scoop, slightly toward the flush edge,
        // center ~0.33 contactR in from the tail — not below the bounding box.
        let nest = min(max(contactR * 0.33, orbSize * 0.25), orbSize * 0.4)
        let shift = orbSize * 0.20
        let half = orbSize / 2
        let fromStart = expansionAnchor.packsFromStart
        switch edge {
        case .right:
            return CGRect(
                x: bodyRect.midX - half + shift,
                y: fromStart ? bodyRect.maxY - nest - half : bodyRect.minY + nest - half,
                width: orbSize,
                height: orbSize
            )
        case .left:
            return CGRect(
                x: bodyRect.midX - half - shift,
                y: fromStart ? bodyRect.maxY - nest - half : bodyRect.minY + nest - half,
                width: orbSize,
                height: orbSize
            )
        case .bottom:
            return CGRect(
                x: fromStart ? bodyRect.maxX - nest - half : bodyRect.minX + nest - half,
                y: bodyRect.midY - half + shift,
                width: orbSize,
                height: orbSize
            )
        case .top:
            return CGRect(
                x: fromStart ? bodyRect.maxX - nest - half : bodyRect.minX + nest - half,
                y: bodyRect.midY - half - shift,
                width: orbSize,
                height: orbSize
            )
        }
    }

    private var detachedGearRect: CGRect {
        let clearance = max(gap, orbSize * 0.18)
        let half = orbSize / 2
        if edge.isVertical {
            let x = bodyRect.midX - half
            let y = expansionAnchor.packsFromStart
                ? bodyRect.maxY + clearance
                : bodyRect.minY - clearance - orbSize
            return CGRect(x: x, y: y, width: orbSize, height: orbSize)
        }
        let y = bodyRect.midY - half
        let x = expansionAnchor.packsFromStart
            ? bodyRect.maxX + clearance
            : bodyRect.minX - clearance - orbSize
        return CGRect(x: x, y: y, width: orbSize, height: orbSize)
    }

    private var detachedBarRect: CGRect {
        let clearance = max(gap, orbSize * 0.12)
        let thickness = max(5, (orbSize * 0.14).rounded())
        let length = max(thickness * 3, (bodyCrossExtent * 0.42).rounded())
        if edge.isVertical {
            let x = bodyRect.midX - length / 2
            let y = expansionAnchor.packsFromStart
                ? bodyRect.maxY + clearance
                : bodyRect.minY - clearance - thickness
            return CGRect(x: x, y: y, width: length, height: thickness)
        }
        let y = bodyRect.midY - length / 2
        let x = expansionAnchor.packsFromStart
            ? bodyRect.maxX + clearance
            : bodyRect.minX - clearance - thickness
        return CGRect(x: x, y: y, width: thickness, height: length)
    }

    private var bodyCrossExtent: CGFloat {
        edge.isVertical ? bodyRect.width : bodyRect.height
    }

    private func detachedBarPath(progress t: CGFloat, gear: CGRect) -> Path {
        let bar = detachedBarRect
        if t <= 0.001 {
            return Path(roundedRect: bar, cornerRadius: min(bar.width, bar.height) / 2)
        }
        let rect = CGRect(
            x: bar.minX + (gear.minX - bar.minX) * t,
            y: bar.minY + (gear.minY - bar.minY) * t,
            width: bar.width + (gear.width - bar.width) * t,
            height: bar.height + (gear.height - bar.height) * t
        )
        let radius = min(rect.width, rect.height) / 2
        return Path(roundedRect: rect, cornerRadius: radius)
    }

    private var restLineWidth: CGFloat { max(9, orbSize * 0.24) }
    private var restArcGap: CGFloat { max(3.5, orbSize * 0.08) }
    private var restOffsetDistance: CGFloat { restArcGap + restLineWidth / 2 }

    private func restOffsetSamples(count: Int) -> [CGPoint] {
        guard count >= 2 else { return [] }
        let canonical = CGSize(
            width: edge.isVertical ? bodyRect.width : bodyRect.height,
            height: edge.isVertical ? bodyRect.height : bodyRect.width
        )
        return scoopRestSamples(count: count, canonical: canonical)
    }

    private func scoopRestSamples(count: Int, canonical: CGSize) -> [CGPoint] {
        let radius = min(contactR, canonical.width, canonical.height / 2)
        guard radius > 1 else { return [] }
        let p0 = CGPoint(x: canonical.width - radius, y: canonical.height - radius)
        let p1 = CGPoint(x: canonical.width, y: canonical.height - radius)
        let p2 = CGPoint(x: canonical.width, y: canonical.height)
        // Longer wrap along the scoop, stop before 6 o'clock so the stroke
        // doesn't hang off the tail (Figma rest: t ≈ 0.14…0.86).
        let t0: CGFloat = 0.14
        let t1: CGFloat = 0.86
        let distance = restOffsetDistance
        return (0..<count).map { index in
            let t = t0 + (t1 - t0) * CGFloat(index) / CGFloat(count - 1)
            return transformed(offsetPoint(t: t, p0: p0, p1: p1, p2: p2, distance: distance), canonical: canonical)
        }
    }

    private func offsetPoint(
        t: CGFloat,
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        distance: CGFloat
    ) -> CGPoint {
        let u = 1 - t
        let point = CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
        let tangent = CGPoint(
            x: 2 * u * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            y: 2 * u * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        )
        let length = max(hypot(tangent.x, tangent.y), 0.000_1)
        // y-down: rotate tangent 90° CCW to point into the pocket.
        let normal = CGPoint(x: -tangent.y / length, y: tangent.x / length)
        return CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
    }

    private func transformed(_ point: CGPoint, canonical: CGSize) -> CGPoint {
        let flipped = expansionAnchor == .end
            ? CGPoint(x: point.x, y: canonical.height - point.y)
            : point
        switch edge {
        case .right:
            return CGPoint(x: bodyRect.minX + flipped.x, y: bodyRect.minY + flipped.y)
        case .left:
            return CGPoint(x: bodyRect.maxX - flipped.x, y: bodyRect.minY + flipped.y)
        case .bottom:
            return CGPoint(x: bodyRect.minX + flipped.y, y: bodyRect.minY + flipped.x)
        case .top:
            return CGPoint(x: bodyRect.minX + flipped.y, y: bodyRect.maxY - flipped.x)
        }
    }
}

private struct CapacityDockProviderRow: View {
    let provider: CapacityDockProvider
    let quota: QuotaSummary?
    let scale: CGFloat
    let gaugeShape: CapacityDockGaugeShape
    let onClick: () -> Void

    private var headline: QuotaSummary.Window? { quota?.headlineWindow }
    private var percent: Double? { headline?.percent }

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: CapacityDockMetrics.ringLabelSpacing(scale: scale)) {
                ZStack {
                    CapacityDockUsageRing(
                        progress: percent,
                        color: headlineRingColor,
                        scale: scale,
                        gaugeShape: gaugeShape
                    )

                    if let image = ProviderIconCache.image(named: provider.iconName) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .frame(
                                width: CapacityDockMetrics.providerIconSize(scale: scale),
                                height: CapacityDockMetrics.providerIconSize(scale: scale)
                            )
                    } else {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 21 * scale, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    if case .terminalFailure = quota?.connection {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12 * scale, weight: .bold))
                            .foregroundStyle(.red)
                            .background(Circle().fill(.black))
                            .offset(x: 19 * scale, y: -19 * scale)
                    }
                }
                .frame(
                    width: CapacityDockMetrics.ringSize(scale: scale),
                    height: CapacityDockMetrics.ringSize(scale: scale)
                )
                .compositingGroup()

                Text(CapacityDockQuotaPresentation.ringPercentLabel(quota: quota))
                    .font(.system(
                        size: CapacityDockMetrics.percentageTextSize(scale: scale),
                        weight: .medium
                    ))
                    .monospacedDigit()
                    .foregroundStyle(headlinePercentColor)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.displayName) usage")
        .accessibilityValue(CapacityDockQuotaPresentation.ringPercentLabel(quota: quota))
        .accessibilityHint("Click to show usage details")
    }

    private var headlinePercentColor: Color {
        guard let percent else { return Color.capacityDockText.opacity(0.72) }
        switch QuotaSummary.severity(for: percent) {
        case .normal: return Color.capacityDockText
        case .warning: return .yellow
        case .critical: return .orange
        case .danger: return .red
        }
    }

    // The ring reflects the weekly (else monthly) limit's status, not a brand
    // colour: green while there is headroom, stepping to red as it is exhausted.
    private var headlineRingColor: Color {
        guard let percent else { return Color.capacityDockText.opacity(0.35) }
        switch QuotaSummary.severity(for: percent) {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .danger: return .red
        }
    }
}

private struct CapacityDockUsageRing: View {
    let progress: Double?
    let color: Color
    let scale: CGFloat
    let gaugeShape: CapacityDockGaugeShape

    private var strokeWidth: CGFloat {
        CapacityDockMetrics.ringStrokeWidth(scale: scale)
    }

    var body: some View {
        ZStack {
            // A recessed track makes the progress read as light filling a
            // physical channel instead of a flat vector stroke.
            CapacityDockGaugePath(kind: gaugeShape)
                .stroke(Color.black.opacity(0.74), lineWidth: strokeWidth + 2 * scale)
            CapacityDockGaugePath(kind: gaugeShape)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.07), .white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth + 0.6 * scale
                )

            if let progress {
                let amount = min(max(progress, 0), 1)
                // Plain solid progress arc, no neon glow or gradient sheen.
                CapacityDockGaugePath(kind: gaugeShape)
                    .trim(from: 0, to: amount)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .compositingGroup()
    }
}

struct CapacityDockGaugePath: Shape {
    let kind: CapacityDockGaugeShape

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .circle:
            Path(ellipseIn: rect)
        case .squircle:
            RoundedRectangle(
                cornerRadius: min(rect.width, rect.height) * 0.30,
                style: .continuous
            )
            .path(in: rect)
        }
    }
}

enum CapacityDockQuotaPresentation {
    static func displayLabel(_ label: String) -> String {
        let compact = label
            .replacingOccurrences(of: "Claude and GPT models", with: "Claude + GPT", options: .caseInsensitive)
            .replacingOccurrences(of: "Gemini Models", with: "Gemini", options: .caseInsensitive)
            .replacingOccurrences(of: "Five-hour", with: "5h", options: .caseInsensitive)
            .replacingOccurrences(of: "5-hour", with: "5h", options: .caseInsensitive)
        if compact.range(of: "limit", options: .caseInsensitive) != nil {
            return compact
        }
        if compact.range(of: "5h", options: .caseInsensitive) != nil {
            return "5h limit"
        }
        if compact.range(of: "week", options: .caseInsensitive) != nil {
            return "Weekly limit"
        }
        if compact.range(of: "month", options: .caseInsensitive) != nil {
            return "Monthly limit"
        }
        return compact
    }

    static func compactPlanLabel(_ plan: String) -> String {
        switch plan.lowercased().filter(\.isLetter) {
        case "supergrokheavy": "Heavy"
        default: plan
        }
    }

    /// Unbound / unknown quota uses a single dash, matching Codenotch.
    static func ringPercentLabel(quota: QuotaSummary?) -> String {
        guard let quota else { return "-" }
        switch quota.connection {
        case .disconnected, .terminalFailure:
            return "-"
        case .connected, .loading, .stale, .transientFailure:
            return quota.headlineWindow?.percentLabel ?? "-"
        }
    }

    static func visibleFooterLines(
        _ lines: [String],
        connection: QuotaSummary.Connection
    ) -> [String] {
        guard case let .terminalFailure(reason) = connection,
              let reason,
              !reason.isEmpty else { return lines }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(normalizedReason) != .orderedSame
        }
    }
}

struct CapacityDockDetailView: View {
    let model: CapacityDockViewModel
    let quota: (CapacityDockProvider) -> QuotaSummary?
    let onConnect: (CapacityDockProvider) -> Void

    var body: some View {
        let _ = model.quotaEpoch
        let bubbleShape = CapacityDockBubbleShape(
            tailEdge: model.detailTailEdge,
            tailPosition: model.detailTailPosition
        )
        Group {
            if let provider = model.hoveredProvider {
                detail(for: provider, quota: quota(provider))
            }
        }
        .padding(detailInsets)
        .frame(
            width: model.detailWidth,
            height: model.detailHeight,
            alignment: .topLeading
        )
        .background(bubbleShape.fill(Color.black))
        .contentShape(bubbleShape)
        .accessibilityElement(children: .contain)
    }

    private var detailInsets: EdgeInsets {
        let horizontal = 22 * model.detailScale
        let vertical = 16 * model.detailScale
        let tailAllowance = 18 * model.detailScale
        return EdgeInsets(
            top: vertical + (model.detailTailEdge == .top ? tailAllowance : 0),
            leading: horizontal + (model.detailTailEdge == .left ? tailAllowance : 0),
            bottom: vertical + (model.detailTailEdge == .bottom ? tailAllowance : 0),
            trailing: horizontal + (model.detailTailEdge == .right ? tailAllowance : 0)
        )
    }

    @ViewBuilder
    private func detail(for provider: CapacityDockProvider, quota: QuotaSummary?) -> some View {
        VStack(alignment: .leading, spacing: 11 * model.detailScale) {
            HStack(spacing: 8 * model.detailScale) {
                if let image = ProviderIconCache.image(named: provider.iconName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.capacityDockText)
                        .frame(width: 24 * model.detailScale, height: 24 * model.detailScale)
                }
                Text("\(provider.displayName) Usage")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.capacityDockText)
                Spacer(minLength: 8)
                if let plan = quota?.planLabel, !plan.isEmpty {
                    Text(CapacityDockQuotaPresentation.compactPlanLabel(plan))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.capacityDockText.opacity(0.62))
                        .lineLimit(1)
                }
            }

            if let quota {
                connectionLabel(quota.connection, provider: provider)
                if quota.details.isEmpty, let primary = quota.primary {
                    CapacityDockQuotaRow(
                        window: primary,
                        scale: model.detailScale
                    )
                } else {
                    ForEach(Array(quota.details.prefix(5).enumerated()), id: \.offset) { _, window in
                        CapacityDockQuotaRow(
                            window: window,
                            scale: model.detailScale
                        )
                    }
                }
                let footerLines = CapacityDockQuotaPresentation.visibleFooterLines(
                    quota.footerLines,
                    connection: quota.connection
                )
                if !footerLines.isEmpty {
                    Divider().overlay(Color.capacityDockText.opacity(0.12))
                    ForEach(Array(footerLines.prefix(2).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.capacityDockText.opacity(0.58))
                    }
                }
                let liveTasks = Array(model.activeTasks.prefix(CapacityDockActiveTaskSnapshot.maxTasks))
                if !liveTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6 * model.detailScale) {
                        ForEach(liveTasks) { task in
                            CapacityDockActiveTaskRow(
                                task: task,
                                scale: model.detailScale
                            )
                        }
                    }
                    .padding(.top, 2 * model.detailScale)
                }
            } else {
                Text(ProviderConnectionGuidance.dockInstruction(for: provider))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.capacityDockText.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if provider.catalogEntry.hasLiveCodeBurnQuotaAdapter,
               let action = CapacityDockConnectionAction.resolve(quota: quota) {
                let title = action.title(for: provider)
                Button(title) { onConnect(provider) }
                    .buttonStyle(.borderedProminent)
                    .tint(provider.ringColor)
                    .controlSize(.small)
                    .accessibilityLabel("\(title) \(provider.displayName)")
            }
        }
    }

    @ViewBuilder
    private func connectionLabel(
        _ connection: QuotaSummary.Connection,
        provider: CapacityDockProvider
    ) -> some View {
        switch connection {
        case .connected:
            EmptyView()
        case .loading:
            Text("Refreshing…")
                .font(.system(size: 10))
                .foregroundStyle(Color.capacityDockText.opacity(0.52))
        case .stale:
            Text("Last known usage · refreshing")
                .font(.system(size: 10))
                .foregroundStyle(.yellow.opacity(0.82))
        case .transientFailure:
            Text("Last known usage · retrying")
                .font(.system(size: 10))
                .foregroundStyle(.orange.opacity(0.86))
        case .disconnected:
            Text("Not connected")
                .font(.system(size: 11))
                .foregroundStyle(Color.capacityDockText.opacity(0.6))
        case .terminalFailure(let reason):
            VStack(alignment: .leading, spacing: 3 * model.detailScale) {
                Text("Reconnect required")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.capacityDockText.opacity(0.58))
                        .lineLimit(2)
                }
                Text(ProviderConnectionGuidance.dockInstruction(for: provider))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.capacityDockText.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CapacityDockActiveTaskRow: View {
    let task: CapacityDockActiveTask
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 7 * scale) {
            CapacityDockLiveDot(size: 8 * scale)
            Text(task.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.capacityDockText.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(task.title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: NSLocalizedString("Active, %@", comment: ""), task.title)
        )
    }
}

private struct CapacityDockLiveDot: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.22))
            if reduceMotion {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.42, height: size * 0.42)
            } else {
                Circle()
                    .trim(from: 0.12, to: 0.78)
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: max(1.25, size * 0.18), lineCap: .round)
                    )
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(
                        .linear(duration: 0.85).repeatForever(autoreverses: false),
                        value: spinning
                    )
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .onAppear { spinning = !reduceMotion }
        .accessibilityHidden(true)
    }
}

private struct CapacityDockQuotaRow: View {
    let window: QuotaSummary.Window
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                Text(CapacityDockQuotaPresentation.displayLabel(window.label))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !window.resetsAtLabel.isEmpty {
                    Text(window.resetsAtLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(progressColor)
                        .frame(width: max(2, geometry.size.width * min(max(window.percent, 0), 1)))
                }
            }
            .frame(height: 4 * scale)
            Text("\(window.percentLabel) Used")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.88))
        }
    }

    private var progressColor: Color {
        switch QuotaSummary.severity(for: window.percent) {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .danger: return .red
        }
    }
}

private struct CapacityDockSurface<S: Shape>: View {
    let shape: S
    let theme: CapacityDockTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if theme == .liquidGlass, !reduceTransparency {
            if #available(macOS 26.0, *) {
                CapacityDockNativeGlassSurface(shape: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.black.opacity(0.16)))
            }
        } else {
            ZStack {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.075, green: 0.078, blue: 0.085), location: 0),
                            .init(color: Color(red: 0.034, green: 0.035, blue: 0.040), location: 0.46),
                            .init(color: Color(red: 0.012, green: 0.013, blue: 0.016), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                shape.fill(
                    RadialGradient(
                        colors: [.white.opacity(0.055), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
            }
        }
    }
}

@available(macOS 26.0, *)
private struct CapacityDockNativeGlassSurface<S: Shape>: View {
    let shape: S

    var body: some View {
        #if compiler(>=6.2)
        Color.clear
            .glassEffect(.regular.interactive(), in: shape)
            // Native glass tracks the wallpaper, so over a light background it
            // turns pale and the light text disappears. A gentle dark scrim keeps
            // the surface dark enough for the labels on any background while still
            // reading as glass.
            .overlay(shape.fill(Color.black.opacity(0.24)))
        #else
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.black.opacity(0.16)))
        #endif
    }
}

struct CapacityDockRailShape: Shape {
    var bodyWidth: CGFloat
    var bodyLength: CGFloat? = nil
    /// Corner radii stay locked to this length while the rail grows, so the
    /// expansion-anchor end (the top, when expanding down) does not reshape.
    var restLength: CGFloat? = nil
    var shoulderDepth: CGFloat = 34
    var attachmentProgress: CGFloat
    var edge: CapacityDockEdge

    var animatableData: CGFloat {
        get { attachmentProgress }
        set { attachmentProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let canonicalRect = CGRect(
            x: 0,
            y: 0,
            width: edge.isVertical ? rect.width : rect.height,
            height: edge.isVertical ? rect.height : rect.width
        )
        let canonical = rightFlarePath(in: canonicalRect)
        let transform: CGAffineTransform
        switch edge {
        case .right:
            transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        case .left:
            transform = CGAffineTransform(
                a: -1,
                b: 0,
                c: 0,
                d: 1,
                tx: canonicalRect.width + rect.minX,
                ty: rect.minY
            )
        case .bottom:
            transform = CGAffineTransform(
                a: 0,
                b: 1,
                c: 1,
                d: 0,
                tx: rect.minX,
                ty: rect.minY
            )
        case .top:
            transform = CGAffineTransform(
                a: 0,
                b: -1,
                c: 1,
                d: 0,
                tx: rect.minX,
                ty: canonicalRect.width + rect.minY
            )
        }
        return canonical.applying(transform)
    }

    private func rightFlarePath(in rect: CGRect) -> Path {
        let progress = min(max(attachmentProgress, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        // The system-notch technique (Helm / notchi): one quad curve per corner,
        // control point at the corner. Free (left) side has convex rounded
        // corners; the contact (right) side necks concavely into the touched
        // edge when docked. Depth scales with panel length and is clamped below
        // half of it, so a short single-item rail necks gently and never lets the
        // two shoulders meet or swallow the gauge.
        // freeR: convex rounded corners on the free (left) side. contactR: the
        // small concave flare where the body necks out to the flush contact
        // (right) edge — the body is inset from top and bottom by contactR, and
        // the flare connects that inset to the flush corner (Helm's structure).
        let referenceLength = restLength ?? bodyLength ?? rect.height
        let freeR = min(22, referenceLength / 2, bodyWidth * 0.45)
        // Not attached to an edge: a plain rounded pill, every corner rounded.
        // The concave contact-edge flares only exist once docked.
        if eased < 0.5 {
            return Path(roundedRect: rect, cornerRadius: freeR)
        }
        // Scoop depth is taken from the resting length, not the live height, so
        // hover-expand only lengthens the midsection. The top curve stays put.
        let contactR = Self.contactRadius(
            bodyWidth: bodyWidth,
            restLength: referenceLength,
            shoulderDepth: shoulderDepth,
            attachmentProgress: attachmentProgress
        )

        var path = Path()
        // Flush top-right corner, then concave flare into the inset body top
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - contactR, y: rect.minY + contactR),
            control: CGPoint(x: rect.maxX, y: rect.minY + contactR)
        )
        // Body top edge to the free-side top corner (convex)
        path.addLine(to: CGPoint(x: rect.minX + freeR, y: rect.minY + contactR))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + contactR + freeR),
            control: CGPoint(x: rect.minX, y: rect.minY + contactR)
        )
        // Free (left) edge down to the bottom-left corner (convex)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - contactR - freeR))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + freeR, y: rect.maxY - contactR),
            control: CGPoint(x: rect.minX, y: rect.maxY - contactR)
        )
        // Body bottom edge, then concave flare out to the flush bottom-right
        path.addLine(to: CGPoint(x: rect.maxX - contactR, y: rect.maxY - contactR))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY - contactR)
        )
        // Flush contact (right) edge back up to the start
        path.closeSubpath()
        return path
    }

    static func contactRadius(
        bodyWidth: CGFloat,
        restLength: CGFloat,
        shoulderDepth: CGFloat,
        attachmentProgress: CGFloat
    ) -> CGFloat {
        let eased = ease(attachmentProgress)
        if eased < 0.5 { return 0 }
        let freeR = min(22, restLength / 2, bodyWidth * 0.45)
        return min(
            shoulderDepth * 0.6,
            restLength * 0.22,
            max(0, restLength / 2 - freeR)
        ) * eased
    }

    private static func ease(_ progress: CGFloat) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return p * p * (3 - 2 * p)
    }
}

struct CapacityDockBubbleShape: Shape {
    let tailEdge: CapacityDockEdge
    var tailPosition: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        let canonicalRect = CGRect(
            x: 0,
            y: 0,
            width: tailEdge.isVertical ? rect.width : rect.height,
            height: tailEdge.isVertical ? rect.height : rect.width
        )
        let canonical = rightTailPath(in: canonicalRect)
        let transform: CGAffineTransform
        switch tailEdge {
        case .right:
            transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        case .left:
            transform = CGAffineTransform(
                a: -1,
                b: 0,
                c: 0,
                d: 1,
                tx: canonicalRect.width + rect.minX,
                ty: rect.minY
            )
        case .bottom:
            transform = CGAffineTransform(
                a: 0,
                b: 1,
                c: 1,
                d: 0,
                tx: rect.minX,
                ty: rect.minY
            )
        case .top:
            transform = CGAffineTransform(
                a: 0,
                b: -1,
                c: 1,
                d: 0,
                tx: rect.minX,
                ty: canonicalRect.width + rect.minY
            )
        }
        return canonical.applying(transform)
    }

    private func rightTailPath(in rect: CGRect) -> Path {
        var path = Path()
        let tailWidth = min(22, max(14, rect.width * 0.055))
        let bodyRight = rect.maxX - tailWidth
        let radius = min(20, rect.height * 0.18)
        let midY = rect.minY + rect.height * min(max(tailPosition, 0.18), 0.82)
        let neckHalfHeight = min(32, rect.height * 0.19)

        path.move(to: CGPoint(x: radius, y: rect.minY))
        path.addLine(to: CGPoint(x: bodyRight - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight, y: rect.minY + radius),
            control: CGPoint(x: bodyRight, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bodyRight, y: midY - neckHalfHeight))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control1: CGPoint(x: bodyRight, y: midY - neckHalfHeight * 0.55),
            control2: CGPoint(x: rect.maxX, y: midY - tailWidth * 0.42)
        )
        path.addCurve(
            to: CGPoint(x: bodyRight, y: midY + neckHalfHeight),
            control1: CGPoint(x: rect.maxX, y: midY + tailWidth * 0.42),
            control2: CGPoint(x: bodyRight, y: midY + neckHalfHeight * 0.55)
        )
        path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight - radius, y: rect.maxY),
            control: CGPoint(x: bodyRight, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private extension CapacityDockProvider {
    var ringColor: Color {
        switch self {
        case .claude: return Color(red: 0.98, green: 0.31, blue: 0.08)
        case .codex: return Color(red: 0.12, green: 0.87, blue: 0.55)
        case .gemini: return Color(red: 0.28, green: 0.55, blue: 0.98)
        case .copilot: return Color(red: 0.58, green: 0.48, blue: 0.96)
        case .kimiCode: return Color(red: 0.90, green: 0.94, blue: 0.08)
        case .antigravity: return Color(red: 1.0, green: 0.48, blue: 0.27)
        default:
            // Stable CodeBurn-owned accents keep generated provider sigils
            // recognizable without importing a branding registry.
            let seed = rawValue.utf8.reduce(UInt64(2_166_136_261)) { value, byte in
                (value ^ UInt64(byte)) &* 16_777_619
            }
            return Color(
                hue: Double(seed % 360) / 360,
                saturation: 0.72,
                brightness: 0.94
            )
        }
    }
}
