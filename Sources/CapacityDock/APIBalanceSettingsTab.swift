import SwiftUI

struct APIBalanceSettingsTab: View {
    var kind: APIBalanceAccount.Kind? = nil
    @State private var store = APIBalanceStore.shared
    @State private var editorAccount: APIBalanceAccount?
    @State private var error: String?
    @State private var saving = false

    private var accounts: [APIBalanceAccount] { store.accounts.filter { kind == nil || $0.kind == kind } }

    private func newAccount() -> APIBalanceAccount {
        var account = APIBalanceAccount()
        if kind == .relay { account.kind = .relay; account.name = "自定义中转站" }
        return account
    }

    var body: some View {
        Form {
            Section {
                Text("菜单栏显示：API 剩余余额 ｜ ◉ 今日消耗总计")
                Text("右侧沿用本地日志的 API 等价估算。余额单独显示，不与今日金额相加；不同币种分别汇总。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("API 账户") }
            Section {
                if accounts.isEmpty {
                    Text("尚未添加 API 账户，菜单栏保持原样。")
                        .foregroundStyle(.secondary)
                }
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            APIBalanceLogo(account: account).frame(width: 18, height: 18)
                            Text(account.name).fontWeight(.semibold)
                            Spacer()
                            Text(store.snapshots[account.id]?.amounts.map(\.text).joined(separator: " · ") ?? "—")
                                .monospacedDigit()
                        }
                        if let snapshot = store.snapshots[account.id] {
                            Text("更新于 \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption).foregroundStyle(.secondary)
                            if snapshot.isAvailable == false {
                                Text("平台报告当前余额不可用于调用").font(.caption).foregroundStyle(.orange)
                            }
                            ForEach(snapshot.amounts, id: \.currency) { amount in
                                if let granted = amount.granted, let toppedUp = amount.toppedUp {
                                    Text("赠送 \(APIBalanceAmount(currency: amount.currency, value: granted).text) · 充值 \(APIBalanceAmount(currency: amount.currency, value: toppedUp).text)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let message = store.errors[account.id] {
                            Text(message + (store.snapshots[account.id] == nil ? "" : " 当前显示上次余额。"))
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("编辑") { error = nil; editorAccount = account }
                            Button("移除", role: .destructive) {
                                saving = true
                                Task { @MainActor in
                                    defer { saving = false }
                                    do {
                                        try await store.remove(account)
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                        }.disabled(saving)
                    }.padding(.vertical, 4)
                }
                HStack {
                    Button(store.isRefreshing ? "正在更新…" : "刷新余额") { store.refresh(force: true, kind: kind) }
                        .disabled(store.isRefreshing || accounts.isEmpty)
                    Spacer()
                    Button("添加账户") { error = nil; editorAccount = newAccount() }
                }
            } header: { Text("已添加的账户") }
            if let error {
                Section { Text(error).foregroundStyle(.orange).font(.callout) }
            }
        }
        .disabled(saving)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $editorAccount) { account in
            APIBalanceAccountEditor(account: account, editing: store.accounts.contains { $0.id == account.id })
        }
    }
}

private struct APIBalanceAccountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: APIBalanceAccount
    @State private var key = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var keyFocused: Bool
    let editing: Bool

    init(account: APIBalanceAccount, editing: Bool) {
        _draft = State(initialValue: account)
        self.editing = editing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing ? "编辑 API 账户" : "添加 API 账户")
                .font(.title3.weight(.semibold))
            Form {
                Picker("平台类型", selection: $draft.kind) {
                    Text("DeepSeek 官方").tag(APIBalanceAccount.Kind.deepSeek)
                    Text("自定义中转站").tag(APIBalanceAccount.Kind.relay)
                }.onChange(of: draft.kind) { old, kind in
                    let previousDefault = old == .deepSeek ? "DeepSeek" : "自定义中转站"
                    if !editing && draft.name == previousDefault {
                        draft.name = kind == .deepSeek ? "DeepSeek" : "自定义中转站"
                    }
                }
                TextField("账户名称", text: $draft.name, prompt: Text("为这个账户命名"))
                if draft.kind == .deepSeek {
                    LabeledContent("余额接口", value: "api.deepseek.com/user/balance")
                } else {
                    TextField("完整余额接口 URL", text: $draft.endpoint, prompt: Text("https://example.com/api/balance"))
                    TextField("金额 JSON 路径", text: $draft.amountPath, prompt: Text("data.balance"))
                    TextField("币种", text: $draft.currency, prompt: Text("USD 或 CNY"))
                    TextField("金额单位除数", text: $draft.divisor, prompt: Text("1"))
                    Text("GET 请求，使用 Authorization: Bearer 密钥。路径支持 data.balance、data.0.balance；以分为单位填除数 100，以元为单位填 1。请使用平台文档中的实际接口和单位。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField(editing ? "API 密钥（留空保留）" : "API 密钥", text: $key,
                            prompt: Text(editing ? "留空保留已保存的密钥" : "输入 API 密钥"))
                    .focused($keyFocused)
            }
            .textFieldStyle(.roundedBorder)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .disabled(saving)
            Text("密钥保存在 macOS 钥匙串，仅向上方余额接口发送。保存后开始查询余额。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.callout).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(saving ? "正在保存…" : "保存并查询", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }.disabled(saving)
        }
        .padding(20)
        .frame(width: 520, height: draft.kind == .deepSeek ? 390 : 560)
        .interactiveDismissDisabled(saving)
        .onAppear { if !editing { keyFocused = true } }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        error = nil
        draft.currency = draft.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let account = draft
        let credential = key
        Task { @MainActor in
            defer { saving = false }
            do {
                try await APIBalanceStore.shared.save(account, key: credential)
                key = ""
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct APIBalanceLogo: View {
    var account: APIBalanceAccount
    var body: some View {
        if account.kind == .deepSeek, let image = ProviderIconCache.image(named: "deepseek") {
            Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("DeepSeek")
        } else {
            Image(systemName: "server.rack").resizable().scaledToFit().accessibilityLabel(account.name)
        }
    }
}

/// A compact balance strip shared by the popover and the full usage page.
struct APIBalanceSummary: View {
    @State private var store = APIBalanceStore.shared
    @State private var expanded = false
    var body: some View {
        if !store.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { expanded.toggle() } label: {
                    HStack {
                        if store.accounts.count == 1, let account = store.accounts.first {
                            APIBalanceLogo(account: account).frame(width: 15, height: 15)
                        } else { Image(systemName: "creditcard") }
                        Text("API 剩余")
                        Spacer()
                        Text(store.menuText ?? "—").monospacedDigit()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 11, weight: .medium)).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if expanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(store.accounts) { account in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(account.name)
                                        Spacer()
                                        Text(store.snapshots[account.id]?.amounts.map(\.text).joined(separator: " · ") ?? "—")
                                    }
                                    if let message = store.errors[account.id] {
                                        Text(message).foregroundStyle(.orange)
                                    }
                                    if let snapshot = store.snapshots[account.id] {
                                        Text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard))")
                                            .foregroundStyle(.secondary)
                                    }
                                }.font(.system(size: 10))
                            }
                        }
                    }.frame(maxHeight: 90)
                    HStack {
                        Button("刷新") { store.refresh(force: true) }.disabled(store.isRefreshing)
                        Spacer()
                        Button("管理 API 账户") {
                            NotificationCenter.default.post(name: .capacityDockOpenProviderSettings, object: "api-balance")
                        }
                    }.font(.system(size: 10))
                }
            }.padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                .onAppear { store.refresh() }
        }
    }
}

