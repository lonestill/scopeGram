#if !APP_STORE

import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import Sparkle
import CrashRecoveryUI



final class TelegramUpdater : NSObject, SUUpdaterPrivate {
    var delegate: SUUpdaterDelegate!
    
    var userAgentString: String!
    
    var domain: String! = nil
    var host: String! = nil
    
    var httpHeaders: [AnyHashable : Any]!
    
    var decryptionPassword: String!
    
    var sparkleBundle: Bundle!
    
    override init() {
        self.sparkleBundle = Bundle(for: SUUpdateDriver.self)
    }
}

extension SUAppcastItem {
    var updateText: String {
        var updateText = (itemDescription.html2Attributed?.string ?? itemDescription).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        while let range = updateText.range(of: "   ") {
            updateText = updateText.replacingOccurrences(of: "   ", with: "  ", options: [], range: range)
        }
        updateText = updateText.replacingOccurrences(of: "•", with: "\n•", options: [], range: nil)
        
        if updateText.first == "\n" {
            updateText.removeFirst()
        }
        updateText = updateText.replacingOccurrences(of: "\t", with: "  ", options: [], range: nil)
        return updateText
    }
    
    var versionTitle: String {
        return "Version \(self.displayVersionString!) (\(self.versionString!))"
    }
}



enum AppUpdateLoadingState : Equatable {
    case nonInited
    case initializing
    case loading(item:SUAppcastItem, current: Int, total: Int)
    case hasUpdate(SUAppcastItem)
    case readyToInstall(SUAppcastItem)
    case uptodate
    case unarchiving(SUAppcastItem)
    case installing
    case failed(NSError)
}

private let initialState = AppUpdateState(items: [], loadingState: .nonInited)
private let statePromise: ValuePromise<AppUpdateState> = ValuePromise(initialState, ignoreRepeated: true)
private let stateValue = Atomic(value: initialState)

var appUpdateStateSignal: Signal<AppUpdateState, NoError> {
    return statePromise.get()
}

private let updateState:((AppUpdateState)->AppUpdateState) -> Void = { f in
    statePromise.set(stateValue.modify(f))
}
private let updater = TelegramUpdater()
private let currentDriver = Atomic<ObjectIdentifier?>(value: nil)
private var driver:SUBasicUpdateDriver? {
    didSet {
        let identifier = driver.map { ObjectIdentifier($0) }
        _ = currentDriver.swap(identifier)
    }
}
private let host = SUHost(bundle: Bundle.main)

func updateApplication(sharedContext: SharedAccountContext) {

    
    let state = stateValue.with {$0.loadingState}
    switch state {
    case let .readyToInstall(item):
        cancelStagedUpdate()
        var text: String = "Telegram was updated to \(item.versionTitle.lowercased())"
        text += "\n\n"
        
        text += item.updateText
        
        
        _ = (sharedContext.activeAccountsWithInfo |> take(1) |> mapToSignal { _, accounts -> Signal<Never, NoError> in
            return combineLatest(accounts.map { addAppUpdateText($0.account.postbox, applyText: text) }) |> ignoreValues
        } |> deliverOnMainQueue).start(completed: { 
              driver?.install(withToolAndRelaunch: true)
            
        })
        
    case .installing:
        break
    default:
        resetUpdater()
    }
}


struct AppUpdateState : Equatable {
    let items: [SUAppcastItem]
    let loadingState: AppUpdateLoadingState
    
    fileprivate init(items: [SUAppcastItem], loadingState: AppUpdateLoadingState) {
        self.items = items
        self.loadingState = loadingState
        
    }
    func withUpdatedItems(_ items: [SUAppcastItem]) -> AppUpdateState {
        return AppUpdateState(items: items, loadingState: self.loadingState)
    }
    func withUpdatedLoadingState(_ loadingState: AppUpdateLoadingState) -> AppUpdateState {
        return AppUpdateState(items: self.items, loadingState: loadingState)
    }
}

