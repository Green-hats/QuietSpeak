import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var client: ClientModel
    @State private var editing: ServerBookmark?
    @State private var adding = false
    @State private var lockedChannel: Channel?
    @State private var channelPassword = ""
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                servers.frame(width: 194)
                Divider()
                channelList.frame(width: 272)
                Divider()
                conversation.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            voiceBar
        }
        .background(Palette.canvas)
        .sheet(isPresented: $client.showConnection) {
            ConnectionSheet(bookmark: client.selectedServer, isNew: false).environmentObject(client)
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
    private var header: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 65)
            Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(
                Palette.accent)
            Text("轻语").font(.system(size: 17, weight: .semibold))
            Text("TS3").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(
                .secondary
            )
            .padding(.horizontal, 6).padding(.vertical, 3).background(.quaternary, in: Capsule())
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(client.connected ? Palette.accent : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(client.status.label).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if client.busy {
                Button {
                    client.disconnect()
                } label: {
                    Label("断开", systemImage: "xmark.circle")
                }.buttonStyle(.borderless)
            } else {
                Button {
                    client.showConnection = true
                } label: {
                    Label("连接服务器", systemImage: "bolt.fill")
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            Button {
                client.showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain).help("语音设置 ⌘,")
        }
        .padding(.horizontal, 16).frame(height: 56)
    }
    private var servers: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("服务器").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).help("添加服务器")
            }.padding(.horizontal, 18).padding(.top, 22)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(client.bookmarks) { item in
                        Button {
                            client.selectedBookmark = item.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "server.rack").font(.system(size: 18))
                                    .foregroundStyle(
                                        client.selectedBookmark == item.id
                                            ? Palette.accent : Color.secondary
                                    )
                                    .frame(width: 32, height: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(
                                        client.activeBookmark == item.id
                                            ? client.status.label : "点击连接"
                                    ).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if client.activeBookmark == item.id {
                                    Circle().fill(Palette.accent).frame(width: 5, height: 5)
                                }
                            }
                            .padding(9).background(
                                client.selectedBookmark == item.id
                                    ? Palette.accent.opacity(0.10) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                if !client.busy {
                                    client.selectedBookmark = item.id
                                    client.showConnection = true
                                }
                            }
                        )
                        .contextMenu {
                            Button("连接…") {
                                client.selectedBookmark = item.id
                                client.showConnection = true
                            }.disabled(client.busy)
                            Button("编辑…") { editing = item }
                            Button("移除收藏", role: .destructive) { client.removeBookmark(item) }
                        }
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Text("少一点干扰，\n多一点交流。")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .lineSpacing(5)
                Text("原生 macOS · TeamSpeak 3")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }.padding(18)
        }.background(Palette.sidebar.opacity(0.65))
    }
    private var channelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(client.connected ? client.serverName : (client.selectedServer?.name ?? "频道"))
                    .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(
                    client.connected
                        ? "\(client.channels.count) 个频道 · \(client.members.count) 位可见成员"
                        : "连接后查看频道和成员"
                )
                .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("搜索频道", text: $client.search).textFieldStyle(.plain)
                }
                .font(.system(size: 12)).padding(8).background(
                    .quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7)
                )
                .padding(.top, 8)
            }.padding(18)
            Divider().padding(.horizontal, 18)
            if client.channels.isEmpty {
                VStack(spacing: 12) {
                    Image(
                        systemName: client.busy
                            ? "antenna.radiowaves.left.and.right" : "rectangle.3.group"
                    ).font(.system(size: 29, weight: .light)).foregroundStyle(.tertiary)
                    Text(client.busy ? "正在获取频道…" : "频道会出现在这里").font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if client.busy { ProgressView().controlSize(.small) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(flatChannels, id: \.channel.id) { row in
                            channelRow(row.channel, depth: row.depth)
                        }
                        if flatChannels.isEmpty {
                            Text("没有匹配的频道").foregroundStyle(.secondary).padding()
                        }
                    }.padding(.horizontal, 9).padding(.vertical, 12)
                }
            }
        }.background(Palette.sidebar.opacity(0.28))
    }
    private var flatChannels: [(channel: Channel, depth: Int)] {
        if !client.search.isEmpty {
            return client.channels.filter {
                $0.name.localizedCaseInsensitiveContains(client.search)
            }.sorted { $0.name < $1.name }.map { ($0, 0) }
        }
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
        let selected = client.selectedChannel == channel.id
        let joined = client.currentChannel == channel.id
        let count = client.members.filter { $0.channel == channel.id }.count
        return Button {
            client.selectedChannel = channel.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: joined ? "waveform" : "number").font(
                    .system(size: 13, weight: .medium)
                )
                .foregroundStyle(joined ? Palette.accent : Color.secondary)
                Text(channel.name).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if channel.locked {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                if count > 0 {
                    Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 10 + CGFloat(min(depth, 4)) * 12).padding(.trailing, 10).frame(
                height: 36
            )
            .background(
                selected ? Palette.accent.opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    client.selectedChannel = channel.id
                    join(channel)
                }
            )
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
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "number").font(.system(size: 20, weight: .light))
                        .foregroundStyle(Palette.accent)
                        .padding(10).background(
                            Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(channel.name).font(.system(size: 19, weight: .semibold)).lineLimit(2)
                        Text(
                            channel.topic?.isEmpty == false
                                ? channel.topic!
                                : (channel.id == client.currentChannel
                                    ? "正在这个频道交流" : "预览频道 · 加入后即可交流")
                        )
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if channel.id != client.currentChannel {
                        Button("加入频道") { join(channel) }.buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Label("已加入", systemImage: "checkmark.circle.fill").font(.system(size: 11))
                            .foregroundStyle(Palette.accent)
                    }
                }.padding(22)
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
                ChatPane().environmentObject(client)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "waveform").font(.system(size: 42, weight: .light))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 100, height: 100).background(
                        Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 29))
                Text(client.busy ? "正在建立连接" : "交流，从连接开始").font(.system(size: 24, weight: .semibold))
                Text(client.statusDetail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                if client.busy {
                    ProgressView().controlSize(.small).padding(.top, 8)
                } else {
                    Button {
                        client.showConnection = true
                    } label: {
                        Label("连接服务器", systemImage: "bolt.fill").padding(.horizontal, 10).padding(
                            .vertical, 4)
                    }.buttonStyle(.borderedProminent).padding(.top, 8)
                }
                Text("频道 · 语音 · 文字聊天").font(.system(size: 11)).foregroundStyle(.tertiary).padding(
                    .top, 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 28))
                    .foregroundStyle(Palette.accent.opacity(0.75))
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        client.members.first(where: { $0.id == client.ownID })?.name ?? client
                            .selectedServer?.nickname ?? "你"
                    )
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(client.joined?.name ?? "尚未加入语音频道").font(.system(size: 10)).foregroundStyle(
                        .secondary
                    ).lineLimit(1)
                }.frame(width: 145, alignment: .leading)
                Divider().frame(height: 28)
                voiceButton(
                    client.microphoneEnabled ? "mic.fill" : "mic.slash.fill",
                    label: client.microphoneEnabled ? "关闭麦克风" : "开启麦克风",
                    active: client.microphoneEnabled
                ) { client.toggleMicrophone() }
                voiceButton(
                    client.deafened ? "speaker.slash.fill" : "headphones",
                    label: client.deafened ? "恢复耳机" : "耳机静音", active: !client.deafened
                ) { client.toggleDeafen() }
                Picker("说话方式", selection: $client.talkMode) {
                    ForEach(TalkMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 110).disabled(!client.connected)
                .onChange(of: client.talkMode) {
                    client.holding = false
                    client.updateAudio()
                }
                Spacer(minLength: 8)
                if client.talkMode == .pushToTalk {
                    HoldToTalk(
                        enabled: client.connected && client.microphoneEnabled && !client.deafened,
                        active: client.transmitting, onHold: client.setHolding
                    )
                    .frame(width: 162, height: 34)
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
            }.padding(.horizontal, 20).frame(height: 76)
        }.background(Palette.sidebar.opacity(0.45))
    }
    private func voiceButton(
        _ icon: String, label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(
                active ? Palette.accent : Color.secondary
            )
            .frame(width: 36, height: 36).background(
                active ? Palette.accent.opacity(0.08) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).disabled(!client.connected).help(label).accessibilityLabel(label)
    }
}

