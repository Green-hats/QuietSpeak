import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var client: ClientModel
    @State private var editing: ServerBookmark?
    @State private var adding = false
    @State private var lockedChannel: Channel?
    @State private var channelPassword = ""
    @AppStorage("nativeServerSidebarVisible") private var showServers = true
    @AppStorage("nativeChannelSidebarVisible") private var showChannels = true
    @State private var chatDraft = ""
    var body: some View {
        navigation.navigationSplitViewStyle(.balanced)
            .focusedSceneValue(\.channelSidebarVisibility, $showChannels)
            .sheet(isPresented: $client.showConnection) {
                ConnectionSheet(bookmark: client.selectedServer, isNew: false).environmentObject(
                    client)
            }
            .sheet(isPresented: $adding) {
                ConnectionSheet(bookmark: nil, isNew: true).environmentObject(client)
            }
            .sheet(item: $editing) { item in
                ConnectionSheet(bookmark: item, isNew: false).environmentObject(client)
            }
            .sheet(isPresented: $client.showSettings) { SettingsSheet().environmentObject(client) }
            .alert(
                "无法完成操作",
                isPresented: Binding(
                    get: { client.error != nil }, set: { if !$0 { client.error = nil } })
            ) {
                Button("好", role: .cancel) { client.error = nil }
            } message: {
                Text(client.error ?? "")
            }
            .alert(
                "频道密码",
                isPresented: Binding(
                    get: { lockedChannel != nil },
                    set: {
                        if !$0 {
                            lockedChannel = nil
                            channelPassword = ""
                        }
                    })
            ) {
                SecureField("请输入频道密码", text: $channelPassword)
                Button("加入") {
                    client.joinSelected(password: channelPassword)
                    lockedChannel = nil
                    channelPassword = ""
                }
                Button("取消", role: .cancel) {
                    lockedChannel = nil
                    channelPassword = ""
                }
            } message: {
                Text("加入 \(lockedChannel?.name ?? "")")
            }
    }
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { showServers ? .all : .detailOnly },
            set: { visibility in
                if visibility == .all || visibility == .doubleColumn {
                    showServers = true
                } else if visibility == .detailOnly {
                    showServers = false
                }
            })
    }
    private var navigation: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            servers
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if showChannels {
                        HSplitView {
                            channelList.frame(minWidth: 210, idealWidth: 260, maxWidth: 380)
                            detail.layoutPriority(1)
                        }
                    } else {
                        detail
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                voiceBar.padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(minWidth: showChannels ? 584 : 540)
            .navigationTitle(client.connected ? client.serverName : "轻语")
            .navigationSubtitle(
                client.connected ? "\(client.channels.count) 个频道 · \(client.members.count) 位成员" : ""
            )
        }
    }
    private var detail: some View {
        conversation
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            .navigationTitle(client.selected?.name ?? "轻语")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let channel = client.selected, client.connected,
                        channel.id != client.currentChannel
                    {
                        Button("加入频道", systemImage: "arrow.right.circle") { join(channel) }
                            .help("加入选中的频道")
                    }
                    Button(
                        client.busy ? "断开" : "连接",
                        systemImage: client.busy ? "xmark.circle" : "network"
                    ) {
                        if client.busy { client.disconnect() } else { client.showConnection = true }
                    }
                    .labelStyle(.titleAndIcon).font(.system(size: 15))
                    .help(client.busy ? "断开连接" : "连接服务器 ⌘K")
                    Button("语音设置", systemImage: "slider.horizontal.3") {
                        client.showSettings = true
                    }
                    .labelStyle(.iconOnly).font(.system(size: 18)).help("语音设置 ⌘,")
                }
            }
    }
    private var servers: some View {
        List(selection: $client.selectedBookmark) {
            ForEach(client.bookmarks) { item in
                HStack(spacing: 10) {
                    Image(systemName: "server.rack").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).lineLimit(1)
                        Text(client.activeBookmark == item.id ? client.status.label : item.address)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if client.activeBookmark == item.id, client.connected {
                        Circle().fill(Palette.speaking).frame(width: 5, height: 5)
                    }
                }
                .padding(.vertical, 4).tag(item.id)
                .onTapGesture(count: 2) {
                    if !client.busy {
                        client.selectedBookmark = item.id
                        client.showConnection = true
                    }
                }
                .contextMenu {
                    Button("连接…") {
                        client.selectedBookmark = item.id
                        client.showConnection = true
                    }.disabled(client.busy)
                    Button("编辑…") { editing = item }
                    Button("移除收藏", role: .destructive) { client.removeBookmark(item) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("服务器")
        .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("添加服务器", systemImage: "plus") { adding = true }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
    private var channelList: some View {
        List(selection: $client.selectedChannel) {
            ForEach(flatChannels, id: \.channel.id) { row in
                channelRow(row.channel, depth: row.depth).tag(row.channel.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if client.channels.isEmpty {
                VStack(spacing: 10) {
                    if client.busy { ProgressView().controlSize(.small) }
                    Text(client.busy ? "正在加载…" : "暂无频道")
                        .font(.callout).foregroundStyle(.tertiary)
                }.allowsHitTesting(false)
            }
        }

    }
    private var flatChannels: [(channel: Channel, depth: Int)] {
        var output: [(channel: Channel, depth: Int)] = []
        var seen: Set<UInt64> = []
        func walk(_ parent: UInt64, _ depth: Int) {
            for c in orderedChannels(client.channels, parent: parent) where !seen.contains(c.id) {
                seen.insert(c.id)
                output.append((c, depth))
                walk(c.id, depth + 1)
            }
        }
        walk(0, 0)
        for c in client.channels.sorted(by: { $0.id < $1.id }) where !seen.contains(c.id) {
            output.append((c, 0))
        }
        return output
    }
    private func channelRow(_ channel: Channel, depth: Int) -> some View {
        let joined = client.currentChannel == channel.id
        let count = client.members.filter { $0.channel == channel.id }.count
        return HStack(spacing: 8) {
            Image(systemName: joined ? "waveform" : "number")
                .foregroundStyle(joined ? Palette.brand : Color.secondary)
            Text(channel.name).lineLimit(1)
            Spacer(minLength: 2)
            if channel.locked {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
            }
            if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.leading, CGFloat(min(depth, 4)) * 12).padding(.vertical, 5)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            client.selectedChannel = channel.id
            join(channel)
        }
        .contextMenu {
            Button("加入频道") {
                client.selectedChannel = channel.id
                join(channel)
            }.disabled(!client.connected || joined)
        }
    }
    private func join(_ channel: Channel) {
        if channel.id == client.currentChannel { return }
        if channel.locked { lockedChannel = channel } else { client.joinSelected() }
    }
    @ViewBuilder private var conversation: some View {
        if client.connected, let channel = client.selected {
            VStack(spacing: 0) {
                Text(channel.name).font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
                if let topic = channel.topic, !topic.isEmpty {
                    Text(topic).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, 12)
                }
                if !client.visibleMembers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(client.visibleMembers) { member in
                                MemberPill(
                                    member: member, isOwn: member.id == client.ownID,
                                    speaking: client.speaking.contains(member.id)
                                        || member.id == client.ownID && client.transmitting)
                            }
                        }.padding(.horizontal, 22).padding(.bottom, 16)
                    }
                }
                Divider().padding(.horizontal, 22)
                ChatPane(draft: $chatDraft).environmentObject(client)
            }
        } else {
            VStack(spacing: 16) {
                Image(nsImage: QuietSpeakIcon.homepage).renderingMode(.template)
                    .frame(width: 56, height: 56)
                    .foregroundStyle(Palette.brand).accessibilityHidden(true)
                Text("轻语").font(.system(size: 21, weight: .semibold))
                if client.busy {
                    Text(client.statusDetail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 360)
                    ProgressView().controlSize(.small)
                } else {
                    Button("连接服务器…") { client.showConnection = true }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var voiceBar: some View {
        VStack(spacing: 0) {
            if let warning = client.audioWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(warning).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        client.audioWarning = nil
                    } label: {
                        Image(systemName: "xmark")
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 18).padding(.vertical, 8).background(
                    Color.orange.opacity(0.06))
            }
            ViewThatFits(in: .horizontal) {
                voiceControls(compact: false)
                voiceControls(compact: true)
            }
        }.modifier(VoicePanelMaterial())
    }
    private func voiceControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            if !compact {
                Image(systemName: "person.crop.circle").font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    client.members.first(where: { $0.id == client.ownID })?.name ?? client
                        .selectedServer?.nickname ?? "你"
                )
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let channel = client.joined {
                    Text(channel.name).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }.frame(width: compact ? 80 : 120, alignment: .leading)
            Divider().frame(height: 28)
            voiceButton(
                client.microphoneEnabled ? "mic.fill" : "mic.slash.fill",
                label: client.microphoneEnabled ? "关闭麦克风" : "开启麦克风",
                active: client.microphoneEnabled
            ) { client.toggleMicrophone() }
            voiceButton(
                client.deafened ? "speaker.slash.fill" : "headphones",
                label: client.deafened ? "恢复耳机" : "耳机静音", active: client.deafened
            ) { client.toggleDeafen() }
            Spacer(minLength: 16)
            Picker("说话方式", selection: $client.talkMode) {
                ForEach(TalkMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().frame(width: compact ? 100 : 110).disabled(!client.connected)
            .onChange(of: client.talkMode) {
                client.holding = false
                client.updateAudio()
            }
            if client.talkMode == .pushToTalk {
                HoldToTalk(
                    enabled: client.connected && client.microphoneEnabled && !client.deafened,
                    active: client.transmitting, onHold: client.setHolding
                )
                .frame(width: compact ? 130 : 162, height: 34)
                .help("按住按钮或 ⌥ Option 说话；键盘快捷键仅在轻语位于前台时生效")
            } else {
                Label(
                    client.microphoneRequested
                        ? (client.canSendAudio ? "麦克风已开启" : "等待话语权限") : "麦克风已关闭",
                    systemImage: client.transmitting ? "waveform" : "mic.slash"
                )
                .font(.system(size: 11)).foregroundStyle(
                    client.transmitting ? Palette.accent : Color.secondary)
            }
        }.padding(.horizontal, compact ? 12 : 16).frame(height: 54)
    }
    private func voiceButton(
        _ icon: String, label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17))
                .foregroundStyle(active ? Palette.brand : Color.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderless).disabled(!client.connected).help(label).accessibilityLabel(label)
    }
}