extension String{
    var html2Attributed: NSAttributedString? {
        do {
            guard let data = data(using: String.Encoding.utf8) else {
                return nil
            }
            return try NSAttributedString(data: data,
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        } catch {
            print("error: ", error)
            return nil
        }
    }
}

private let _id_update_app: InputDataIdentifier = InputDataIdentifier("_id_update_app")
private let _id_initializing: InputDataIdentifier = InputDataIdentifier("_id_initializing")
private let _id_downloading: InputDataIdentifier = InputDataIdentifier("_id_downloading")
private let _id_download_update: InputDataIdentifier = InputDataIdentifier("_id_download_update")
private let _id_install_update: InputDataIdentifier = InputDataIdentifier("_id_install_update")
private let _id_check_for_updates: InputDataIdentifier = InputDataIdentifier("_id_check_for_updates")
private let _id_unarchiving: InputDataIdentifier = InputDataIdentifier("_id_unarchiving")

private func appUpdateEntries(state: AppUpdateState) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    var currentItem: SUAppcastItem?
    
    switch state.loadingState {
    case let .failed(error):
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_check_for_updates, data: InputDataGeneralData(name: strings().appUpdateCheckForUpdates, color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(error.localizedDescription), data: InputDataGeneralTextData(color: theme.colors.redUI, detectBold: false, viewType: .textBottomItem)))
        index += 1
        
    case let .hasUpdate(item):
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_download_update, data: InputDataGeneralData(name: strings().appUpdateDownloadUpdate, color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case .initializing, .nonInited:
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_initializing, data: InputDataGeneralData(name: strings().appUpdateRetrievingInfo, color: theme.colors.grayText, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
    case let .loading(item, current, total):
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_downloading, data: InputDataGeneralData(name: "\(strings().appUpdateDownloading)  \(String.prettySized(with: current, forceDecimal: true) + " / " + String.prettySized(with: total))", color: theme.colors.grayText, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case .uptodate:
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_check_for_updates, data: InputDataGeneralData(name: strings().appUpdateCheckForUpdates, color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().appUpdateUptodate), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
    case let .unarchiving(item):
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_unarchiving, data: InputDataGeneralData(name: strings().appUpdateUnarchiving, color: theme.colors.grayText, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case let .readyToInstall(item):
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_install_update, data: InputDataGeneralData(name: strings().updateUpdateTelegram, color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case .installing:
        break
    }
    
    
    if let item = currentItem {
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().appUpdateNewestAvailable), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    
        let text = "**" + item.versionTitle + "**" + "\n" + item.updateText
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier(item.fileURL.path), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, textColor: theme.colors.listGrayText, fontSize: 13, isTextSelectable: true, viewType: .textTopItem)
        }))
        index += 1
    }
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    
    return entries
}



func AppUpdateViewController() -> InputDataController {
    
    let signal: Signal<InputDataSignalValue, NoError> = statePromise.get() |> deliverOnResourceQueue |> map { value in
        return appUpdateEntries(state: value)
    } |> map { InputDataSignalValue(entries: $0) }
    

    return InputDataController(dataSignal: signal, title: strings().appUpdateTitle, validateData: { data in
        
        if let _ = data[_id_download_update] {
            ScopegramUpdateManager.shared.startDownload()
        }
        if let _ = data[_id_check_for_updates] {
            ScopegramUpdateManager.shared.checkNow(manual: true)
        }
        if let _ = data[_id_install_update] {
            ScopegramUpdateManager.shared.installUpdate()
        }
        
        return .none
    }, afterDisappear: {

    }, hasDone: false, identifier: "app_update")
    
    
}

#if STABLE
private let updates_channel_xml = "macos_stable_updates_xml"
#else
private let updates_channel_xml = "macos_beta_updates_xml"
#endif


private final class InternalUpdaterDownloader : SPUDownloaderSession {
    private let context: AccountContext
    private let updateItem: SUAppcastItem
    private let disposable = MetaDisposable()
    init(context: AccountContext, updateItem: SUAppcastItem, delegate: SPUDownloaderDelegate) {
        self.context = context
        self.updateItem = updateItem
        super.init(delegate: delegate)
    }
    
    deinit {
        disposable.dispose()
    }
    
    override func suggestedFilename() -> String! {
        return "Telegram.app.zip"
    }
    
    
    
