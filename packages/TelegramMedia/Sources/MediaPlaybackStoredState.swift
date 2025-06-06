import TelegramCore
import Postbox
import SwiftSignalKit

public final class MediaPlaybackStoredState: Codable {
    public let timestamp: Double
    
    public init(timestamp: Double) {
        self.timestamp = timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.timestamp = try container.decode(Double.self, forKey: "timestamp")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.timestamp, forKey: "timestamp")
    }
}

public func mediaPlaybackStoredState(engine: TelegramEngine, messageId: EngineMessage.Id) -> Signal<MediaPlaybackStoredState?, NoError> {
    return engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> map { message -> MediaPlaybackStoredState? in
        guard let message else {
            return nil
        }
        for attribute in message.attributes {
            if let attribute = attribute as? DerivedDataMessageAttribute {
                return attribute.data["mps"]?.get(MediaPlaybackStoredState.self)
            }
        }
        return nil
    }
}

public func updateMediaPlaybackStoredStateInteractively(engine: TelegramEngine, messageId: EngineMessage.Id, state: MediaPlaybackStoredState?) -> Signal<Never, NoError> {
    return engine.messages.updateLocallyDerivedData(messageId: messageId, update: { data in
        var data = data
        if let state, let entry = CodableEntry(state) {
            data["mps"] = entry
        } else {
            data.removeValue(forKey: "mps")
        }
        return data
    })
}
