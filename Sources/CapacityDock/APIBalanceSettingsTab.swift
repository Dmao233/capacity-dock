import SwiftUI

struct APIBalanceSettingsTab: View {
    @State private var store = APIBalanceStore.shared
    @State private var draft = APIBalanceAccount()
    @State private var key = ""
    @State private var error: String?
    @State private var saving = false
    @State private var editing = false

    var body: some View {
        Form {
            Section {
                Text("菜单栏显示：API 剩余余额 ｜ ◉ 今日消耗总计")
                Text("右侧沿用本地日志的 API 等价估算。余额单独显示，不与今日金额相加；不同币种分别汇总。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("API 账户") }
            Section {
                if store.accounts.isEmpty {
                    Text("尚未添加 API 账户，菜单栏保持原样。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.accounts) { account in
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
                            Button("编辑") { draft = account; key = ""; error = nil; editing = true }
                            Button("移除", role: .destructive) {
                                saving = true
                                Task { @MainActor in
                                    defer { saving = false }
                                    do {
                                        try await store.remove(account)
                                        if draft.id == account.id { draft = APIBalanceAccount(); editing = false; key = "" }
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                        }.disabled(saving)
                    }.padding(.vertical, 4)
                }
                HStack {
                    Button(store.isRefreshing ? "正在更新…" : "刷新余额") { store.refresh(force: true) }
                        .disabled(store.isRefreshing || store.accounts.isEmpty)
                    Spacer()
                    Button("添加账户") { draft = APIBalanceAccount(); key = ""; error = nil; editing = false }
                }
            } header: { Text("已添加的账户") }
            Section {
                Picker("平台类型", selection: $draft.kind) {
                    Text("DeepSeek 官方").tag(APIBalanceAccount.Kind.deepSeek)
                    Text("自定义中转站").tag(APIBalanceAccount.Kind.relay)
                }.onChange(of: draft.kind) { _, kind in
                    if !editing { draft.name = kind == .deepSeek ? "DeepSeek" : "自定义中转站" }
                }
                TextField("账户名称", text: $draft.name)
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
                SecureField(editing ? "API 密钥（留空保留）" : "API 密钥", text: $key)
                Text("密钥保存在 macOS 钥匙串，仅向上方余额接口发送。保存后开始查询余额。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.orange).font(.callout) }
                Button(saving ? "正在保存…" : "保存并查询") {
                    saving = true
                    error = nil
                    let account = draft
                    let credential = key
                    Task { @MainActor in
                        defer { saving = false }
                        do {
                            try await store.save(account, key: credential)
                            key = ""
                            editing = true
                        } catch { self.error = error.localizedDescription }
                    }
                }
            } header: { Text(editing ? "编辑账户" : "添加账户") }
            .disabled(saving)
        }
        .disabled(saving)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