struct MemberPill: View {
    let member: Member
    let isOwn: Bool
    let speaking: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(speaking ? Palette.speaking : Color.secondary.opacity(0.3)).frame(
                width: 6, height: 6)
            Text(member.name + (isOwn ? "（你）" : "")).lineLimit(1)
            if member.deafened {
                Image(systemName: "speaker.slash.fill").font(.system(size: 9))
            } else if member.muted {
                Image(systemName: "mic.slash.fill").font(.system(size: 9))
            }
        }.font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                speaking ? Palette.speaking.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .accessibilityLabel("\(member.name)\(isOwn ? "，你" : "")\(speaking ? "，正在说话" : "")")
    }
}

struct ChatPane: View {
    @EnvironmentObject var client: ClientModel
    @Binding var draft: String
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if client.visibleMessages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right").font(
                                    .system(size: 26, weight: .light))
                                Text("还没有消息").font(.system(size: 13))
                            }.foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(
                                .top, 65)
                        }
                        ForEach(client.visibleMessages) { message in
                            HStack(alignment: .top, spacing: 10) {
                                if message.scope == "system" {
                                    Image(systemName: "info.circle").font(.system(size: 20))
                                        .foregroundStyle(.secondary).frame(width: 26, height: 26)
                                } else {
                                    Text(String(message.sender.prefix(1))).font(
                                        .system(size: 12, weight: .medium)
                                    )
                                    .foregroundStyle(.secondary).frame(width: 26, height: 26)
                                    .background(
                                        Palette.selection, in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(message.sender).font(
                                            .system(size: 12, weight: .semibold))
                                        if message.scope == "server" || message.scope == "private" {
                                            Text(message.scope == "server" ? "服务器消息" : "私信").font(
                                                .system(size: 9)
                                            ).foregroundStyle(.secondary)
                                        }
                                        Text(message.time, style: .time).font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(message.text).font(.system(size: 13)).foregroundStyle(
                                        message.scope == "system" ? .secondary : .primary
                                    )
                                    .textSelection(.enabled).lineSpacing(4).frame(
                                        maxWidth: .infinity, alignment: .leading)
                                }
                            }.id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(22)
                }
                .onChange(of: client.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: client.selectedChannel) {
                    draft = ""
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            HStack(spacing: 10) {
                TextField(
                    client.canChat ? "发送消息…" : "加入频道后发送消息", text: $draft, axis: .vertical
                )
                .lineLimit(1...4).textFieldStyle(.plain).font(.system(size: 13)).disabled(
                    !client.canChat
                )
                .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 28, height: 28).background(
                            Palette.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).disabled(
                    !client.canChat || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.utf8.count > 1024
                )
                .accessibilityLabel("发送消息")
            }.padding(12).background(Palette.input, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
                .padding(.horizontal, 22).padding(.bottom, 7)
            HStack {
                Text(draft.utf8.count > 1024 ? "消息超过 1024 字节，请缩短后发送" : "")
                Spacer()
                Text("Return 发送")
            }.font(.system(size: 9)).foregroundStyle(
                draft.utf8.count > 1024 ? Color.orange : Color.secondary.opacity(0.65)
            )
            .padding(.horizontal, 24).padding(.bottom, 14)
        }
    }
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 1024, client.canChat else { return }
        client.sendChat(text)
        draft = ""
    }
}

// A true mouse-down/mouse-up control avoids toggling a microphone on a normal click.
struct HoldToTalk: NSViewRepresentable {
    let enabled: Bool
    let active: Bool
    let onHold: (Bool) -> Void
    func makeNSView(context: Context) -> HoldButton {
        let b = HoldButton()
        b.bezelStyle = .rounded
        b.onHold = onHold
        return b
    }
    func updateNSView(_ view: HoldButton, context: Context) {
        view.isEnabled = enabled
        view.title = active ? "正在说话…" : "按住说话  ⌥"
        view.onHold = onHold
        view.contentTintColor = active ? .systemGreen : .secondaryLabelColor
    }
    @MainActor final class HoldButton: NSButton {
        var onHold: ((Bool) -> Void)?
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            highlight(true)
            onHold?(true)
            while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                if next.type == .leftMouseUp { break }
                let inside = bounds.contains(convert(next.locationInWindow, from: nil))
                onHold?(inside)
            }
            highlight(false)
            onHold?(false)
        }
    }
}