    override func moveItem(atPath fromPath: String!, toPath: String!, error: Error) -> Bool {
        try? FileManager.default.removeItem(atPath: toPath)
        do {
            try FileManager.default.copyItem(atPath: fromPath, toPath: toPath)
            return true
        } catch { 
            return false
        }
    }
    
    
    override func startDownload(with request: SPUURLRequest!) {
        if let internalUrl = self.updateItem.internalUrl {
            
            let url = inApp(for: internalUrl as NSString, context: self.context, peerId: nil, openInfo: { _, _, _, _ in }, hashtag: nil, command: nil, applyProxy: nil, confirm: false)
            switch url {
            case let .followResolvedName(_, username, messageId, _, context, _, _):
                if let messageId = messageId {
                    let signal = downloadAppUpdate(account: context.account, source: username, messageId: messageId) |> deliverOnMainQueue
                    disposable.set(signal.start(next: { [weak self] result in
                        guard let `self` = self else {
                            return
                        }
                        switch result {
                        case let .started(total):
                            self.delegate.downloaderDidReceiveExpectedContentLength(Int64(total))
                        case let .progress(current, _):
                            self.delegate.downloaderDidReceiveData(ofLength: UInt64(current))
                        case let .finished(path):
                            self.urlSession(URLSession(), downloadTask: URLSessionDownloadTask(), didFinishDownloadingTo: URL(fileURLWithPath: path))
                        }
                    }, error: { [weak self] error in
                            self?.delegate.downloaderDidFailWithError(NSError(domain: strings().appUpdateErrorFailedDownload, code: 0, userInfo: nil))
                    }))
                } else {
                    self.delegate.downloaderDidFailWithError(NSError(domain: strings().appUpdateErrorWrongInternal, code: 0, userInfo: nil))
                }
                
            default:
                self.delegate.downloaderDidFailWithError(NSError(domain: strings().appUpdateErrorWrongInternal, code: 0, userInfo: nil))
            }
            
            
        } else {
            self.delegate.downloaderDidFailWithError(NSError(domain: strings().appUpdateErrorNoInternal, code: 0, userInfo: nil))
        }
        
    }
    
    
    override func cancel() {
        disposable.set(nil)
    }
    
}

private final class InternalUpdateDriver : ExternalUpdateDriver {
    
    
    private let disposabe = MetaDisposable()
    private let context: AccountContext
    
    init(updater:TelegramUpdater, context: AccountContext) {
        self.context = context
        super.init(updater: updater)
    }
    
    deinit {
        disposabe.dispose()
    }
    
    override func checkForUpdates(at URL: URL!, host aHost: SUHost!, domain: String!) {
        self.host = aHost

        updateSharedState {
            return $0.withUpdatedLoadingState(.initializing)
        }
        
        let signal = requestUpdatesXml(account: self.context.account, source: updates_channel_xml) |> deliverOnMainQueue |> timeout(20.0, queue: .mainQueue(), alternate: .fail(.xmlLoad))
        
        disposabe.set(signal.start(next: { [weak self] data in
            let appcast = SUAppcast()
            appcast.parseAppcastItems(fromXMLData: data, error: nil)
            self?.appcastDidFinishLoading(appcast)
        }, error: { [weak self] error in
            self?.abortUpdateWithError(NSError(domain: strings().appUpdateErrorFailedUpdating, code: 0, userInfo: nil))
        }))
    }
    
    override func downloadUpdate() {
        let downloader = InternalUpdaterDownloader(context: self.context, updateItem: self.updateItem, delegate: self)
        self.download = downloader
        let fileName = "Telegram \(self.updateItem.versionString ?? "")"

        downloader.startPersistentDownload(with: SPUURLRequest(), bundleIdentifier: host.bundle.bundleIdentifier!, desiredFilename: fileName)
    }
    
    override func downloaderDidReceiveData(ofLength length: UInt64) {
        updateSharedState { state in
            switch state.loadingState {
            case let .loading(item, _, total):
                return state.withUpdatedLoadingState(.loading(item: item, current: Int(length), total: total))
            default:
                return state
            }
        }
    }
    
