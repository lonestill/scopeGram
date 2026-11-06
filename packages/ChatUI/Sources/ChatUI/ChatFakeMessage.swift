import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramTheme
import TelegramContext
import TelegramUtils

public struct FakeMessagePayload {
    public enum Target {
        case serviceChat(shouldNavigate: Bool)
        case currentChat
    }
    public let target: Target
    public let text: String
    
    public init(target: Target, text: String) {
        self.target = target
        self.text = text
    }
}

public func parseChatFakeCommand(_ raw: String) -> FakeMessagePayload? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/fake") else { return nil }
    
    var rest = String(trimmed.dropFirst("/fake".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    
    var target: FakeMessagePayload.Target = .serviceChat(shouldNavigate: true)
    
    // Check flags / destination prefixes
    if rest.hasPrefix("here") {
        rest = String(rest.dropFirst("here".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .currentChat
    } else if rest.hasPrefix("local") {
        rest = String(rest.dropFirst("local".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .currentChat
    } else if rest.hasPrefix("this") {
        rest = String(rest.dropFirst("this".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .currentChat
    } else if rest.hasPrefix("noswitch") {
        rest = String(rest.dropFirst("noswitch".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .serviceChat(shouldNavigate: false)
    } else if rest.hasPrefix("stay") {
        rest = String(rest.dropFirst("stay".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .serviceChat(shouldNavigate: false)
    } else if rest.hasPrefix("silent") {
        rest = String(rest.dropFirst("silent".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .serviceChat(shouldNavigate: false)
    } else if rest.hasPrefix("tg") {
        rest = String(rest.dropFirst("tg".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .serviceChat(shouldNavigate: true)
    } else if rest.hasPrefix("777000") {
        rest = String(rest.dropFirst("777000".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        target = .serviceChat(shouldNavigate: true)
    }
    
    // Strip surrounding quotes if present: "...", '...', «...», “...”
    if (rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2) ||
       (rest.hasPrefix("'") && rest.hasSuffix("'") && rest.count >= 2) ||
       (rest.hasPrefix("«") && rest.hasSuffix("»") && rest.count >= 2) ||
       (rest.hasPrefix("“") && rest.hasSuffix("”") && rest.count >= 2) {
        rest = String(rest.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // If empty text, provide a realistic default Telegram login code message
    if rest.isEmpty {
        rest = "Login code: 73921. Do not give this code to anyone, even if they say they are from Telegram!\n\nThis code can be used to log in to your Telegram account. We never ask it for anything else.\n\nIf you didn't request this code by trying to log in on another device, simply ignore this message."
    }
    
    return FakeMessagePayload(target: target, text: rest)
}

public func parseFakeMessageTextAndEntities(_ input: String) -> (String, [MessageTextEntity]) {
    var text = input
    var entities: [MessageTextEntity] = []
    var hasMarkdown = false
    
    // Parse inline `code`
    let codePattern = "`([^`]+)`"
    if let regex = try? NSRegularExpression(pattern: codePattern, options: []) {
        while let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            hasMarkdown = true
            let innerRange = match.range(at: 1)
            let innerText = (text as NSString).substring(with: innerRange)
            let fullRange = match.range
            text = (text as NSString).replacingCharacters(in: fullRange, with: innerText)
            entities.append(MessageTextEntity(range: fullRange.location ..< fullRange.location + innerRange.length, type: .Code))
        }
    }
    
    // Parse **bold**
    let boldPattern = "\\*\\*([^*]+)\\*\\*"
    if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
        while let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            hasMarkdown = true
            let innerRange = match.range(at: 1)
            let innerText = (text as NSString).substring(with: innerRange)
            let fullRange = match.range
            text = (text as NSString).replacingCharacters(in: fullRange, with: innerText)
            entities.append(MessageTextEntity(range: fullRange.location ..< fullRange.location + innerRange.length, type: .Bold))
        }
    }
    
    // Parse ||spoiler||
    let spoilerPattern = "\\|\\|([^|]+)\\|\\|"
    if let regex = try? NSRegularExpression(pattern: spoilerPattern, options: []) {
        while let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            hasMarkdown = true
            let innerRange = match.range(at: 1)
            let innerText = (text as NSString).substring(with: innerRange)
            let fullRange = match.range
            text = (text as NSString).replacingCharacters(in: fullRange, with: innerText)
            entities.append(MessageTextEntity(range: fullRange.location ..< fullRange.location + innerRange.length, type: .Spoiler))
        }
    }
    
    // If no markdown tokens were found, apply official service notification formatting heuristics
    if !hasMarkdown {
        let nsText = text as NSString
        // 1. If multiline, bold the header line before the first newline
        if let newlineIndex = text.firstIndex(of: "\n") {
            let lineLength = text.distance(from: text.startIndex, to: newlineIndex)
            if lineLength > 0 && lineLength < 120 {
                entities.append(MessageTextEntity(range: 0 ..< lineLength, type: .Bold))
            }
        }
        
        // 2. Bold any standalone numeric confirmation code (e.g. 12345 or 123-456)
        let codePattern = "(?<!\\d)(\\d{3}[-\\s]?\\d{2,3}|\\d{5,6})(?!\\d)"
        if let regex = try? NSRegularExpression(pattern: codePattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                let range = m.range
                let lower = range.location
                let upper = range.location + range.length
                let overlaps = entities.contains(where: { $0.range.lowerBound < upper && lower < $0.range.upperBound })
                if !overlaps {
                    entities.append(MessageTextEntity(range: lower ..< upper, type: .Bold))
                }
            }
        }
    }
    
    return (text, entities)
}

public func insertFakeServiceMessage(
    context: any AccountContextProtocol,
    currentPeerId: PeerId,
    threadId: Int64?,
    navigation: NavigationViewController?,
    payload: FakeMessagePayload
) {
    let servicePeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))
    
    let targetPeerId: PeerId
    let shouldNavigate: Bool
    
    switch payload.target {
    case .currentChat:
        targetPeerId = currentPeerId
        shouldNavigate = false
    case let .serviceChat(navigate):
        targetPeerId = servicePeerId
        shouldNavigate = navigate && (currentPeerId != servicePeerId)
    }
    
    let (cleanText, entities) = parseFakeMessageTextAndEntities(payload.text)
    var attributes: [MessageAttribute] = []
    if !entities.isEmpty {
        attributes.append(TextEntitiesMessageAttribute(entities: entities))
    }
    
    let timestamp = Int32(Date().timeIntervalSince1970)
    let targetThreadId = (targetPeerId == currentPeerId) ? threadId : nil
    
    let storeMessage = StoreMessage(
        peerId: targetPeerId,
        namespace: Namespaces.Message.Local,
        customStableId: nil,
        globallyUniqueId: nil,
        groupingKey: nil,
        threadId: targetThreadId,
        timestamp: timestamp,
        flags: [.Incoming],
        tags: [],
        globalTags: [],
        localTags: [],
        forwardInfo: nil,
        authorId: servicePeerId,
        text: cleanText,
        attributes: attributes,
        media: []
    )
    
    _ = (context.account.postbox.transaction { transaction -> Void in
        if transaction.getPeer(servicePeerId) == nil {
            let serviceUser = TelegramUser(
                id: servicePeerId,
                accessHash: nil,
                firstName: "Telegram",
                lastName: nil,
                username: nil,
                phone: nil,
                photo: [],
                botInfo: nil,
                restrictionInfo: nil,
                flags: [.isVerified],
                emojiStatus: nil,
                usernames: [],
                storiesHidden: nil,
                nameColor: nil,
                backgroundEmojiId: nil,
                profileColor: nil,
                profileBackgroundEmojiId: nil,
                subscriberCount: nil,
                verificationIconFileId: nil
            )
            updatePeersCustom(transaction: transaction, peers: [serviceUser], update: { _, updated in updated })
        }
        
        _ = transaction.addMessages([storeMessage], location: .UpperHistoryBlock)
    } |> deliverOnMainQueue).start(completed: {
        if shouldNavigate {
            ChatUIHooks.shared.navigateToChat(navigation ?? context.bindings.rootNavigation(), context, .peer(servicePeerId))
        }
    })
}

