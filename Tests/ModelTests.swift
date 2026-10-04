import Foundation

@main struct ModelTests {
    static func main() throws {
        func check(_ input: String, _ expected: String) throws {
            let value = try ConnectionAddress.normalize(input)
            assert(value == expected)
        }
        try check(" example.com ", "example.com")
        try check("127.0.0.1:3918", "127.0.0.1:3918")
        try check("[::1]", "[::1]:9987")
        try check("::1", "[::1]:9987")
        try check("ts3server://example.com?nickname=abc", "example.com")
        try check("ts3server://example.com:3918", "example.com:3918")
        for bad in [
            "", "some host", "host:0", "host:65536", "host:abc", "host:", ":9987",
            "https://example.com",
        ] {
            do {
                _ = try ConnectionAddress.normalize(bad)
                fatalError("Accepted invalid input: \(bad)")
            } catch {}
        }
        func channel(_ id: UInt64, _ order: UInt64, _ parent: UInt64 = 0) -> Channel {
            Channel(
                id: id, parent: parent, order: order, name: "\(id)", topic: nil, locked: false,
                codec: "OpusVoice")
        }
        let list = [channel(3, 9), channel(9, 0), channel(1, 3), channel(4, 0, 9)]
        assert(orderedChannels(list, parent: 0).map(\.id) == [9, 3, 1])
        assert(orderedChannels(list, parent: 9).map(\.id) == [4])
        assert(orderedChannels([channel(3, 9), channel(9, 3)], parent: 0).count == 2)
        let payload = Data(
            #"{"server":"测试","welcome":"欢迎","own":42,"currentChannel":9,"channels":[{"id":9,"parent":0,"order":0,"name":"大厅","topic":null,"locked":false,"codec":"OpusVoice"}],"clients":[{"id":42,"channel":9,"name":"你","muted":true,"deafened":false}]}"#
                .utf8)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: payload)
        assert(snapshot.channels[0].name == "大厅" && snapshot.clients[0].muted)
        print(
            "PASS: address validation, SRV preservation, IPv6, predecessor channel ordering, Unicode snapshot decoding"
        )
    }
}
