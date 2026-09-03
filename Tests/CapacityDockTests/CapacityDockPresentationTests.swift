import CoreGraphics
import Foundation
import Testing
@testable import CapacityDock

@Suite("Capacity Dock presentation")
struct CapacityDockPresentationTests {
    @Test("Reference-scale rail uses Codenotch side-notch proportions")
    func compactRailMetrics() {
        #expect(CapacityDockMetrics.railWidth(scale: 1) == 72)
        #expect(CapacityDockMetrics.horizontalRailWidth(scale: 1) == 78)
        #expect(CapacityDockMetrics.edgeFlareWidth(scale: 1) == 0)
        #expect(CapacityDockMetrics.edgeShoulderDepth(scale: 1) == 72)
        #expect(CapacityDockMetrics.rowHeight(scale: 1) == 62)
        #expect(CapacityDockMetrics.rowSpacing(scale: 1) == 10)
        #expect(CapacityDockMetrics.railAlongPad(scale: 1) == 10)
        #expect(CapacityDockMetrics.railCrossPad(scale: 1) == 14)
        #expect(CapacityDockMetrics.ringSize(scale: 1) == 44)
        #expect(CapacityDockMetrics.ringStrokeWidth(scale: 1) == 3)
        #expect(CapacityDockMetrics.ringLabelSpacing(scale: 1) == 4)
        #expect(CapacityDockMetrics.providerIconSize(scale: 1) == 20)
        #expect(CapacityDockMetrics.percentageTextSize(scale: 1) == 12)
        #expect(CapacityDockMetrics.settingsCapGap(scale: 1) == 2)
        #expect(CapacityDockMetrics.settingsCapDetachedGap(scale: 1) == 8)
        #expect(CapacityDockMetrics.settingsCapOrbSize(scale: 1) == 44)
        #expect(CapacityDockMetrics.settingsCapSlot(scale: 1) == 12)
        #expect(CapacityDockMetrics.settingsCapDetachedSlot(scale: 1) == 52)
    }

    @MainActor
    @Test("rail body length follows presentation progress instead of snapping to interaction state")
    func presentationLengthInterpolates() {
        let suite = "CodeBurnMenubarTests.CapacityDock.Presentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))
        model.interaction.setRailHovered(true)
        model.isRailPresentationExpanded = true
        model.railPresentationProgress = 0.5

        let resting = CapacityDockMetrics.railHeight(providerCount: 1, alongPad: model.railAlongPad, scale: model.scale)
        let expanded = CapacityDockMetrics.railHeight(providerCount: 3, alongPad: model.railAlongPad, scale: model.scale)
        #expect(abs(model.bodyLength - (resting + expanded) / 2) < 0.000_001)
        #expect(model.displayedProviders.first == .codex)
    }

    @MainActor
    @Test("resting rail shows only the pinned provider")
    func restingRailShowsPinnedProviderOnly() {
        let suite = "CodeBurnMenubarTests.CapacityDock.RestingShell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        CapacityDockPreferences.setPreferredProvider(.codex, defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))

        #expect(model.displayedRailItems == [.provider(.codex)])
        #expect(model.displayedProviders == [.codex])
        #expect(model.bodyLength == model.restingBodyLength)
    }

    @MainActor
    @Test("Keep-expanded rest shows every selected ring without a hover")
    func keepExpandedRestShowsAllProviders() {
        let suite = "CodeBurnMenubarTests.CapacityDock.KeepExpandedRest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        CapacityDockPreferences.setPreferredProvider(.codex, defaults: defaults)
        CapacityDockPreferences.setKeepExpanded(true, defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))

        #expect(model.displayedProviders == [.codex, .claude, .gemini])
        #expect(model.restingBodyLength == model.expandedBodyLength)
        #expect(model.bodyLength == model.expandedBodyLength)
        #expect(model.wantsExpandedRail)
        #expect(model.presentationOpacity(for: .claude) == 1)
        #expect(model.presentationOpacity(for: .gemini) == 1)

