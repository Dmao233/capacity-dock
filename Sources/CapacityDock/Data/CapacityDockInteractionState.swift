import Foundation

/// Immediate interaction truth for Capacity Dock. Hover/collapse delays are
/// scheduled by the controller; this value only decides whether a delayed
/// action is still valid when it fires.
struct CapacityDockInteractionState: Equatable, Sendable {
    private(set) var isRailHovered = false
    private(set) var isDetailHovered = false
    private(set) var isSettingsHovered = false
    private(set) var isPinned = false
    private(set) var isCollapseGraceActive = false
    private(set) var isDragging = false

    init(
        isRailHovered: Bool = false,
        isDetailHovered: Bool = false,
        isSettingsHovered: Bool = false,
        isPinned: Bool = false
    ) {
        self.isRailHovered = isRailHovered
        self.isDetailHovered = isDetailHovered
        self.isSettingsHovered = isSettingsHovered
        self.isPinned = isPinned
    }

    var isExpanded: Bool {
        isRailHovered || isDetailHovered || isSettingsHovered
            || isCollapseGraceActive
    }
    var canCollapse: Bool {
        !isRailHovered && !isDetailHovered && !isSettingsHovered
            && !isCollapseGraceActive && !isDragging
    }
    var acceptsHoverTransitions: Bool { !isDragging }

    mutating func setRailHovered(_ hovered: Bool) {
        isRailHovered = hovered
        if hovered { isCollapseGraceActive = false }
    }

    mutating func beginRailExitGrace() {
        isRailHovered = false
        isCollapseGraceActive = true
    }

    mutating func completeCollapseGrace() {
        isCollapseGraceActive = false
    }

    mutating func beginDragging() {
        isDragging = true
    }

    mutating func endDragging() {
        isDragging = false
    }

    mutating func setDetailHovered(_ hovered: Bool) {
        isDetailHovered = hovered
    }

    mutating func setSettingsHovered(_ hovered: Bool) {
        isSettingsHovered = hovered
        if hovered { isCollapseGraceActive = false }
    }

    mutating func togglePinned() {
        isPinned.toggle()
    }

    mutating func dismiss() {
        self = CapacityDockInteractionState()
    }

    @discardableResult
    mutating func handleEscape() -> Bool {
        guard isExpanded || isPinned else { return false }
        dismiss()
        return true
    }
}
