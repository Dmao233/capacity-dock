import Foundation
import Testing
@testable import CapacityDock

@Suite("Display currency")
struct DisplayCurrencyTests {
    @Test("CodeBurn compact strings convert USD by the display rate")
    func formatsLikeCodeBurn() {
        #expect(DisplayCurrency.usd.compactAmount(12.34) == "$12.34")
        #expect(DisplayCurrency.usd.compactWhole(12.34) == "$12")
        #expect(DisplayCurrency.usd.menubarText(amount: 12.34) == " $12.34")
        #expect(DisplayCurrency.usd.menubarText(amount: nil) == " $—")

        let cny = DisplayCurrency(code: "CNY", rate: 6.7191, symbol: "¥")
        #expect(cny.compactAmount(12.34) == "¥82.91")
        #expect(cny.menubarText(amount: 12.34) == " ¥82.91")
        #expect(cny.menubarText(amount: nil) == " ¥—")
        #expect(MenubarBillBadge.amount(12.34).menubarText(currency: cny) == " ¥82.91")
    }

    @Test("grouped ledger keeps two decimals and the CodeBurn symbol")
    func groupedLedger() {
        let cny = DisplayCurrency(code: "CNY", rate: 6.7191, symbol: "¥")
        #expect(cny.grouped(1000) == "¥6,719.10")
        #expect(TokenConsumptionFormatting.money(12.34, currency: .usd) == "$12.34")
    }

    @Test("CodeBurn config currency is inherited and written back")
    func sharedCodeBurnFileRoundTrip() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-fx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = CodeBurnCurrencyFile(home: home)
        #expect(file.loadCode() == nil)

        file.persist(code: "CNY")
        #expect(file.loadCode() == "CNY")
        let data = try SafeFile.read(
            from: home.appendingPathComponent(".config/codeburn/config.json").path
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let currency = json?["currency"] as? [String: Any]
        #expect(currency?["code"] as? String == "CNY")
        #expect(currency?["symbol"] as? String == "¥")

        file.persist(code: "USD")
        #expect(file.loadCode() == nil)
    }

    @Test("invalid or oversized existing CodeBurn files are never replaced", arguments: ["malformed", "array", "oversized"])
    func preservesInvalidConfig(kind: String) throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent(".config/codeburn/config.json").path
        let contents = kind == "malformed" ? "{broken" : kind == "array" ? "[]" : String(repeating: " ", count: 256 * 1024 + 1)
        let original = Data(contents.utf8)
        try SafeFile.write(original, to: path)
        #expect(!CodeBurnCurrencyFile(home: home).persist(code: "CNY"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == original)
    }

    @Test("CodeBurn synchronization preserves other settings and refuses symlinks")
    func preservesOtherSettings() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent(".config/codeburn/config.json").path
        let original = Data(#"{"theme":"dark","currency":{"code":"EUR","custom":true}}"#.utf8)
        try SafeFile.write(original, to: path)
        let file = CodeBurnCurrencyFile(home: home)
        #expect(file.persist(code: "CNY"))
        let json = try #require(JSONSerialization.jsonObject(with: SafeFile.read(from: path)) as? [String: Any])
        #expect(json["theme"] as? String == "dark")
        #expect((json["currency"] as? [String: Any])?["custom"] as? Bool == true)
        #expect(file.persist(code: "USD"))
        let usd = try #require(JSONSerialization.jsonObject(with: SafeFile.read(from: path)) as? [String: Any])
        #expect(usd["theme"] as? String == "dark")
        #expect(usd["currency"] == nil)

        let target = home.appendingPathComponent("original.json")
        try original.write(to: target)
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target.path)
        #expect(!file.persist(code: "CNY"))
        #expect(try Data(contentsOf: target) == original)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: path) == target.path)
    }

    @Test("a late exchange rate cannot overwrite a newer selection")
    @MainActor
    func latestCurrencyWins() async throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "capacity-dock-currency-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rates = DelayedCurrencyRates()
        let file = CodeBurnCurrencyFile(home: home)
        let state = DisplayCurrencyState(defaults: defaults, sharedFile: file, rates: rates)
        let first = state.select("CNY")
        await rates.waitForRequest()
        await state.select("USD").value
        await rates.finish(7)
        await first.value
        #expect(state.snapshot == .usd)
        #expect(CapacityDockPreferences.currencyCode(defaults: defaults) == "USD")
        #expect(file.loadCode() == nil)
        #expect(!state.isUpdating)
        #expect(state.errorMessage == nil)
    }

    @Test("a failed rate leaves the displayed and saved currencies aligned")
    @MainActor
    func failedRateDoesNotSaveSelection() async throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "capacity-dock-currency-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = CodeBurnCurrencyFile(home: home)
        let state = DisplayCurrencyState(defaults: defaults, sharedFile: file, rates: FixedCurrencyRates())
        await state.select("USD").value
        await state.select("CNY").value
        #expect(state.snapshot == .usd)
        #expect(CapacityDockPreferences.currencyCode(defaults: defaults) == "USD")
        #expect(file.loadCode() == nil)
        #expect(state.errorMessage != nil)
        #expect(!state.isUpdating)
    }

    @Test("cached rates work offline and a config error is reported without losing its contents")
    @MainActor
    func cachedRateWithConfigFailure() async throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent(".config/codeburn/config.json").path
        let original = Data("{broken".utf8)
        try SafeFile.write(original, to: path)
        let suite = "capacity-dock-currency-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = DisplayCurrencyState(
            defaults: defaults, sharedFile: CodeBurnCurrencyFile(home: home),
            rates: FixedCurrencyRates(cached: 7)
        )
        await state.select("CNY").value
        #expect(state.snapshot.grouped(10) == "¥70.00")
        #expect(CapacityDockPreferences.currencyCode(defaults: defaults) == "CNY")
        #expect(state.errorMessage != nil)
        #expect(try SafeFile.read(from: path) == original)
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("capacity-dock-fx-\(UUID().uuidString)")
    }
}

private struct FixedCurrencyRates: FXRateProviding {
    var cached: Double? = nil
    func cachedRate(for code: String) async -> Double? { cached }
    func rate(for code: String) async -> Double? { nil }
}

private actor DelayedCurrencyRates: FXRateProviding {
    private var continuation: CheckedContinuation<Double?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func cachedRate(for code: String) async -> Double? { nil }

    func rate(for code: String) async -> Double? {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitForRequest() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ rate: Double?) {
        continuation?.resume(returning: rate)
        continuation = nil
    }
}
