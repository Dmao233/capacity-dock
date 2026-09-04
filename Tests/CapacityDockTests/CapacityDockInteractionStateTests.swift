import Testing
@testable import CapacityDock

@Suite("Capacity Dock interaction state")
struct CapacityDockInteractionStateTests {
    @Test("rail exit stays expanded until the collapse grace period completes")
    func railHoverLifecycle() {
        var state = CapacityDockInteractionState()

        state.setRailHovered(true)
        #expect(state.isExpanded)
        #expect(!state.canCollapse)

        state.beginRailExitGrace()
        #expect(state.isExpanded)
        #expect(!state.canCollapse)

        state.completeCollapseGrace()
        #expect(!state.isExpanded)
        #expect(state.canCollapse)
    }

    @Test("detail hover bridges the pointer gap after leaving the rail")
    func detailHoverKeepsExpanded() {
        var state = CapacityDockInteractionState()
        state.setRailHovered(true)
        state.setDetailHovered(true)
        state.beginRailExitGrace()
        state.completeCollapseGrace()

        #expect(state.isExpanded)
        #expect(!state.canCollapse)

        state.setDetailHovered(false)
        #expect(state.canCollapse)
    }

    @Test("settings cap hover holds the expanded notch without pinning")
    func settingsHoverHoldsExpanded() {
        var state = CapacityDockInteractionState(isRailHovered: true)
        state.beginRailExitGrace()
        state.setSettingsHovered(true)
        state.completeCollapseGrace()

        #expect(!state.canCollapse)
        #expect(state.isSettingsHovered)
        #expect(state.isExpanded)

        state.setSettingsHovered(false)
        #expect(state.canCollapse)
        #expect(!state.isExpanded)
    }

    @Test("outside click and Escape fully dismiss expanded interaction")
    func dismissesExpandedState() {
        var state = CapacityDockInteractionState(isRailHovered: true, isDetailHovered: true)

        state.dismiss()
        #expect(state == CapacityDockInteractionState())

        state.setRailHovered(true)
        let handled = state.handleEscape()
        #expect(handled)
        #expect(state == CapacityDockInteractionState())
        let handledAgain = state.handleEscape()
        #expect(!handledAgain)
    }

    @Test("dragging suppresses hover transitions")
    func draggingSuppressesHover() {
        var state = CapacityDockInteractionState(isRailHovered: true)

        state.beginDragging()
        #expect(state.isDragging)
        #expect(state.isExpanded)
        #expect(!state.acceptsHoverTransitions)

        state.endDragging()
        #expect(!state.isDragging)
        #expect(state.acceptsHoverTransitions)
    }

    @Test("dragging during collapse grace keeps the current rail geometry stable")
    func draggingPreservesCollapseGrace() {
        var state = CapacityDockInteractionState(isRailHovered: true)
        state.beginRailExitGrace()
        #expect(state.isExpanded)

        state.beginDragging()
        #expect(state.isExpanded)
        #expect(state.isCollapseGraceActive)
    }
}
