import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import TelegramContext
import TelegramTheme
import ColorPalette
import TelegramUtils
import InAppSettings

// MARK: - Root Scopegram Settings (Categories Hub)

public func ScopegramSettingsController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    
    var getController: (() -> InputDataController?)? = nil
    
    let pushCategory: (ViewController) -> Void = { target in
        let nav = getController?()?.navigationController ?? context.bindings.rootNavigation()
        nav.push(target)
    }
    
    let entries: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .desc(sectionId: 0, index: 0, text: .plain("CATEGORIES"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
        
        .general(sectionId: 0, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("cat_ghost"), data: .init(
            name: "Ghost & Privacy",
            color: theme.colors.text,
            type: .nextContext("Ghost Mode, Stealth Stories, Typing"),
            viewType: .firstItem,
            action: {
                pushCategory(ScopegramGhostSettingsController(context: context))
            }
        )),
        
        .general(sectionId: 0, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("cat_chat"), data: .init(
            name: "Chats & Messaging",
            color: theme.colors.text,
            type: .nextContext("Anti-Delete, Bypass Restrictions, TTL Media"),
            viewType: .innerItem,
            action: {
                pushCategory(ScopegramChatSettingsController(context: context))
            }
        )),
        
        .general(sectionId: 0, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("cat_media"), data: .init(
            name: "Calls & Media",
            color: theme.colors.text,
            type: .nextContext("Call Confirmation"),
            viewType: .innerItem,
            action: {
                pushCategory(ScopegramMediaSettingsController(context: context))
            }
        )),
        
        .general(sectionId: 0, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("cat_security"), data: .init(
            name: "Security & Identity",
            color: theme.colors.text,
            type: .nextContext("Hide Phones, Show Peer ID"),
            viewType: .innerItem,
            action: {
                pushCategory(ScopegramSecuritySettingsController(context: context))
            }
        )),
        
        .general(sectionId: 0, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("cat_experimental"), data: .init(
            name: "Clean UI & Ads",
            color: theme.colors.text,
            type: .nextContext("Channel AdBlock, Dev Tweaks"),
            viewType: .lastItem,
            action: {
                pushCategory(ScopegramExperimentalSettingsController(context: context))
            }
        )),
        
        .desc(sectionId: 0, index: 6, text: .plain("Select a category above to configure Scopegram client features."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
        
        .sectionId(1, type: .normal),
        .desc(sectionId: 1, index: 7, text: .plain("CLIENT INFO"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
        
        .general(sectionId: 1, index: 8, value: .none, error: nil, identifier: InputDataIdentifier("scopegram_engine"), data: .init(
            name: "Engine",
            color: theme.colors.text,
            type: .context("Scopegram Native v1.0"),
            viewType: .firstItem
        )),
        
        .general(sectionId: 1, index: 9, value: .none, error: nil, identifier: InputDataIdentifier("scopegram_github"), data: .init(
            name: "GitHub Repository",
            color: theme.colors.text,
            type: .nextContext("lonestill/scopeGram"),
            viewType: .innerItem,
            action: {
                if let url = URL(string: "https://github.com/lonestill/scopeGram") {
                    NSWorkspace.shared.open(url)
                }
            }
        )),
        
        .general(sectionId: 1, index: 10, value: .none, error: nil, identifier: InputDataIdentifier("scopegram_check_updates"), data: .init(
            name: "Check for Updates",
            color: theme.colors.accent,
            type: .next,
            viewType: .lastItem,
            action: {
                NSApp.sendAction(Selector(("checkForUpdates:")), to: nil, from: nil)
            }
        )),
        
        .desc(sectionId: 1, index: 11, text: .plain("Direct GitHub Releases updater with native in-app download and verified DMG mounting. Zero external trackers."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
        
        .sectionId(2, type: .normal)
    ]
    
    let signal = Signal<InputDataSignalValue, NoError>.single(InputDataSignalValue(entries: entries))
    let controller = InputDataController(dataSignal: signal, title: "Scopegram", removeAfterDisappear: false, hasDone: false, identifier: "scopegram")
    
    getController = { [weak controller] in controller }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}

// MARK: - Category 1: Ghost & Privacy

public func ScopegramGhostSettingsController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    
    struct State: Equatable {
        var ghostMode: Bool
        var dontReadMessages: Bool
        var hideTyping: Bool
        var stealthStories: Bool
    }
    
    let ud = UserDefaults.standard
    let initialState = State(
        ghostMode: ud.bool(forKey: "scopegram.ghostMode") || ud.bool(forKey: "chargedGram.ghostMode") || ud.bool(forKey: "mod.keepChatsUnread"),
        dontReadMessages: ud.bool(forKey: "scopegram.dontReadMessages"),
        hideTyping: ud.bool(forKey: "scopegram.hideTyping"),
        stealthStories: ud.bool(forKey: "scopegram.stealthStories")
    )
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let toggleGhost: () -> Void = {
        updateState { current in
            var current = current
            current.ghostMode = !current.ghostMode
            UserDefaults.standard.set(current.ghostMode, forKey: "scopegram.ghostMode")
            UserDefaults.standard.set(current.ghostMode, forKey: "chargedGram.ghostMode")
            UserDefaults.standard.set(current.ghostMode, forKey: "mod.keepChatsUnread")
            return current
        }
    }
    
    let toggleDontRead: () -> Void = {
        updateState { current in
            var current = current
            current.dontReadMessages = !current.dontReadMessages
            UserDefaults.standard.set(current.dontReadMessages, forKey: "scopegram.dontReadMessages")
            return current
        }
    }
    
    let toggleHideTyping: () -> Void = {
        updateState { current in
            var current = current
            current.hideTyping = !current.hideTyping
            UserDefaults.standard.set(current.hideTyping, forKey: "scopegram.hideTyping")
            return current
        }
    }
    
    let toggleStealthStories: () -> Void = {
        updateState { current in
            var current = current
            current.stealthStories = !current.stealthStories
            UserDefaults.standard.set(current.stealthStories, forKey: "scopegram.stealthStories")
            return current
        }
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 0, index: 0, text: .plain("MASTER GHOST SWITCH"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .general(sectionId: 0, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("ghost_toggle"), data: .init(
                name: "Ghost Mode (Master)",
                color: theme.colors.text,
                type: .switchable(state.ghostMode),
                viewType: .singleItem,
                action: toggleGhost
            )),
            .desc(sectionId: 0, index: 2, text: .plain("When enabled, acts as a master override for all stealth features below."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            
            .sectionId(1, type: .normal),
            .desc(sectionId: 1, index: 3, text: .plain("GRANULAR PRIVACY CONTROLS"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            
            .general(sectionId: 1, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("ghost_read_receipts"), data: .init(
                name: "Don't Send Read Receipts",
                color: theme.colors.text,
                type: .switchable(state.ghostMode || state.dontReadMessages),
                viewType: .firstItem,
                action: toggleDontRead
            )),
            
            .general(sectionId: 1, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("ghost_typing"), data: .init(
                name: "Don't Send Typing / Voice Status",
                color: theme.colors.text,
                type: .switchable(state.ghostMode || state.hideTyping),
                viewType: .innerItem,
                action: toggleHideTyping
            )),
            
            .general(sectionId: 1, index: 6, value: .none, error: nil, identifier: InputDataIdentifier("ghost_stories"), data: .init(
                name: "Stealth Stories Viewing",
                color: theme.colors.text,
                type: .switchable(state.ghostMode || state.stealthStories),
                viewType: .lastItem,
                action: toggleStealthStories
            )),
            
            .desc(sectionId: 1, index: 7, text: .plain("Stealth Stories lets you view any contact's stories without your name ever appearing in their viewer list."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(2, type: .normal)
        ]
        return InputDataSignalValue(entries: entries)
    }
    
    let controller = InputDataController(dataSignal: signal, title: "Ghost & Privacy", removeAfterDisappear: false, hasDone: false, identifier: "scopegram_ghost")
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}

// MARK: - Category 2: Chats & Messaging

public func ScopegramChatSettingsController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    
    struct State: Equatable {
        var showDeleted: Bool
        var allowCopyRestricted: Bool
        var saveExpiringMedia: Bool
        var reactionsOnHover: Bool
    }
    
    let ud = UserDefaults.standard
    let initialState = State(
        showDeleted: ud.bool(forKey: "scopegram.showDeletedMessages") || ud.bool(forKey: "chargedGram.showDeletedMessages"),
        allowCopyRestricted: ud.bool(forKey: "scopegram.allowCopyRestricted"),
        saveExpiringMedia: ud.bool(forKey: "scopegram.saveExpiringMedia"),
        reactionsOnHover: ud.bool(forKey: "scopegram.reactionsOnHover") || ud.bool(forKey: "chargedGram.reactionsOnHover")
    )
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let toggleDeleted: () -> Void = {
        updateState { current in
            var current = current
            current.showDeleted = !current.showDeleted
            UserDefaults.standard.set(current.showDeleted, forKey: "scopegram.showDeletedMessages")
            UserDefaults.standard.set(current.showDeleted, forKey: "chargedGram.showDeletedMessages")
            return current
        }
    }
    
    let toggleCopyRestricted: () -> Void = {
        updateState { current in
            var current = current
            current.allowCopyRestricted = !current.allowCopyRestricted
            UserDefaults.standard.set(current.allowCopyRestricted, forKey: "scopegram.allowCopyRestricted")
            return current
        }
    }
    
    let toggleExpiringMedia: () -> Void = {
        updateState { current in
            var current = current
            current.saveExpiringMedia = !current.saveExpiringMedia
            UserDefaults.standard.set(current.saveExpiringMedia, forKey: "scopegram.saveExpiringMedia")
            return current
        }
    }
    
    let toggleReactions: () -> Void = {
        updateState { current in
            var current = current
            current.reactionsOnHover = !current.reactionsOnHover
            UserDefaults.standard.set(current.reactionsOnHover, forKey: "scopegram.reactionsOnHover")
            UserDefaults.standard.set(current.reactionsOnHover, forKey: "chargedGram.reactionsOnHover")
            return current
        }
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 0, index: 0, text: .plain("MESSAGE PRESERVATION & BYPASSES"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            
            .general(sectionId: 0, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("chat_deleted"), data: .init(
                name: "Anti-Delete Messages",
                color: theme.colors.text,
                type: .switchable(state.showDeleted),
                viewType: .firstItem,
                action: toggleDeleted
            )),
            
            .general(sectionId: 0, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("chat_copy_restricted"), data: .init(
                name: "Bypass Channel Copy Protection",
                color: theme.colors.text,
                type: .switchable(state.allowCopyRestricted),
                viewType: .innerItem,
                action: toggleCopyRestricted
            )),
            
            .general(sectionId: 0, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("chat_expiring_media"), data: .init(
                name: "Unlimited Disappearing Media",
                color: theme.colors.text,
                type: .switchable(state.saveExpiringMedia),
                viewType: .innerItem,
                action: toggleExpiringMedia
            )),
            
            .general(sectionId: 0, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("chat_reactions"), data: .init(
                name: "Quick Reactions on Hover",
                color: theme.colors.text,
                type: .switchable(state.reactionsOnHover),
                viewType: .lastItem,
                action: toggleReactions
            )),
            
            .desc(sectionId: 0, index: 5, text: .plain("Anti-Delete retains messages when remote peers delete them. Bypass Protection allows copying, forwarding, and saving media from restricted channels. Unlimited Media disables self-destruct timers on view-once photos & voices."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        return InputDataSignalValue(entries: entries)
    }
    
    let controller = InputDataController(dataSignal: signal, title: "Chats & Messaging", removeAfterDisappear: false, hasDone: false, identifier: "scopegram_chat")
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}

// MARK: - Category 3: Calls & Media

public func ScopegramMediaSettingsController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    
    struct State: Equatable {
        var confirmCalls: Bool
    }
    
    let ud = UserDefaults.standard
    let initialState = State(confirmCalls: ud.bool(forKey: "scopegram.confirmCalls") || ud.bool(forKey: "chargedGram.confirmCalls"))
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let toggleCalls: () -> Void = {
        updateState { current in
            var current = current
            current.confirmCalls = !current.confirmCalls
            UserDefaults.standard.set(current.confirmCalls, forKey: "scopegram.confirmCalls")
            UserDefaults.standard.set(current.confirmCalls, forKey: "chargedGram.confirmCalls")
            return current
        }
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 0, index: 0, text: .plain("CALL SAFETY"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .general(sectionId: 0, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("media_calls"), data: .init(
                name: "Confirm Calls",
                color: theme.colors.text,
                type: .switchable(state.confirmCalls),
                viewType: .singleItem,
                action: toggleCalls
            )),
            .desc(sectionId: 0, index: 2, text: .plain("Prompts a confirmation dialog before initiating audio or video calls to prevent accidental dialing."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        return InputDataSignalValue(entries: entries)
    }
    
    let controller = InputDataController(dataSignal: signal, title: "Calls & Media", removeAfterDisappear: false, hasDone: false, identifier: "scopegram_media")
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}

// MARK: - Category 4: Security & Identity

public func ScopegramSecuritySettingsController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    
    struct State: Equatable {
        var hidePhoneNumbers: Bool
        var showPeerId: Bool
    }
    
    let ud = UserDefaults.standard
    let initialState = State(
        hidePhoneNumbers: ud.bool(forKey: "scopegram.hidePhoneNumbers") || ud.bool(forKey: "chargedGram.hidePhoneNumbers"),
        showPeerId: FastSettings.canViewPeerId
    )
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let togglePhones: () -> Void = {
        updateState { current in
            var current = current
            current.hidePhoneNumbers = !current.hidePhoneNumbers
            UserDefaults.standard.set(current.hidePhoneNumbers, forKey: "scopegram.hidePhoneNumbers")
            UserDefaults.standard.set(current.hidePhoneNumbers, forKey: "chargedGram.hidePhoneNumbers")
            return current
        }
    }
    
    let togglePeerId: () -> Void = {
        FastSettings.canViewPeerId = !FastSettings.canViewPeerId
        updateState { current in
            var current = current
            current.showPeerId = FastSettings.canViewPeerId
            return current
        }
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 0, index: 0, text: .plain("IDENTITY & PROFILE PRIVACY"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            
            .general(sectionId: 0, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("sec_phones"), data: .init(
                name: "Hide Phone Numbers",
                color: theme.colors.text,
                type: .switchable(state.hidePhoneNumbers),
                viewType: .firstItem,
                action: togglePhones
            )),
            
            .general(sectionId: 0, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("sec_peer_id"), data: .init(
                name: "Show Peer ID on Profile",
                color: theme.colors.text,
                type: .switchable(state.showPeerId),
                viewType: .lastItem,
                action: togglePeerId
            )),
            
            .desc(sectionId: 0, index: 3, text: .plain("Masks phone numbers in user profiles. Peer ID shows Telegram numeric IDs for users, groups, and channels with click-to-copy."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        return InputDataSignalValue(entries: entries)
    }
    
    let controller = InputDataController(dataSignal: signal, title: "Security & Identity", removeAfterDisappear: false, hasDone: false, identifier: "scopegram_security")
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}

// MARK: - Category 5: Clean UI & Ads

public func ScopegramExperimentalSettingsController(context: any AccountContextProtocol) -> InputDataController {
    let actionsDisposable = DisposableSet()
    
    struct State: Equatable {
        var hideAds: Bool
        var debugLogs: Bool
    }
    
    let ud = UserDefaults.standard
    let initialState = State(
        hideAds: ud.bool(forKey: "scopegram.hideAds"),
        debugLogs: ud.bool(forKey: "scopegram.debugLogs")
    )
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let toggleAds: () -> Void = {
        updateState { current in
            var current = current
            current.hideAds = !current.hideAds
            UserDefaults.standard.set(current.hideAds, forKey: "scopegram.hideAds")
            return current
        }
    }
    
    let toggleLogs: () -> Void = {
        updateState { current in
            var current = current
            current.debugLogs = !current.debugLogs
            UserDefaults.standard.set(current.debugLogs, forKey: "scopegram.debugLogs")
            return current
        }
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 0, index: 0, text: .plain("ADBLOCK & INTERFACE"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            
            .general(sectionId: 0, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("exp_ads"), data: .init(
                name: "Hide Sponsored Messages (AdBlock)",
                color: theme.colors.text,
                type: .switchable(state.hideAds),
                viewType: .firstItem,
                action: toggleAds
            )),
            
            .general(sectionId: 0, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("exp_logs"), data: .init(
                name: "Debug Logging",
                color: theme.colors.text,
                type: .switchable(state.debugLogs),
                viewType: .lastItem,
                action: toggleLogs
            )),
            
            .desc(sectionId: 0, index: 3, text: .plain("Blocks sponsored ad posts displayed at the bottom of public channels. Debug Logging enables verbose logs for client diagnostics."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        return InputDataSignalValue(entries: entries)
    }
    
    let controller = InputDataController(dataSignal: signal, title: "Clean UI & Ads", removeAfterDisappear: false, hasDone: false, identifier: "scopegram_experimental")
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}
