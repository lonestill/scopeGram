import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramTheme
import TelegramContext
import TelegramUtils
import ShortPeerRow

public struct FakeMessagePayload {
    public enum Target: Equatable {
        case serviceChat(shouldNavigate: Bool)
        case currentChat
    }
    public let target: Target
    public let text: String
    public let media: [Media]
    public let replyMarkup: ReplyMarkupMessageAttribute?
    
    public init(target: Target, text: String, media: [Media] = [], replyMarkup: ReplyMarkupMessageAttribute? = nil) {
        self.target = target
        self.text = text
        self.media = media
        self.replyMarkup = replyMarkup
    }
}

public func parseChatFakeCommand(_ raw: String) -> FakeMessagePayload? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/fake") else { return nil }
    
    var rest = String(trimmed.dropFirst("/fake".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    if rest.hasPrefix("_") {
        rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var target: FakeMessagePayload.Target = .serviceChat(shouldNavigate: true)
    
    // 1. Target prefixes
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
    
    if rest.hasPrefix("_") {
        rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Strip surrounding quotes if present
    if (rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2) ||
       (rest.hasPrefix("'") && rest.hasSuffix("'") && rest.count >= 2) ||
       (rest.hasPrefix("«") && rest.hasSuffix("»") && rest.count >= 2) ||
       (rest.hasPrefix("“") && rest.hasSuffix("”") && rest.count >= 2) {
        rest = String(rest.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    let parts = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    let subcommand = parts.first?.lowercased() ?? ""
    let subArgs = parts.dropFirst().joined(separator: " ")
    
    // 2. Action Subcommands (TelegramMediaAction)
    
    // /fake gift [3|6|12] or /fake premium [3|6|12]
    if subcommand == "gift" || subcommand == "premium" {
        let months: Int32
        if let parsed = Int32(subArgs), [3, 6, 12].contains(parsed) {
            months = parsed
        } else if subArgs.contains("12") || subArgs.contains("year") {
            months = 12
        } else if subArgs.contains("6") {
            months = 6
        } else {
            months = 3
        }
        let days = months * 30
        let giftAction = TelegramMediaAction(action: .giftPremium(
            currency: "USD",
            amount: 0,
            days: days,
            cryptoCurrency: nil,
            cryptoAmount: nil,
            text: "Вам подарен Telegram Premium на \(months) мес.!",
            entities: nil
        ))
        return FakeMessagePayload(target: target, text: "", media: [giftAction])
    }
    
    // /fake promo [code] or /fake giftcode [code]
    if subcommand == "promo" || subcommand == "giftcode" {
        let code = subArgs.isEmpty ? "SCOPEGRAM-\(Int.random(in: 1000...9999))" : subArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = TelegramMediaAction(action: .giftCode(
            slug: "https://t.me/giftcode/\(code)",
            fromGiveaway: false,
            isUnclaimed: false,
            boostPeerId: nil,
            months: 6,
            currency: "USD",
            amount: 0,
            cryptoCurrency: nil,
            cryptoAmount: nil,
            text: "Подарочный код на Telegram Premium",
            entities: nil
        ))
        return FakeMessagePayload(target: target, text: "", media: [action])
    }
    
    // /fake stars [count]
    if subcommand == "stars" || subcommand == "star" {
        let count = Int64(subArgs) ?? 5000
        let action = TelegramMediaAction(action: .giftStars(
            currency: "XTR",
            amount: count,
            count: count,
            cryptoCurrency: nil,
            cryptoAmount: nil,
            transactionId: "STARS-SG-\(Int.random(in: 100000...999999))"
        ))
        return FakeMessagePayload(target: target, text: "", media: [action])
    }
    
    // /fake call [missed | video | duration]
    if subcommand == "call" {
        let isMissed = subArgs.contains("miss") || subArgs.contains("пропущ")
        let isVideo = subArgs.contains("video") || subArgs.contains("видео")
        var duration: Int32? = nil
        if !isMissed {
            let digits = subArgs.filter { "0123456789".contains($0) }
            let num = Int32(digits) ?? 5
            duration = (subArgs.contains("s") || subArgs.contains("сек")) ? num : (num * 60)
        }
        let action = TelegramMediaAction(action: .phoneCall(
            callId: Int64.random(in: 100000...999999),
            discardReason: isMissed ? .missed : .hangup,
            duration: duration,
            isVideo: isVideo
        ))
        return FakeMessagePayload(target: target, text: "", media: [action])
    }
    
    // /fake screen or /fake screenshot
    if subcommand == "screen" || subcommand == "screenshot" {
        let action = TelegramMediaAction(action: .historyScreenshot)
        return FakeMessagePayload(target: target, text: "", media: [action])
    }
    
    // /fake pay [amount] or /fake payment [amount]
    if subcommand == "pay" || subcommand == "payment" {
        let amount = Int64(subArgs.filter { "0123456789".contains($0) }) ?? 100
        let action = TelegramMediaAction(action: .paymentSent(
            currency: "USD",
            totalAmount: amount,
            invoiceSlug: "SCOPEGRAM-PAY",
            isRecurringInit: false,
            isRecurringUsed: false
        ))
        return FakeMessagePayload(target: target, text: "", media: [action])
    }
    
    // /fake refund [amount]
    if subcommand == "refund" {
        let amount = Int64(subArgs.filter { "0123456789".contains($0) }) ?? 100
        let servicePeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))
        let action = TelegramMediaAction(action: .paymentRefunded(
            peerId: servicePeerId,
            currency: "USD",
            totalAmount: amount,
            payload: nil,
            transactionId: "RF-\(Int.random(in: 100000...999999))"
        ))
        return FakeMessagePayload(target: target, text: "", media: [action])
    }
    
    // 3. Official System Text Presets with Inline Buttons
    
    // /fake ban [optional reason]
    if subcommand == "ban" {
        let reason = subArgs.isEmpty ? "Нарушение условий использования платформы (Terms of Service) и подозрительная активность." : subArgs
        let text = "⛔️ **Telegram Moderation Alert**\n\nВаша учетная запись была временно ограничена модерацией Telegram.\n\n**Причина:** \(reason)\n**Срок ограничения:** 48 часов.\n\nЕсли вы считаете, что блокировка выдана по ошибке, вы можете отправить апелляцию боту SpamBot."
        let buttons = [
            ReplyMarkupButton(title: "📋 Подать апелляцию", titleWhenForwarded: nil, action: .url("https://t.me/spambot"), style: nil),
            ReplyMarkupButton(title: "Terms of Service", titleWhenForwarded: nil, action: .url("https://telegram.org/tos"), style: nil)
        ]
        let markup = ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: buttons)], flags: .inline, placeholder: nil)
        return FakeMessagePayload(target: target, text: text, replyMarkup: markup)
    }
    
    // /fake warn [optional text]
    if subcommand == "warn" || subcommand == "warning" {
        let note = subArgs.isEmpty ? "В вашей учетной записи зафиксирована подозрительная активность. Убедитесь, что у вас включена двухэтапная аутентификация (2FA), и проверьте список активных сеансов во избежание принудительного сброса аккаунта." : subArgs
        let text = "⚠️ **Предупреждение службы безопасности Telegram**\n\n\(note)"
        let buttons = [
            ReplyMarkupButton(title: "🔒 Настройки безопасности", titleWhenForwarded: nil, action: .url("tg://settings"), style: nil)
        ]
        let markup = ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: buttons)], flags: .inline, placeholder: nil)
        return FakeMessagePayload(target: target, text: text, replyMarkup: markup)
    }
    
    // /fake verify [optional name]
    if subcommand == "verify" {
        let targetName = subArgs.isEmpty ? "вашей учетной записи" : subArgs
        let text = "⭐️ **Верификация подтверждена**\n\nПоздравляем! Запрос на верификацию \(targetName) успешно одобрен Telegram.\n\nОфициальный подтверждённый знак (синяя галочка) активирован во всех результатах поиска и профиле."
        let buttons = [
            ReplyMarkupButton(title: "⭐️ О верификации", titleWhenForwarded: nil, action: .url("https://telegram.org/verify"), style: nil)
        ]
        let markup = ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: buttons)], flags: .inline, placeholder: nil)
        return FakeMessagePayload(target: target, text: text, replyMarkup: markup)
    }
    
    // /fake login [device / location]
    if subcommand == "login" {
        let details = subArgs.isEmpty ? "iPhone 16 Pro Max, iOS 18.2\n**Локация:** Амстердам, Нидерланды\n**IP:** 185.220.101.4" : subArgs
        let text = "⚠️ **Внимание: Вход с нового устройства**\n\nВ ваш аккаунт Telegram был выполнен вход:\n\n**Устройство:** \(details)\n**Время:** Только что\n\nЕсли это были не вы, немедленно завершите сеанс."
        let buttons = [
            ReplyMarkupButton(title: "🔴 Завершить сеанс", titleWhenForwarded: nil, action: .url("tg://settings"), style: nil)
        ]
        let markup = ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: buttons)], flags: .inline, placeholder: nil)
        return FakeMessagePayload(target: target, text: text, replyMarkup: markup)
    }
    
    // /fake code [optional code]
    if subcommand == "code" {
        let code = subArgs.isEmpty ? "\(Int.random(in: 10000...99999))" : subArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = "Login code: `\(code)`. Do not give this code to anyone, even if they say they are from Telegram!\n\nThis code can be used to log in to your Telegram account. We never ask it for anything else.\n\nIf you didn't request this code by trying to log in on another device, simply ignore this message."
        return FakeMessagePayload(target: target, text: text)
    }
    
    // /fake help
    if subcommand == "help" {
        let text = """
        🛠 **Команды /fake генератора:**
        
        • `/fake code [код]` — код входа Telegram
        • `/fake ban [причина]` — алерт блокировки + кнопки
        • `/fake warn [текст]` — варнинг безопасности
        • `/fake verify [имя]` — подтверждение верификации
        • `/fake login [инфо]` — алерт входа с неизвестного IP
        
        **Нативные системные плашки (Actions):**
        • `/fake gift [3|6|12]` — подарок Telegram Premium
        • `/fake promo [код]` — промокод на подписку
        • `/fake stars [кол-во]` — перевод звёзд Stars
        • `/fake call [missed|5m|video]` — звонок Telegram
        • `/fake screen` — системный алерт скриншота
        • `/fake pay [сумма]` — чек об оплате
        • `/fake refund [сумма]` — квитанция возврата
        
        **Модификаторы:**
        • `/fake here <команда/текст>` — отправить в текущий чат
        • `/fake noswitch ...` — отправить в 777000 без перехода
        """
        return FakeMessagePayload(target: target, text: text)
    }
    
    // Default: if raw text was passed without subcommand
    if rest.isEmpty {
        rest = "Login code: `73921`. Do not give this code to anyone, even if they say they are from Telegram!\n\nThis code can be used to log in to your Telegram account. We never ask it for anything else.\n\nIf you didn't request this code by trying to log in on another device, simply ignore this message."
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
    if let replyMarkup = payload.replyMarkup {
        attributes.append(replyMarkup)
    }
    
    let timestamp = Int32(Date().timeIntervalSince1970)
    let targetThreadId = (targetPeerId == currentPeerId) ? threadId : nil
    
    let authorId: PeerId
    if payload.target == .currentChat && currentPeerId.namespace == Namespaces.Peer.CloudUser {
        authorId = currentPeerId
    } else {
        authorId = servicePeerId
    }
    
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
        authorId: authorId,
        text: cleanText,
        attributes: attributes,
        media: payload.media
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

public func scopegramClientCommands(for peer: Peer, query: String) -> [ChatInputCommand] {
    let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let commands: [(text: String, desc: String)] = [
        ("fake", "Генератор системных сообщений Telegram"),
        ("fake_gift", "Подарок Telegram Premium (3, 6, 12 мес)"),
        ("fake_stars", "Перевод Telegram Stars (звёзды)"),
        ("fake_ban", "Сервисный алерт о блокировке за нарушение ToS"),
        ("fake_warn", "Предупреждение службы безопасности"),
        ("fake_verify", "Одобрение верификации профиля"),
        ("fake_login", "Алерт о входе с неизвестного устройства"),
        ("fake_promo", "Подарочный промокод на подписку"),
        ("fake_call", "Системная плашка звонка (пропущенный/видео)"),
        ("fake_screen", "Системный алерт о скриншоте диалога"),
        ("fake_pay", "Квитанция об оплате"),
        ("fake_refund", "Квитанция возврата средств"),
        ("fake_code", "Официальный код авторизации Telegram"),
        ("fake_help", "Полный список возможностей /fake"),
        ("fake_here", "Модификатор: отправить в текущий чат")
    ]
    
    let filtered = commands.filter { item in
        if normalized.isEmpty {
            return true
        }
        let cleanName = item.text.lowercased()
        let cleanDesc = item.desc.lowercased()
        let queryWithUnderscore = normalized.replacingOccurrences(of: " ", with: "_")
        let queryWithSpace = normalized.replacingOccurrences(of: "_", with: " ")
        return cleanName.hasPrefix(normalized)
            || cleanName.hasPrefix(queryWithUnderscore)
            || cleanName.contains(normalized)
            || cleanDesc.contains(normalized)
            || cleanDesc.contains(queryWithSpace)
    }
    
    return filtered.map { item in
        ChatInputCommand(peer: EnginePeer(peer), command: BotCommand(text: item.text, description: item.desc))
    }
}