        model.interaction.setRailHovered(true)
        #expect(model.displayedProviders == [.codex, .claude, .gemini])
        model.interaction.setRailHovered(false)
        #expect(model.displayedProviders == [.codex, .claude, .gemini])
        #expect(model.targetBodyLength == model.expandedBodyLength)
    }

    @MainActor
    @Test("expanded notch shows only provider rings; settings sit on the external cap")
    func expandedRailKeepsProvidersInsideNotch() {
        let suite = "CodeBurnMenubarTests.CapacityDock.ExpandedShell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        CapacityDockPreferences.setPreferredProvider(.codex, defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))
        model.isRailPresentationExpanded = true
        model.railPresentationProgress = 1
        model.expansionAnchor = .start

        #expect(model.displayedRailItems == [
            .provider(.codex), .provider(.claude), .provider(.gemini),
        ])
        let bounds = CGRect(origin: .zero, size: model.panelSize)
        let body = model.notchBodyFrame(in: bounds)
        let cap = model.settingsCapFrame(in: bounds)
        #expect(body.height == model.bodyLength)
        #expect(cap.maxY <= bounds.maxY + 0.5)
        #expect(cap.maxY > body.maxY)
        #expect(cap.minY < body.maxY)
        #expect(cap.midX > body.midX)
        #expect(model.panelSize.height == model.bodyLength + CapacityDockMetrics.settingsCapSlot(scale: model.scale))
        let nestedGear = CGPoint(x: cap.midX, y: cap.minY + 6)
        #expect(model.containsSettingsCap(nestedGear, in: bounds))
    }

    @MainActor
    @Test("settings cap morphs from an outside arc to a gear")
    func settingsCapMorphsFromArcToGear() {
        let body = CGRect(x: 0, y: 0, width: 72, height: 168)
        let panel = CGRect(x: 0, y: 0, width: 72, height: 220)
        let rest = CapacityDockSettingsCapShape(
            progress: 0,
            edge: .right,
            expansionAnchor: .start,
            bodyRect: body,
            contactR: 37,
            gap: 8,
            orbSize: 44
        ).path(in: panel)
        let gear = CapacityDockSettingsCapShape(
            progress: 1,
            edge: .right,
            expansionAnchor: .start,
            bodyRect: body,
            contactR: 37,
            gap: 8,
            orbSize: 44
        ).path(in: panel)

        // Rest is a longer parallel of the Helm tail scoop, sitting in the
        // groove — not hanging off 6 o'clock and not a disc below the body.
        #expect(rest.contains(CGPoint(x: 61, y: 153)))
        #expect(rest.contains(CGPoint(x: 45, y: 141)))
        #expect(!rest.contains(CGPoint(x: 63, y: 168)))
        #expect(!rest.contains(CGPoint(x: 68, y: 176)))
        #expect(!rest.contains(CGPoint(x: 36, y: 198)))
        #expect(!rest.contains(CGPoint(x: 20, y: 160)))
        #expect(gear.contains(CGPoint(x: 45, y: 156)))
        #expect(gear.contains(CGPoint(x: 45, y: 148)))
        #expect(!gear.contains(CGPoint(x: 36, y: 198)))
        #expect(!gear.contains(CGPoint(x: 4, y: 156)))
    }

    @Test("Detached pill keeps settings outside the body instead of nesting into a scoop")
    func detachedSettingsSitOutsidePill() {
        let body = CGRect(x: 0, y: 0, width: 72, height: 168)
        let panel = CGRect(x: 0, y: 0, width: 72, height: 220)
        let rest = CapacityDockSettingsCapShape(
            progress: 0,
            edge: .right,
            expansionAnchor: .start,
            bodyRect: body,
            contactR: 0,
            gap: 8,
            orbSize: 44
        ).path(in: panel)
        let gear = CapacityDockSettingsCapShape(
            progress: 1,
            edge: .right,
            expansionAnchor: .start,
            bodyRect: body,
            contactR: 0,
            gap: 8,
            orbSize: 44
        ).path(in: panel)

        #expect(!rest.contains(CGPoint(x: 36, y: 84)))
        #expect(!rest.contains(CGPoint(x: 36, y: 150)))
        #expect(rest.contains(CGPoint(x: 36, y: 177)))
        #expect(!rest.contains(CGPoint(x: 8, y: 177)))
        #expect(gear.contains(CGPoint(x: 36, y: 198)))
        #expect(!gear.contains(CGPoint(x: 36, y: 150)))
    }

    @Test("unbound provider quota renders as a single dash")
    func unboundQuotaUsesSingleDash() {
        #expect(CapacityDockQuotaPresentation.ringPercentLabel(quota: nil) == "-")
        let disconnected = QuotaSummary(
            providerFilter: .claude,
            connection: .disconnected,
            primary: nil,
            details: [],
            planLabel: nil,
            footerLines: []
        )
        #expect(CapacityDockQuotaPresentation.ringPercentLabel(quota: disconnected) == "-")
        let connected = QuotaSummary(
            providerFilter: .codex,
            connection: .connected,
            primary: QuotaSummary.Window(label: "Weekly", percent: 0.23, resetsAt: nil),
            details: [],
            planLabel: nil,
            footerLines: []
        )
        #expect(CapacityDockQuotaPresentation.ringPercentLabel(quota: connected) == "23%")
    }

    @MainActor
    @Test("Resting provider stays at the reveal anchor")
    func restingProviderFollowsExpansionAnchor() {
        let suite = "CodeBurnMenubarTests.CapacityDock.AnchorOrder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))
        model.isRailPresentationExpanded = true

        model.expansionAnchor = .start
        #expect(model.displayedProviders == [.codex, .claude, .gemini])
        model.expansionAnchor = .end
        #expect(model.displayedProviders == [.gemini, .claude, .codex])
    }

    @MainActor
    @Test("Attachment morphs inside the body without changing the panel size")
    func attachmentKeepsPanelSizeStable() {
        let suite = "CodeBurnMenubarTests.CapacityDock.EdgeSpread.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setScale(1.2, defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))

        model.attachmentEdge = .right
        let vertical = model.targetPanelSize(forAttachmentProgress: 1)
        let capReveal = CapacityDockMetrics.settingsCapSlot(scale: 1.2) * model.railPresentationProgress
        #expect(vertical.width == CapacityDockMetrics.railWidth(scale: 1.2))
        #expect(vertical.height == model.targetBodyLength + capReveal)

        model.attachmentEdge = .top
        let horizontal = model.targetPanelSize(forAttachmentProgress: 1)
        #expect(horizontal.width == model.targetBodyLength + capReveal)
        #expect(horizontal.height == CapacityDockMetrics.horizontalRailWidth(scale: 1.2))
    }

    @MainActor
    @Test("Detached rail reserves an external settings slot instead of a scoop peek")
    func detachedRailReservesExternalSettingsSlot() {
        let suite = "CodeBurnMenubarTests.CapacityDock.DetachedSlot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))
        model.isRailPresentationExpanded = true
        model.railPresentationProgress = 1
        model.attachmentProgress = 0

        let size = model.panelSize
        #expect(size.height == model.bodyLength + CapacityDockMetrics.settingsCapDetachedSlot(scale: model.scale))
        let bounds = CGRect(origin: .zero, size: size)
        let body = model.notchBodyFrame(in: bounds)
        let cap = model.settingsCapFrame(in: bounds)
        #expect(cap.minY >= body.maxY)
        #expect(abs(cap.midX - body.midX) < 0.5)
    }

    @Test("Expanding the rail keeps the top scoop identical to rest")
    func expansionKeepsTopScoop() {
        let restHeight: CGFloat = 168
        let expandedHeight: CGFloat = 312
        let rest = CapacityDockRailShape(
            bodyWidth: 72,
            bodyLength: restHeight,
            restLength: restHeight,
            shoulderDepth: 72,
            attachmentProgress: 1,
            edge: .right
        ).path(in: CGRect(x: 0, y: 0, width: 72, height: restHeight))
        let expanded = CapacityDockRailShape(
            bodyWidth: 72,
            bodyLength: expandedHeight,
            restLength: restHeight,
            shoulderDepth: 72,
            attachmentProgress: 1,
            edge: .right
        ).path(in: CGRect(x: 0, y: 0, width: 72, height: expandedHeight))

        for y in stride(from: CGFloat(1), through: 48, by: 3) {
            for x in stride(from: CGFloat(1), through: 71, by: 5) {
                #expect(
                    rest.contains(CGPoint(x: x, y: y)) == expanded.contains(CGPoint(x: x, y: y))
                )
            }
        }
    }

    @Test("Docked silhouette flares smoothly into one flush contact chord without horns")
    func dockedRailSilhouette() {
        let path = CapacityDockRailShape(bodyWidth: 88, bodyLength: 356, attachmentProgress: 1, edge: .right)
            .path(in: CGRect(x: 0, y: 0, width: 88, height: 356))

        // Free (left) corners and the necked long-axis ends stay open; the flush
        // contact chord fills the right edge along the body's full-width span.
        #expect(!path.contains(CGPoint(x: 2, y: 2)))
        #expect(!path.contains(CGPoint(x: 2, y: 354)))
        #expect(!path.contains(CGPoint(x: 44, y: 2)))
        #expect(!path.contains(CGPoint(x: 44, y: 354)))
        #expect(path.contains(CGPoint(x: 82, y: 178)))
        #expect(path.contains(CGPoint(x: 82, y: 300)))
        #expect(path.contains(CGPoint(x: 86, y: 30)))
        #expect(path.contains(CGPoint(x: 86, y: 178)))
        #expect(path.contains(CGPoint(x: 86, y: 326)))
    }

    @Test("Meniscus contact grows outward from the center of the attached edge")
    func meniscusContactGrowth() {
        let rect = CGRect(x: 0, y: 0, width: 88, height: 112)
        let detached = CapacityDockRailShape(bodyWidth: 88, attachmentProgress: 0, edge: .right)
            .path(in: rect)
        let halfAttached = CapacityDockRailShape(bodyWidth: 88, attachmentProgress: 0.5, edge: .right)
            .path(in: rect)
        let attached = CapacityDockRailShape(bodyWidth: 88, attachmentProgress: 1, edge: .right)
            .path(in: rect)

        // Detached: a rounded pill — filled across the top center, empty at the corners.
        #expect(detached.contains(CGPoint(x: 44, y: 2)))
        #expect(!detached.contains(CGPoint(x: 86, y: 2)))
        // Half attached: the right edge begins flushing against the surface at center height.
        #expect(halfAttached.contains(CGPoint(x: 86, y: rect.midY)))
        #expect(!halfAttached.contains(CGPoint(x: 86, y: 2)))
        // Fully attached: the contact holds at the center of the edge while the neck
        // pulls the top center away from it.
        #expect(attached.contains(CGPoint(x: 86, y: rect.midY)))
        #expect(!attached.contains(CGPoint(x: 44, y: 2)))
    }

    @Test("Meniscus interpolation changes continuously while staying inside the panel")
    func meniscusInterpolationIsContinuous() {
        let rect = CGRect(x: 0, y: 0, width: 88, height: 112)
        let sampleProgress: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let contactSpans = sampleProgress.map { progress in
            let path = CapacityDockRailShape(
                bodyWidth: 88,
                attachmentProgress: progress,
                edge: .right
            ).path(in: rect)
            return stride(from: 1, through: 111, by: 1).filter { y in
                path.contains(CGPoint(x: 87, y: CGFloat(y)))
            }.count
        }

        // The deepening neck at full attachment settles the near-edge span slightly,
        // so contact is not strictly monotonic; it still grows from detached to
        // attached, every attached state exceeds the detached widget, and each step
        // stays continuous (no jumps).
        #expect(contactSpans.first! < contactSpans.last!)
        #expect(contactSpans.dropFirst(2).allSatisfy { $0 > contactSpans[0] })
        #expect(zip(contactSpans, contactSpans.dropFirst()).allSatisfy { current, next in
            abs(next - current) < 44
        })
    }

    @Test("Detached silhouette retracts into a fully rounded widget")
    func detachedRailSilhouette() {
        let path = CapacityDockRailShape(bodyWidth: 88, attachmentProgress: 0, edge: .right)
            .path(in: CGRect(x: 0, y: 0, width: 88, height: 112))

        #expect(!path.contains(CGPoint(x: 3, y: 3)))
        #expect(!path.contains(CGPoint(x: 85, y: 3)))
        #expect(path.contains(CGPoint(x: 44, y: 3)))
        #expect(path.contains(CGPoint(x: 85, y: 56)))
    }

    @Test("Surface-tension silhouette mirrors across every screen edge")
    func edgeAttachmentMirrors() {
        let right = CapacityDockRailShape(bodyWidth: 88, bodyLength: 356, attachmentProgress: 1, edge: .right)
            .path(in: CGRect(x: 0, y: 0, width: 88, height: 356))
        let left = CapacityDockRailShape(bodyWidth: 88, bodyLength: 356, attachmentProgress: 1, edge: .left)
            .path(in: CGRect(x: 0, y: 0, width: 88, height: 356))
        let top = CapacityDockRailShape(bodyWidth: 88, bodyLength: 356, attachmentProgress: 1, edge: .top)
            .path(in: CGRect(x: 0, y: 0, width: 356, height: 88))
        let bottom = CapacityDockRailShape(bodyWidth: 88, bodyLength: 356, attachmentProgress: 1, edge: .bottom)
            .path(in: CGRect(x: 0, y: 0, width: 356, height: 88))

        // Each edge flushes its contact chord along the full-width span at mid-length
        // while the long-axis ends neck open — so the flush side is identified by a
        // near-edge mid-length point being filled and the free side staying empty.
        #expect(!right.contains(CGPoint(x: 44, y: 2)))
        #expect(right.contains(CGPoint(x: 82, y: 178)))
        #expect(left.contains(CGPoint(x: 2, y: 178)))
        #expect(left.contains(CGPoint(x: 6, y: 300)))
        #expect(!left.contains(CGPoint(x: 86, y: 2)))
        #expect(!left.contains(CGPoint(x: 44, y: 2)))
        #expect(top.contains(CGPoint(x: 178, y: 2)))
        #expect(top.contains(CGPoint(x: 300, y: 6)))
        #expect(!top.contains(CGPoint(x: 2, y: 86)))
        #expect(!top.contains(CGPoint(x: 2, y: 44)))
        #expect(bottom.contains(CGPoint(x: 178, y: 86)))
        #expect(bottom.contains(CGPoint(x: 300, y: 82)))
        #expect(!bottom.contains(CGPoint(x: 2, y: 2)))
        #expect(!bottom.contains(CGPoint(x: 2, y: 44)))
    }

    @MainActor
    @Test("Selected provider identity remains stable throughout reveal and retraction")
    func selectedProviderIdentityStaysStable() {
        let suite = "CodeBurnMenubarTests.CapacityDock.Identity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        CapacityDockPreferences.setPreferredProvider(.codex, defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))
        model.hoveredProvider = .codex
        model.isRailPresentationExpanded = true

        for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            model.railPresentationProgress = progress
            #expect(model.displayedProviders.first == .codex)
            #expect(model.hoveredProvider == .codex)
        }

        model.isRailPresentationExpanded = false
        model.railPresentationProgress = 0
        #expect(model.displayedProviders == [.codex])
        #expect(model.hoveredProvider == .codex)
    }

    @MainActor
    @Test("Resting provider stays visible when the rail expands toward its start edge")
    func restingProviderNeverFlashesToAnotherIcon() {
        let suite = "CodeBurnMenubarTests.CapacityDock.NoIconFlash.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        CapacityDockPreferences.setSelectedProviders([.codex, .claude, .gemini], defaults: defaults)
        CapacityDockPreferences.setPreferredProvider(.codex, defaults: defaults)
        let model = CapacityDockViewModel(preferences: CapacityDockPreferences.load(defaults: defaults))
        model.isRailPresentationExpanded = true
        model.expansionAnchor = .end
        model.railPresentationProgress = 0

        #expect(model.displayedProviders == [.gemini, .claude, .codex])
        #expect(model.presentationOpacity(for: .codex) == 1)
        #expect(model.presentationOpacity(for: .gemini) == 0)
        #expect(model.presentationOpacity(for: .claude) == 0)
    }

    @Test("Squircle gauge keeps the channel inset while using continuous corners")
    func squircleGaugePath() {
        let rect = CGRect(x: 0, y: 0, width: 52, height: 52)
        let path = CapacityDockGaugePath(kind: .squircle).path(in: rect)

        #expect(path.contains(CGPoint(x: 26, y: 1)))
        #expect(path.contains(CGPoint(x: 1, y: 26)))
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
    }

    @Test("Detail card pointer grows from a broad curved neck")
    func detailPointerNeck() {
        let path = CapacityDockBubbleShape(tailEdge: .right)
            .path(in: CGRect(x: 0, y: 0, width: 350, height: 220))

        #expect(path.contains(CGPoint(x: 331, y: 85)))
        #expect(path.contains(CGPoint(x: 346, y: 110)))
        #expect(path.contains(CGPoint(x: 331, y: 135)))
        #expect(!path.contains(CGPoint(x: 346, y: 80)))
    }

    @Test("Clamped detail pointer remains aligned to the provider row")
    func detailPointerOffset() {
        let rect = CGRect(x: 0, y: 0, width: 350, height: 220)
        let path = CapacityDockBubbleShape(tailEdge: .right, tailPosition: 0.25)
            .path(in: rect)

        #expect(path.contains(CGPoint(x: 346, y: 55)))
        #expect(!path.contains(CGPoint(x: 346, y: 110)))
    }

    @Test("Long provider quota labels preserve their time window")
    func compactQuotaLabels() {
        #expect(CapacityDockQuotaPresentation.displayLabel("Gemini Models · Five-hour") == "5h limit")
        #expect(CapacityDockQuotaPresentation.displayLabel("Gemini Models · Weekly") == "Weekly limit")
        #expect(CapacityDockQuotaPresentation.displayLabel("Claude and GPT models · Five-hour") == "5h limit")
        #expect(CapacityDockQuotaPresentation.displayLabel("Claude and GPT models · Weekly") == "Weekly limit")
        #expect(CapacityDockQuotaPresentation.displayLabel("Weekly") == "Weekly limit")
        #expect(CapacityDockQuotaPresentation.compactPlanLabel("SuperGrok Heavy") == "Heavy")
        #expect(CapacityDockQuotaPresentation.compactPlanLabel("SuperGrok") == "SuperGrok")
        #expect(CapacityDockQuotaPresentation.compactPlanLabel("Pro") == "Pro")
    }

    @Test("terminal diagnostics are not repeated in the footer")
    func terminalFooterDeduplicates() {
        let reason = "No available fetch strategy for clinepass."
        let lines = CapacityDockQuotaPresentation.visibleFooterLines(
            [reason, "Source: ClinePass"],
            connection: .terminalFailure(reason: reason)
        )

        #expect(lines == ["Source: ClinePass"])
    }

    @Test("terminal recovery cards reserve enough height for wrapped guidance and the action")
    func terminalCardHeight() {
        let reason = "No available fetch strategy for clinepass."
        let quota = QuotaSummary(
            providerFilter: .all,
            connection: .terminalFailure(reason: reason),
            primary: nil,
            details: [],
            planLabel: nil,
            footerLines: [reason]
        )

        #expect(CapacityDockMetrics.detailHeight(quota: quota, scale: 1) >= 216)
    }

    @MainActor
    @Test("Curated vectors win while existing CodeBurn artwork remains a fallback")
    func bundledArtworkWins() {
        let candidates = ProviderIconCache.resourceCandidates(for: "antigravity")
        #expect(candidates.first?.name == "provider-antigravity")
        #expect(candidates.first?.fileExtension == "svg")
        #expect(candidates.last?.name == "antigravity")
        #expect(candidates.last?.fileExtension == "png")
    }

    @Test("Dock selection candidates contain only eligible providers")
    func connectedSelectionCandidates() {
        let eligibleIDs: Set<String> = ["codex", "claude", "antigravity"]
        let providers = CapacityDockProviderSelection.eligibleProviders {
            eligibleIDs.contains($0.id)
        }

        #expect(providers.map(\.id) == ["codex", "claude", "antigravity"])
        #expect(!providers.contains { $0.id == "clinepass" })
    }

    @Test("saved credentials only make implemented adapters dock-eligible")
    func unsupportedCredentialsAreNotConnections() {
        let clinePass = CapacityDockProvider(rawValue: "clinepass")!
        let openRouter = CapacityDockProvider(rawValue: "openrouter")!

        #expect(CapacityDockProviderSelection.isDockEligible(
            clinePass,
            isConnected: false,
            hasSavedCredential: true
        ))
        #expect(!CapacityDockProviderSelection.isDockEligible(
            openRouter,
            isConnected: false,
            hasSavedCredential: true
        ))
    }

    @Test("Selected providers remain manageable when their live connection breaks")
    func selectedProvidersRemainManageable() {
        let selected: [CapacityDockProvider] = [.codex, CapacityDockProvider(rawValue: "clinepass")!]
        let providers = CapacityDockProviderSelection.manageableProviders(
            selected: selected,
            isConnected: { $0 == .codex || $0 == .claude }
        )

        #expect(providers.map(\.id) == ["codex", "claude", "clinepass"])
        #expect(CapacityDockProviderSelection.canDeselect(
            CapacityDockProvider(rawValue: "clinepass")!,
            selected: selected,
            isConnected: { $0 == .codex }
        ))
        #expect(!CapacityDockProviderSelection.canDeselect(
            .codex,
            selected: [.codex],
            isConnected: { $0 == .codex }
        ))
    }

    @Test("Credential-only providers receive an actionable connection instruction")
    func apiCredentialGuidance() {
        let provider = CapacityDockProvider(rawValue: "clinepass")!
        #expect(ProviderConnectionGuidance.instruction(for: provider) ==
            "Enter an API key or token below, then press Save & Connect.")
    }

    @Test("Browser-session providers receive an actionable connection instruction")
    func browserSessionGuidance() {
        let provider = CapacityDockProvider(rawValue: "commandcode")!
        #expect(ProviderConnectionGuidance.instruction(for: provider) ==
            "Sign in to Command Code in a supported browser, then click Retry.")
    }

    @Test("Grok Build offers direct one-click local login discovery")
    func grokBuildConnectionGuidance() {
        let provider = CapacityDockProvider(rawValue: "grok")!
        #expect(ProviderConnectionGuidance.instruction(for: provider) ==
            "Sign in with the Grok app or CLI, then click Retry.")
        #expect(ProviderConnectionSubmissionPolicy.resolve(
            credential: CapacityDockProviderCredential(),
            savedCredential: CapacityDockProviderCredential(),
            requiresExplicitCredential: false
        ) == .connect)
    }

    @Test("Connect saves edited credentials before fetching")
    func connectionSubmissionPolicy() {
        let empty = CapacityDockProviderCredential()
        let edited = CapacityDockProviderCredential(sourceMode: "api", apiKey: "synthetic")

        #expect(ProviderConnectionSubmissionPolicy.resolve(
            credential: edited,
            savedCredential: empty,
            requiresExplicitCredential: true
        ) == .saveAndConnect)
        #expect(ProviderConnectionSubmissionPolicy.resolve(
            credential: edited,
            savedCredential: edited,
            requiresExplicitCredential: true
        ) == .connect)
        #expect(ProviderConnectionSubmissionPolicy.resolve(
            credential: empty,
            savedCredential: empty,
            requiresExplicitCredential: true
        ) == .requiresCredential)
    }
}