    override func downloaderDidReceiveExpectedContentLength(_ expectedContentLength: Int64) {
        updateSharedState { state in
            return state.withUpdatedLoadingState(.loading(item: self.updateItem, current: 0, total: Int(expectedContentLength)))
        }
    }
    
}

private class ExternalUpdateDriver : SUBasicUpdateDriver {
    
    fileprivate var stagedOver: SUAppcastItem?

    fileprivate var isStaging: Bool {
        return stagedOver != nil
    }

    fileprivate var isCurrentDriver: Bool {
        return currentDriver.with { $0 } == ObjectIdentifier(self)
    }
    
    override func isItemNewer(_ ui: SUAppcastItem!) -> Bool {
        guard super.isItemNewer(ui) else {
            return false
        }
        if let stagedOver = stagedOver {
            return SUStandardVersionComparator().compareVersion(stagedOver.versionString, toVersion: ui.versionString) == .orderedAscending
        }
        return true
    }

    override func didFindValidUpdate() {
        if isStaging && stagedDriver !== self {
            return
        }
        super.didFindValidUpdate()
    }

    private func downloadKeepingReadyUpdate() {
        let download = SPUDownloaderSession(delegate: self)
        self.download = download
        let fileName = "\(host.name ?? "") \(updateItem.versionString ?? "")"
        download?.startPersistentDownload(with: SPUURLRequest(request: URLRequest(url: updateItem.fileURL)), bundleIdentifier: host.bundle.bundleIdentifier!, desiredFilename: fileName)
    }

    fileprivate func updateSharedState(_ f: (AppUpdateState) -> AppUpdateState) {
        if isCurrentDriver {
            updateState(f)
        }
    }
    
    override func extractUpdate() {
        super.extractUpdate()
        updateSharedState {
            return $0.withUpdatedLoadingState(.unarchiving(self.updateItem))
        }
    }
    

    
    override func install(withToolAndRelaunch relaunch: Bool, displayingUserInterface showUI: Bool) {
        if isCurrentDriver {
            cancelStagedUpdate()
        }
        updateSharedState {
            return $0.withUpdatedLoadingState(.installing)
        }
        resourcesQueue.async {
            super.install(withToolAndRelaunch: relaunch, displayingUserInterface: showUI)
        }
    }
    
    override func appcastDidFinishLoading(_ ac: SUAppcast!) {
        updateSharedState {
            return $0.withUpdatedItems(ac.items?.compactMap({$0 as? SUAppcastItem}) ?? [])
        }
        super.appcastDidFinishLoading(ac)
    }
    
    override func didNotFindUpdate() {
        if isStaging {
            dropStagedUpdate(self, failed: false)
            return
        }
        updateSharedState {
            return $0.withUpdatedLoadingState(.uptodate)
        }
    }
    
    override func checkForUpdates(at url: URL!, host aHost: SUHost!, domain: String!) {
        updateSharedState {
            return $0.withUpdatedLoadingState(.initializing)
        }
        super.checkForUpdates(at: url, host: aHost, domain: domain)

    }
    
    override func downloadUpdate() {
        if isStaging {
            downloadKeepingReadyUpdate()
            return
        }
        updateSharedState {
            return $0.withUpdatedLoadingState(.loading(item: self.updateItem, current: 0, total: Int(self.updateItem.contentLength)))
        }
        super.downloadUpdate()
    }
    
    override func downloaderDidFinish(withTemporaryDownloadData downloadData: SPUDownloadData!) {
        super.downloaderDidFinish(withTemporaryDownloadData: downloadData)
    }
    
    override func unarchiverDidFinish(_ ua: Any!) {
        if isStaging {
            promoteStagedUpdate(self)
            return
        }
        updateSharedState {
            return $0.withUpdatedLoadingState(.readyToInstall(self.updateItem))
        }
    }
    
    override func unarchiver(_ ua: Any!, extractedProgress progress: Double) {
        
    }
    
    override func downloaderDidReceiveData(ofLength length: UInt64) {
        updateSharedState { state in
            switch state.loadingState {
            case let .loading(item, current, total):
                return state.withUpdatedLoadingState(.loading(item: item, current: current + Int(length), total: total))
            default:
                return state
            }
        }
    }
    
