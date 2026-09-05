import SwiftUI

struct ConsumptionSettingsTab: View {
    var compactLayout = false
    @State private var period: TokenConsumptionPeriod = .today
    @State private var selectedProviderID = "all"
    @State private var snapshot: TokenConsumptionSnapshot?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLoading && snapshot == nil {
                loadingRow
            } else if let snapshot {
                providerChips(snapshot)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero(snapshot)
                        if snapshot.showsDailyTrend {
                            dailyTrend(snapshot)
                        }
                        modelsBlock(snapshot)
                        providersBlock(snapshot)
                        footer(snapshot)
                    }
                    .frame(maxWidth: compactLayout ? .infinity : 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(compactLayout ? 14 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: period) {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Your AI Bill, Itemized")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(NSLocalizedString("Reload local logs", comment: "")) {
                    Task { await load() }
                }
                .disabled(isLoading)
                .controlSize(compactLayout ? .small : .regular)
                .accessibilityHint(NSLocalizedString("Reads Claude, Codex, Grok, and Cursor usage logs on this Mac again.", comment: ""))
            }
            Picker(NSLocalizedString("Period", comment: ""), selection: $period) {
                ForEach(TokenConsumptionPeriod.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(NSLocalizedString("Period", comment: ""))
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading local logs…")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func providerChips(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let billed = snapshot.billedProviderRows
        if billed.count >= 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    providerChip(
                        id: "all",
                        title: NSLocalizedString("All", comment: ""),
                        amount: TokenConsumptionPresentation.heroAmount(snapshot.periodTotals)
                    )
                    ForEach(billed) { row in
                        providerChip(
                            id: row.providerID,
                            title: row.displayName,
                            amount: row.showsCurrency ? TokenConsumptionFormatting.usd(row.estimatedUSD ?? 0) : nil
                        )
                    }
                }
            }
            .accessibilityLabel(NSLocalizedString("Providers", comment: ""))
        }
    }

    private func providerChip(id: String, title: String, amount: String?) -> some View {
        let selected = selectedProviderID == id
        let label = amount.map { "\(title) \($0)" } ?? title
        return Button {
            selectedProviderID = id
        } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .help(label)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func hero(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let filter = selectedProviderID == "all" ? nil : selectedProviderID
        let totals = snapshot.totals(matching: filter)
        let kind = TokenConsumptionPresentation.heroKind(snapshot, providerID: filter)
        VStack(alignment: .leading, spacing: 8) {
            Text(TokenConsumptionPresentation.windowLabel(snapshot))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(TokenConsumptionPresentation.windowLabel(snapshot))

            switch kind {
            case .missingLogs:
                Text(emptyCopy)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .emptyPeriod:
                Text("No usage in this period")
                    .foregroundStyle(.secondary)
                    .help(NSLocalizedString("Logs exist, but this period has no token events.", comment: ""))
            case .billed:
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(TokenConsumptionPresentation.heroAmount(totals) ?? "")
                        .font(.system(size: compactLayout ? 28 : 32, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .help(NSLocalizedString("API-equivalent estimate, not a subscription charge.", comment: ""))
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        if totals.loggedEventCount > 0 {
                            Text(TokenConsumptionPresentation.callsText(totals.loggedEventCount))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(TokenConsumptionPresentation.callsText(totals.loggedEventCount))
                        }
                        Text(TokenConsumptionPresentation.tokensText(totals.tokenCount))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .help(TokenConsumptionPresentation.tokensText(totals.tokenCount))
                    }
                }
                tokenSecondary(totals)
                if totals.unpricedEventCount > 0 {
                    Text("Some calls unpriced")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help(NSLocalizedString("Estimated dollars use a small offline API price table. Calls without a matched model stay unpriced instead of showing $0.", comment: ""))
                }
            case .tokensOnly:
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(TokenConsumptionPresentation.tokensText(totals.tokenCount))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .help(TokenConsumptionPresentation.tokensText(totals.tokenCount))
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("No API estimate")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if totals.loggedEventCount > 0 {
                            Text(TokenConsumptionPresentation.callsText(totals.loggedEventCount))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                tokenSecondary(totals)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func tokenSecondary(_ totals: TokenConsumptionPeriodTotals) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: NSLocalizedString("In %@ · Out %@", comment: ""),
                    TokenConsumptionFormatting.tokens(totals.input),
                    TokenConsumptionFormatting.tokens(totals.output)
                )
            )
            .font(.system(size: 12).monospacedDigit())
            .lineLimit(1)
            .help(
                String(
                    format: NSLocalizedString("Input %@ tokens", comment: ""),
                    TokenConsumptionFormatting.tokens(totals.input)
                )
                + " · "
                + String(
                    format: NSLocalizedString("Output %@ tokens", comment: ""),
                    TokenConsumptionFormatting.tokens(totals.output)
                )
            )
            if totals.cacheRead > 0 || totals.cacheWrite > 0 || totals.reasoning > 0 {
                Text(detailLine(totals))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(detailLine(totals))
            }
        }
    }

    private func detailLine(_ totals: TokenConsumptionPeriodTotals) -> String {
        var parts: [String] = []
        if totals.cacheRead > 0 {
            parts.append(String(
                format: NSLocalizedString("Cache %@", comment: ""),
                TokenConsumptionFormatting.tokens(totals.cacheRead)
            ))
        }
        if totals.cacheWrite > 0 {
            parts.append(String(
                format: NSLocalizedString("Cache write %@", comment: ""),
                TokenConsumptionFormatting.tokens(totals.cacheWrite)
            ))
        }
        if totals.reasoning > 0 {
            parts.append(String(
                format: NSLocalizedString("Reason %@", comment: ""),
                TokenConsumptionFormatting.tokens(totals.reasoning)
            ))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func dailyTrend(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let maxTokens = snapshot.daily.map(\.tokenCount).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            Text("Days with logged usage")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(snapshot.daily) { day in
                    let fraction = CGFloat(day.tokenCount) / CGFloat(max(maxTokens, 1))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, 56 * fraction))
                        .help(dayHelp(day))
                        .accessibilityLabel(dayHelp(day))
                }
            }
            .frame(height: 56, alignment: .bottom)
        }
    }

    private func dayHelp(_ day: TokenConsumptionDay) -> String {
        var parts = [
            day.day,
            TokenConsumptionPresentation.tokensText(day.tokenCount),
            TokenConsumptionPresentation.callsText(day.calls)
        ]
        if day.showsCurrency, let usd = day.estimatedUSD {
            parts.insert(TokenConsumptionFormatting.usd(usd), at: 1)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func modelsBlock(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let filter = selectedProviderID == "all" ? nil : selectedProviderID
        let models = snapshot.modelRows(matching: filter)
        if !models.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Models")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Cost")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("Calls")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                ForEach(models) { model in
                    HStack(spacing: 8) {
                        Text(model.shortName)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .help(model.model)
                        Spacer(minLength: 8)
                        Text(model.showsCurrency ? TokenConsumptionFormatting.usd(model.estimatedUSD ?? 0) : "—")
                            .font(.system(size: 12, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .help(
                                model.showsCurrency
                                    ? NSLocalizedString("API-equivalent estimate, not a subscription charge.", comment: "")
                                    : NSLocalizedString("No API estimate", comment: "")
                            )
                        Text("\(model.pricedEventCount + model.unpricedEventCount)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .trailing)
                            .help(TokenConsumptionPresentation.callsText(model.pricedEventCount + model.unpricedEventCount))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func providersBlock(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let rows: [TokenConsumptionRow] = {
            if selectedProviderID == "all" { return snapshot.ledgerRows }
            return snapshot.ledgerRows.filter { $0.providerID == selectedProviderID }
        }()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Providers")
                    .font(.subheadline.weight(.semibold))
                ForEach(rows) { row in
                    ConsumptionLedgerRow(row: row, period: snapshot.period)
                }
            }
        }
    }

    private func footer(_ snapshot: TokenConsumptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Estimates ≠ subscription bill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(sectionFooter(snapshot))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyCopy: String {
        NSLocalizedString("No local token logs on this Mac. Use Claude Code, Codex CLI, or Grok Build first so JSONL usage appears, then press Reload local logs. This page will not invent $0.", comment: "")
    }

    private func sectionFooter(_ snapshot: TokenConsumptionSnapshot) -> String {
        if snapshot.hasAnyMeasuredRow {
            return NSLocalizedString("Dollars use the same calculateCost pipeline as CodeBurn. Unknown models add $0.", comment: "")
        }
        return NSLocalizedString("A missing token log is not a $0 bill.", comment: "")
    }

    private func load() async {
        isLoading = true
        let chosen = period
        let result = await Task.detached(priority: .userInitiated) {
            LocalTokenLogReader.load(period: chosen)
        }.value
        guard chosen == period else { return }
        snapshot = result
        if selectedProviderID != "all",
           result.billedProviderRows.contains(where: { $0.providerID == selectedProviderID }) == false {
            selectedProviderID = "all"
        }
        isLoading = false
    }
}

private struct ConsumptionLedgerRow: View {
    let row: TokenConsumptionRow
    let period: TokenConsumptionPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let image = ProviderIconCache.image(named: iconName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                }
                Text(row.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .help(row.displayName)
                Spacer(minLength: 8)
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(statusHelp)
            }

            switch row.availability {
            case .logged:
                if row.showsMeasuredZero {
                    Text("No usage in this period")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help(NSLocalizedString("Logs exist, but this period has no token events.", comment: ""))
                } else {
                    Text(tokenLine)
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .help(tokenHelp)
                    Text(amountLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(amountHelp)
                    if row.totals.cacheRead > 0 || row.totals.cacheWrite > 0 || row.totals.reasoning > 0 {
                        Text(detailLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .help(tokenHelp)
                    }
                }
            case .cursorHashOnly:
                Text("Cursor has no token log yet. The Composer tracking database stores file hashes, not tokens.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .noLocalTokenLog:
                Text("The quota ring can show percent remaining, but this Mac has no token log for this provider.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .unreadable:
                Text("Could not read this provider’s local log. Check folder permissions, then press Reload local logs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var iconName: String {
        CapacityDockProvider(rawValue: row.providerID)?.iconName ?? row.providerID
    }

    private var statusLabel: String {
        switch row.availability {
        case .logged:
            return row.showsMeasuredZero
                ? NSLocalizedString("Logged, idle", comment: "")
                : NSLocalizedString("From local logs", comment: "")
        case .cursorHashOnly, .noLocalTokenLog:
            return NSLocalizedString("No token log", comment: "")
        case .unreadable:
            return NSLocalizedString("Unread", comment: "")
        }
    }

    private var statusHelp: String {
        switch row.availability {
        case .logged:
            return period.title
        case .cursorHashOnly:
            return NSLocalizedString("Cursor hashes are not tokens.", comment: "")
        case .noLocalTokenLog:
            return NSLocalizedString("Use the quota ring for percent remaining.", comment: "")
        case .unreadable:
            return NSLocalizedString("Reload after fixing permissions.", comment: "")
        }
    }

    private var tokenLine: String {
        String(
            format: NSLocalizedString("In %@ · Out %@", comment: ""),
            TokenConsumptionFormatting.tokens(row.totals.input),
            TokenConsumptionFormatting.tokens(row.totals.displayOutput)
        )
    }

    private var detailLine: String {
        var parts: [String] = []
        if row.totals.cacheRead > 0 {
            parts.append(String(
                format: NSLocalizedString("Cache %@", comment: ""),
                TokenConsumptionFormatting.tokens(row.totals.cacheRead)
            ))
        }
        if row.totals.cacheWrite > 0 {
            parts.append(String(
                format: NSLocalizedString("Cache write %@", comment: ""),
                TokenConsumptionFormatting.tokens(row.totals.cacheWrite)
            ))
        }
        if row.totals.reasoning > 0 {
            parts.append(String(
                format: NSLocalizedString("Reason %@", comment: ""),
                TokenConsumptionFormatting.tokens(row.totals.reasoning)
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var tokenHelp: String {
        var parts = [
            String(format: NSLocalizedString("Input %@ tokens", comment: ""), TokenConsumptionFormatting.tokens(row.totals.input)),
            String(format: NSLocalizedString("Output %@ tokens", comment: ""), TokenConsumptionFormatting.tokens(row.totals.displayOutput))
        ]
        if row.totals.cacheRead > 0 {
            parts.append(String(
                format: NSLocalizedString("Cache read %@ tokens", comment: ""),
                TokenConsumptionFormatting.tokens(row.totals.cacheRead)
            ))
        }
        if row.totals.cacheWrite > 0 {
            parts.append(String(
                format: NSLocalizedString("Cache write %@ tokens", comment: ""),
                TokenConsumptionFormatting.tokens(row.totals.cacheWrite)
            ))
        }
        if row.totals.reasoning > 0 {
            parts.append(String(
                format: NSLocalizedString("Reasoning %@ tokens", comment: ""),
                TokenConsumptionFormatting.tokens(row.totals.reasoning)
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var amountLine: String {
        if row.showsCurrency, let usd = row.estimatedUSD {
            let money = TokenConsumptionFormatting.usd(usd)
            if row.unpricedEventCount > 0 {
                return String(format: NSLocalizedString("Est. %@ · some calls unpriced", comment: ""), money)
            }
            return money
        }
        return NSLocalizedString("No API estimate", comment: "")
    }

    private var amountHelp: String {
        NSLocalizedString("API-equivalent estimate, not a subscription charge.", comment: "")
    }

    private var accessibilitySummary: String {
        var parts = [row.displayName, period.title, statusLabel]
        if row.availability == .logged, !row.showsMeasuredZero {
            parts.append(tokenHelp)
            parts.append(amountLine)
        }
        return parts.joined(separator: ", ")
    }
}
