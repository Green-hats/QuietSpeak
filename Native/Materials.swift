import SwiftUI

struct VoicePanelMaterial: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            } else {
                content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        #else
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        #endif
    }
}

private struct ChannelSidebarVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var channelSidebarVisibility: Binding<Bool>? {
        get { self[ChannelSidebarVisibilityKey.self] }
        set { self[ChannelSidebarVisibilityKey.self] = newValue }
    }
}
