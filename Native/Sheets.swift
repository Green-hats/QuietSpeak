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
            Text(isNew ? "添加服务器" : "连接服务器").font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 15) {
                field("名称", hint: "服务器名称", text: $name)
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务器地址").font(.system(size: 12, weight: .medium))
                    TextField("域名或 IP:9987", text: $address).textFieldStyle(.roundedBorder).focused(
                        $addressFocused)
                    Text("默认端口 9987").font(.system(size: 10)).foregroundStyle(
                        .secondary)
                }
                field("昵称", hint: "昵称", text: $nickname)
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
            Text("语音设置").font(.system(size: 17, weight: .semibold))
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
                        ? "开启麦克风后，按住底部按钮或 ⌥ 说话。快捷键仅在前台有效。"
                        : "开启麦克风后持续发送语音。"
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
                if let warning = client.audioWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("使用系统音频设备")
                Text("在系统设置 → 声音中切换。切换后无声音时，请重新连接。")
                    .foregroundStyle(.secondary)
            }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(
                    "轻语 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
                ).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(
                    .borderedProminent)
            }
        }.padding(28).frame(width: 450).tint(Palette.accent)
    }
}