    override func downloaderDidReceiveExpectedContentLength(_ expectedContentLength: Int64) {
        updateSharedState { state in
            return state.withUpdatedLoadingState(.loading(item: self.updateItem, current: 0, total: Int(expectedContentLength)))
        }
    }
    
    override func downloaderDidFailWithError(_ error: Error!) {
        super.downloaderDidFailWithError(error)
        updateSharedState { state in
            return state.withUpdatedLoadingState(.failed(error as NSError? ?? NSError(domain: strings().unknownError, code: 0, userInfo: nil)))
        }
        if isCurrentDriver {
            trySwitchUpdaterBetweenSources()
        }
    }
    
    override func abortUpdateWithError(_ error: Error!) {
        super.abortUpdateWithError(error)
        if isStaging {
            Queue.mainQueue().async {
                dropStagedUpdate(self, failed: true)
            }
            return
        }
        updateSharedState { state in
            return state.withUpdatedLoadingState(.failed(error as NSError? ?? NSError(domain: strings().unknownError, code: 0, userInfo: nil)))
        }
        if isCurrentDriver {
            trySwitchUpdaterBetweenSources()
        }
    }
    
    override func installer(for host: SUHost!, failedWithError error: Error!) {
        super.installer(for: host, failedWithError: error)
        updateSharedState { state in
            return state.withUpdatedLoadingState(.failed(error as NSError? ?? NSError(domain: strings().unknownError, code: 0, userInfo: nil)))
        }
        if isCurrentDriver {
            trySwitchUpdaterBetweenSources()
        }
    }
}




private let disposable = MetaDisposable()

func setAppUpdaterBaseDomain(_ domain: String?) {
    updater.domain = domain
    if let domain = domain {
        updater.host = URL(string: domain)?.host
    } else {
        updater.host = nil
    }
}


func crashRecoveryUpdater() -> CrashRecoveryUpdater {
    let state: Signal<CrashRecoveryUpdateState, NoError> = appUpdateStateSignal |> map { state in
        switch state.loadingState {
        case .nonInited, .initializing:
            return .checking
        case let .loading(item, current, total):
            return .downloading(version: item.displayVersionString ?? "", current: current, total: total)
        case let .hasUpdate(item):
            return .downloading(version: item.displayVersionString ?? "", current: 0, total: Int(item.contentLength))
        case let .unarchiving(item):
            return .preparing(version: item.displayVersionString ?? "")
        case let .readyToInstall(item):
            return .readyToInstall(version: item.displayVersionString ?? "")
        case .installing:
            return .installing
        case .uptodate:
            return .upToDate
        case .failed:
            return .failed
        }
    }
    return CrashRecoveryUpdater(state: state, check: {
        updater_resetWithUpdaterSource(.external(context: nil))
    }, install: {
        if case .readyToInstall = stateValue.with({ $0.loadingState }) {
            driver?.install(withToolAndRelaunch: true)
        }
    })
}

func updateAppIfNeeded() {
    let state = stateValue.with {$0.loadingState}
    
    switch state {
    case .readyToInstall:
        driver?.install(withToolAndRelaunch: false, displayingUserInterface: true)
    default:
        break
    }
}


enum UpdaterSource : Equatable {
    static func == (lhs: UpdaterSource, rhs: UpdaterSource) -> Bool {
        switch lhs {
        case let .external(lhsContext):
            if case let .external(rhsContext) = rhs {
                return lhsContext === rhsContext
            } else {
                return false
            }
        case let .internal(lhsContext):
            if case let .internal(rhsContext) = rhs {
                return lhsContext === rhsContext
            } else {
                return false
            }
        }
    }
    
    case external(context: AccountContext?)
    case `internal`(context: AccountContext)
}


private var updateFeedURL: URL {
    return URL(string: Bundle.main.infoDictionary!["SUFeedURL"] as! String)!
}

private func makeUpdateDriver(_ source: UpdaterSource) -> ExternalUpdateDriver {
    switch source {
    case .external:
        return ExternalUpdateDriver(updater: updater)
    case let .internal(context):
        return InternalUpdateDriver(updater: updater, context: context)
    }
}

