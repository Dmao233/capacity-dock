import SwiftUI

/// Settings and the menu-bar bill share one presentation and one cached reader.
struct ConsumptionSettingsTab: View {
    var body: some View {
        BillPopoverView(topInset: 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
