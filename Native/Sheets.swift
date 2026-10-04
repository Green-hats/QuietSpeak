import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var client: ClientModel
    @Environment(\.dismiss) private var dismiss
    let bookmark: ServerBookmark?
    let isNew: Bool
    @State private var name = ""
    @State private var address = ""
    @State private var nickname = ""
    @State private var password = ""
    @State private var remember = false
    @State private var validation: String?
    @FocusState private var addressFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack").font(.system(size: 24)).foregroundStyle(
                    Palette.accent
                )
                .frame(width: 50, height: 50).background(
                    Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "添加服务器" : "连接服务器").font(.system(size: 21, weight: .semibold))
                    Text("输入 TeamSpeak 3 服务器地址即可连接").font(.system(size: 12)).foregroundStyle(
                        .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 15) {
                field("收藏名称", hint: "例如：朋友的服务器", text: $name)
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务器地址").font(.system(size: 12, weight: .medium))
                    TextField("域名或 IP:9987", text: $address).textFieldStyle(.roundedBorder).focused(
                        $addressFocused)
                    Text("默认语音端口为 9987，支持 IPv4 和 IPv6").font(.system(size: 10)).foregroundStyle(
                        .secondary)
                }
                field("你的昵称", hint: "频道里显示的名字", text: $nickname)
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务器密码").font(.system(size: 12, weight: .medium))
                    SecureField("没有密码可留空", text: $password).textFieldStyle(.roundedBorder)
                    Toggle("在钥匙串中记住密码", isOn: $remember).font(.system(size: 11)).toggleStyle(
                        .checkbox)
                }
            }
            if let validation {
                Label(validation, systemImage: "exclamationmark.circle").font(.system(size: 11))
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("连接时默认关闭麦克风").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save(connect: false) }
                Button("连接") { save(connect: true) }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(client.busy)
            }
        }.padding(28).frame(width: 430).tint(Palette.accent)
            .onAppear {
                name = bookmark?.name ?? ""
                address = bookmark?.address ?? ""
                nickname = bookmark?.nickname ?? "Guest"
                if let bookmark, let stored = SecureStore.read("password-\(bookmark.id)") {
                    password = stored
                    remember = true
                }
                addressFocused = true
            }
    }
    private func field(_ label: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium))
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
        }
    }
    private func save(connect: Bool) {
        do {
            let item = try client.saveBookmark(
                id: isNew ? nil : bookmark?.id, name: name, address: address, nickname: nickname,
                password: password, rememberPassword: remember)
            if connect { client.connect(item, password: password) }
            dismiss()
        } catch { validation = error.localizedDescription }
    }
}
struct SettingsSheet: View {
    @EnvironmentObject var client: ClientModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("语音设置").font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                Picker("说话方式", selection: $client.talkMode) {
                    ForEach(TalkMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: client.talkMode) {
                    client.holding = false
                    client.updateAudio()
                }
                Text(
                    client.talkMode == .pushToTalk
                        ? "开启麦克风后，按住底部按钮或 ⌥ Option 说话。键盘按键说话仅在轻语位于前台时生效。"
                        : "开启麦克风后持续发送语音。离开时请点击麦克风按钮关闭。"
                )
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("播放音量")
                    Spacer()
                    Text("\(Int(client.volume*100))%").foregroundStyle(.secondary)
                }.font(.system(size: 12))
                Slider(value: $client.volume, in: 0...1.5).onChange(of: client.volume) {
                    client.updateAudio()
                }
                HStack {
                    Text(client.outputDevice).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(client.testingSpeakers ? "播放中…" : "测试扬声器") { client.testSpeakers() }
                        .disabled(client.testingSpeakers)
                }
                Text("播放一声本地提示音，连接前也可测试。").font(.system(size: 10)).foregroundStyle(.secondary)
                if let warning = client.audioWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Label("使用 macOS 默认输入和输出设备", systemImage: "headphones")
                Text("设备请在系统设置 → 声音中选择。蓝牙耳机和设备切换后如无声音，请重新连接服务器。")
                    .foregroundStyle(.secondary)
            }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(
                    "轻语 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 开源开发预览"
                ).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(
                    .borderedProminent)
            }
        }.padding(28).frame(width: 450).tint(Palette.accent)
    }
}