struct MemberPill: View {
    let member: Member
    let isOwn: Bool
    let speaking: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(speaking ? Palette.accent : Color.secondary.opacity(0.25)).frame(
                width: 6, height: 6)
            Text(member.name + (isOwn ? "（你）" : "")).lineLimit(1)
            if member.deafened {
                Image(systemName: "speaker.slash.fill").font(.system(size: 9))
            } else if member.muted {
                Image(systemName: "mic.slash.fill").font(.system(size: 9))
            }
        }.font(.system(size: 11)).foregroundStyle(speaking ? Palette.accent : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                speaking ? Palette.accent.opacity(0.10) : Color.secondary.opacity(0.06),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    speaking ? Palette.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .accessibilityLabel("\(member.name)\(isOwn ? "，你" : "")\(speaking ? "，正在说话" : "")")
    }
}

struct ChatPane: View {
    @EnvironmentObject var client: ClientModel
    @State private var draft = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if client.visibleMessages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right").font(
                                    .system(size: 26, weight: .light))
                                Text("还没有消息").font(.system(size: 13))
                                Text("简单聊两句，或者直接开始说话").font(.system(size: 11))
                            }.foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(
                                .top, 65)
                        }
                        ForEach(client.visibleMessages) { message in
                            HStack(alignment: .top, spacing: 10) {
                                Image(
                                    systemName: message.scope == "system"
                                        ? "info.circle" : "person.crop.circle.fill"
                                )
                                .font(.system(size: 25)).foregroundStyle(
                                    message.outgoing ? Palette.accent : Color.secondary.opacity(0.5)
                                )
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
                    client.canChat ? "发送消息到当前频道…" : "加入频道后即可发送消息", text: $draft, axis: .vertical
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
            }.padding(12).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12)))
                .padding(.horizontal, 22).padding(.bottom, 7)
            HStack {
                Text(draft.utf8.count > 1024 ? "消息超过 1024 字节，请缩短后发送" : "文字消息只发送到已加入的频道")
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