/// Uses the same account snapshots as the menu bar; the widget never fetches its own copy.
struct APIBalanceDockDetail: View {
    let provider: CapacityDockProvider
    let kind: APIBalanceAccount.Kind
    let scale: CGFloat
    @State private var store = APIBalanceStore.shared

    var body: some View {
        let presentation = store.dockPresentation(for: kind)
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 8 * scale) {
                if let image = ProviderIconCache.image(named: provider.iconName) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 24 * scale, height: 24 * scale)
                }
                Text(provider.displayName).font(.system(size: 17 * scale, weight: .semibold))
                Spacer(minLength: 0)
                Text("API 余额").font(.system(size: 10 * scale)).foregroundStyle(.secondary)
            }
            if presentation.accounts.isEmpty {
                Text("请先在 API 账户设置中添加账户。")
                    .font(.system(size: 12 * scale)).foregroundStyle(.secondary)
            } else {
                Text("当前剩余").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                if let totals = presentation.totals {
                    ForEach(totals, id: \.currency) { amount in
                        Text(amount.text).font(.system(size: 24 * scale, weight: .semibold)).monospacedDigit()
                    }
                } else {
                    Text("—").font(.system(size: 24 * scale, weight: .semibold))
                    Text("部分账户尚无有效余额，暂不合计。")
                        .font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                }
                if presentation.isStale {
                    Text("当前显示上次余额，请查看更新时间。")
                        .font(.system(size: 10 * scale)).foregroundStyle(.orange)
                }
                Divider().overlay(.white.opacity(0.12))
                ForEach(presentation.accounts) { account in
                    VStack(alignment: .leading, spacing: 5 * scale) {
                        if presentation.accounts.count > 1 { Text(account.name).font(.system(size: 11 * scale, weight: .semibold)) }
                        if let snapshot = store.snapshots[account.id] {
                            ForEach(snapshot.amounts, id: \.currency) { amount in
                                if presentation.accounts.count > 1 { Text(amount.text).font(.system(size: 13 * scale)).monospacedDigit() }
                                if let granted = amount.granted, let toppedUp = amount.toppedUp {
                                    Text("充值 \(APIBalanceAmount(currency: amount.currency, value: toppedUp).text)")
                                    Text("赠送 \(APIBalanceAmount(currency: amount.currency, value: granted).text)")
                                }
                            }
                            if snapshot.isAvailable == false { Text("平台报告余额当前不可用").foregroundStyle(.orange) }
                            Text("更新于 \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                        }
                        if let error = store.errors[account.id] { Text(error).foregroundStyle(.orange) }
                        else if store.snapshots[account.id] == nil { Text(store.isRefreshing ? "正在查询余额…" : "等待余额更新") }
                    }.font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("刷新余额") { store.refresh(force: true, kind: kind) }
                    .disabled(store.isRefreshing || presentation.accounts.isEmpty)
                Spacer(minLength: 4)
                Button("管理账户") {
                    NotificationCenter.default.post(name: .capacityDockOpenProviderSettings, object: provider.id)
                }
            }.controlSize(.small)
        }
        .foregroundStyle(Color.capacityDockText)
        .environment(\.colorScheme, .dark)
        .fixedSize(horizontal: false, vertical: true)
    }
}