private var stagedDriver: ExternalUpdateDriver?
private var stagedStartedAt: CFAbsoluteTime = 0
private let stagedUpdateTimeout: CFAbsoluteTime = 60 * 60

private func stageNewerUpdate() {
    guard case let .readyToInstall(item) = stateValue.with({ $0.loadingState }), let source = updaterSource else {
        return
    }
    if stagedDriver != nil {
        if CFAbsoluteTimeGetCurrent() - stagedStartedAt < stagedUpdateTimeout {
            return
        }
        cancelStagedUpdate()
    }
    if let downloadPath = driver?.downloadPath {
        let downloadDirectory = ((downloadPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: downloadDirectory)
    }
    let staged = makeUpdateDriver(source)
    staged.stagedOver = item
    stagedDriver = staged
    stagedStartedAt = CFAbsoluteTimeGetCurrent()
    staged.checkForUpdates(at: updateFeedURL, host: host, domain: updater.host)
}

private func promoteStagedUpdate(_ staged: ExternalUpdateDriver) {
    guard stagedDriver === staged, case .readyToInstall = stateValue.with({ $0.loadingState }) else {
        if stagedDriver === staged {
            stagedDriver = nil
        }
        staged.cleanUpDownload()
        return
    }
    let previous = driver
    stagedDriver = nil
    staged.stagedOver = nil
    driver = staged
    updateState {
        $0.withUpdatedLoadingState(.readyToInstall(staged.updateItem))
    }
    previous?.cleanUpDownload()
}

private func dropStagedUpdate(_ staged: ExternalUpdateDriver, failed: Bool) {
    guard stagedDriver === staged else {
        return
    }
    stagedDriver = nil
    if failed, let source = updaterSource, let alternate = alternateUpdaterSource(source) {
        updaterSource = alternate
    }
}

private func cancelStagedUpdate() {
    guard let staged = stagedDriver else {
        return
    }
    stagedDriver = nil
    staged.download?.cancel()
    staged.abortUpdate()
}

public final class ScopegramUpdateManager: NSObject, URLSessionDownloadDelegate {
    public static let shared = ScopegramUpdateManager()
    
    public var repository: String {
        get {
            return UserDefaults.standard.string(forKey: "scopegram.updateRepo") ?? "lonestill/telegram-macos"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "scopegram.updateRepo")
        }
    }
    
    private var currentDownloadTask: URLSessionDownloadTask?
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    public private(set) var latestItem: SUAppcastItem?
    public private(set) var downloadedFilePath: String?
    private var isChecking = false
    
    public func checkNow(manual: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        
        updateState { $0.withUpdatedLoadingState(.initializing) }
        
        guard let url = URL(string: "https://api.github.com/repos/\(self.repository)/releases/latest") else {
            isChecking = false
            updateState { $0.withUpdatedLoadingState(.failed(NSError(domain: "Invalid update URL", code: -1, userInfo: nil))) }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Scopegram-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                
                if let error = error {
                    if manual {
                        updateState { $0.withUpdatedLoadingState(.failed(error as NSError)) }
                    } else {
                        updateState { $0.withUpdatedLoadingState(.uptodate) }
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                    if manual {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        updateState { $0.withUpdatedLoadingState(.failed(NSError(domain: "Не удалось получить релиз с GitHub (код \(code))", code: code, userInfo: nil))) }
                    } else {
                        updateState { $0.withUpdatedLoadingState(.uptodate) }
                    }
                    return
                }
                
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let tagName = json["tag_name"] as? String else {
                        updateState { $0.withUpdatedLoadingState(.uptodate) }
                        return
                    }
                    
                    let cleanRemoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                    let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
                    
                    let isNewer = SUStandardVersionComparator().compareVersion(currentVersion, toVersion: cleanRemoteVersion) == .orderedAscending
                    
                    if isNewer {
                        let releaseName = (json["name"] as? String) ?? "Scopegram \(tagName)"
                        let body = (json["body"] as? String) ?? "Новая версия Scopegram доступна для обновления."
                        
                        var assetUrlString = ""
                        var assetSize: Int64 = 0
                        
                        if let assets = json["assets"] as? [[String: Any]] {
                            for asset in assets {
                                if let name = asset["name"] as? String, (name.hasSuffix(".dmg") || name.hasSuffix(".zip")) {
                                    if let url = asset["browser_download_url"] as? String {
                                        assetUrlString = url
                                        assetSize = (asset["size"] as? Int64) ?? 0
                                        if name.hasSuffix(".dmg") {
                                            break
                                        }
                                    }
                                }
                            }
                        }
                        
                        if assetUrlString.isEmpty {
                            assetUrlString = (json["html_url"] as? String) ?? "https://github.com/\(self.repository)/releases"
                        }
                        
                        let enclosure: [String: Any] = [
                            "url": assetUrlString,
                            "length": "\(assetSize)",
                            "sparkle:version": cleanRemoteVersion,
                            "sparkle:shortVersionString": cleanRemoteVersion,
                            "type": "application/octet-stream"
                        ]
                        let dict: [String: Any] = [
                            "title": releaseName,
                            "description": body,
                            "sparkle:version": cleanRemoteVersion,
                            "sparkle:shortVersionString": cleanRemoteVersion,
                            "enclosure": enclosure
                        ]
                        
                        if let item = SUAppcastItem(dictionary: dict, domain: nil) {
                            self.latestItem = item
                            updateState { $0.withUpdatedLoadingState(.hasUpdate(item)) }
                        } else {
                            updateState { $0.withUpdatedLoadingState(.uptodate) }
                        }
                    } else {
                        updateState { $0.withUpdatedLoadingState(.uptodate) }
                    }
                } catch {
                    if manual {
                        updateState { $0.withUpdatedLoadingState(.failed(error as NSError)) }
                    } else {
                        updateState { $0.withUpdatedLoadingState(.uptodate) }
                    }
                }
            }
        }.resume()
    }
    
    public func startDownload() {
        guard let item = self.latestItem, let downloadUrl = item.fileURL else { return }
        
        let task = downloadSession.downloadTask(with: downloadUrl)
        self.currentDownloadTask = task
        updateState { $0.withUpdatedLoadingState(.loading(item: item, current: 0, total: Int(item.contentLength))) }
        task.resume()
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let item = self.latestItem else { return }
        let total = totalBytesExpectedToWrite > 0 ? Int(totalBytesExpectedToWrite) : Int(item.contentLength)
        updateState { $0.withUpdatedLoadingState(.loading(item: item, current: Int(totalBytesWritten), total: total)) }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = self.latestItem else { return }
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let destUrl = downloadsDir.appendingPathComponent("Scopegram-\(item.displayVersionString ?? "latest").dmg")
        
        try? FileManager.default.removeItem(at: destUrl)
        do {
            try FileManager.default.copyItem(at: location, to: destUrl)
            self.downloadedFilePath = destUrl.path
            updateState { $0.withUpdatedLoadingState(.readyToInstall(item)) }
        } catch {
            updateState { $0.withUpdatedLoadingState(.failed(error as NSError)) }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            updateState { $0.withUpdatedLoadingState(.failed(error as NSError)) }
        }
    }
    
    public func installUpdate() {
        guard let path = self.downloadedFilePath, FileManager.default.fileExists(atPath: path) else {
            if let url = self.latestItem?.fileURL {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}

private func resetUpdater() {
    ScopegramUpdateManager.shared.checkNow(manual: false)
}

private var updaterSource: UpdaterSource? = nil

func updater_resetWithUpdaterSource(_ source: UpdaterSource, force: Bool = true) {
    updaterSource = source
    ScopegramUpdateManager.shared.checkNow(manual: force)
}


private func alternateUpdaterSource(_ source: UpdaterSource) -> UpdaterSource? {
    switch source {
    case let .external(context):
        #if STABLE || DEBUG || BETA
        if let context = context {
            return .internal(context: context)
        }
        #endif
        return nil
    case let .internal(context):
        return .external(context: context)
    }
}

private func trySwitchUpdaterBetweenSources() {
    if let source = updaterSource, let alternate = alternateUpdaterSource(source) {
        switch alternate {
        case .internal:
            updater_resetWithUpdaterSource(alternate, force: true)
        case .external:
            updater_resetWithUpdaterSource(alternate, force: false)
        }
    }
}

#endif

