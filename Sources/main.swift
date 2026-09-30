import AppKit
import Foundation
import Darwin
import QuickLookUI

// MARK: - Preferences

enum ConflictStrategy: String, CaseIterable {
    case addNumber
    case addTimestamp
    case cancelRename
}

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark
}

enum PreferenceKey {
    static let autoRenameHighConfidence = "autoRenameHighConfidence"
    static let confirmationThreshold = "confirmationThreshold"
    static let alwaysConfirmExecutable = "alwaysConfirmExecutable"
    static let alwaysConfirmAmbiguous = "alwaysConfirmAmbiguous"
    static let showConfidence = "showConfidence"
    static let showExplanation = "showExplanation"
    static let conflictStrategy = "conflictStrategy"
    static let maximumFilenameLength = "maximumFilenameLength"
    static let preserveOriginalExtension = "preserveOriginalExtension"
    static let language = "language"
    static let appearance = "appearance"
}

final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            PreferenceKey.autoRenameHighConfidence: true,
            PreferenceKey.confirmationThreshold: 95,
            PreferenceKey.alwaysConfirmExecutable: true,
            PreferenceKey.alwaysConfirmAmbiguous: true,
            PreferenceKey.showConfidence: true,
            PreferenceKey.showExplanation: true,
            PreferenceKey.conflictStrategy: ConflictStrategy.addNumber.rawValue,
            PreferenceKey.maximumFilenameLength: 180,
            PreferenceKey.preserveOriginalExtension: true,
            PreferenceKey.language: AppLanguage.system.rawValue,
            PreferenceKey.appearance: AppearanceMode.system.rawValue
        ])
    }

    var autoRenameHighConfidence: Bool {
        get { defaults.bool(forKey: PreferenceKey.autoRenameHighConfidence) }
        set { defaults.set(newValue, forKey: PreferenceKey.autoRenameHighConfidence) }
    }

    var confirmationThreshold: Int {
        get {
            let value = defaults.integer(forKey: PreferenceKey.confirmationThreshold)
            return min(100, max(60, value == 0 ? 95 : value))
        }
        set { defaults.set(min(100, max(60, newValue)), forKey: PreferenceKey.confirmationThreshold) }
    }

    var alwaysConfirmExecutable: Bool {
        get { defaults.bool(forKey: PreferenceKey.alwaysConfirmExecutable) }
        set { defaults.set(newValue, forKey: PreferenceKey.alwaysConfirmExecutable) }
    }

    var alwaysConfirmAmbiguous: Bool {
        get { defaults.bool(forKey: PreferenceKey.alwaysConfirmAmbiguous) }
        set { defaults.set(newValue, forKey: PreferenceKey.alwaysConfirmAmbiguous) }
    }

    var showConfidence: Bool {
        get { defaults.bool(forKey: PreferenceKey.showConfidence) }
        set { defaults.set(newValue, forKey: PreferenceKey.showConfidence) }
    }

    var showExplanation: Bool {
        get { defaults.bool(forKey: PreferenceKey.showExplanation) }
        set { defaults.set(newValue, forKey: PreferenceKey.showExplanation) }
    }

    var conflictStrategy: ConflictStrategy {
        get { ConflictStrategy(rawValue: defaults.string(forKey: PreferenceKey.conflictStrategy) ?? "") ?? .addNumber }
        set { defaults.set(newValue.rawValue, forKey: PreferenceKey.conflictStrategy) }
    }

    var maximumFilenameLength: Int {
        get {
            let value = defaults.integer(forKey: PreferenceKey.maximumFilenameLength)
            return min(255, max(1, value == 0 ? 180 : value))
        }
        set { defaults.set(min(255, max(1, newValue)), forKey: PreferenceKey.maximumFilenameLength) }
    }

    var preserveOriginalExtension: Bool {
        get { defaults.bool(forKey: PreferenceKey.preserveOriginalExtension) }
        set { defaults.set(newValue, forKey: PreferenceKey.preserveOriginalExtension) }
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: PreferenceKey.language) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: PreferenceKey.language) }
    }

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.string(forKey: PreferenceKey.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: PreferenceKey.appearance) }
    }
}

// MARK: - Localization + appearance

enum Localization {
    static func string(_ key: String) -> String {
        let language = Preferences.shared.language
        let bundle: Bundle
        switch language {
        case .system:
            bundle = .main
        case .english, .simplifiedChinese:
            if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
               let localizedBundle = Bundle(path: path) {
                bundle = localizedBundle
            } else {
                bundle = .main
            }
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

}

@inline(__always) func L(_ key: String) -> String { Localization.string(key) }
@inline(__always) func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}

enum AppearanceManager {
    static func apply() {
        switch Preferences.shared.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Cross-process confirmation queue

final class ConfirmationQueueLock {
    private var descriptor: Int32 = -1

    init?() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("AutoFilenameHelper", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let lockPath = directory.appendingPathComponent("confirmation.lock").path
        descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }
    }

    func waitForTurn() -> Bool {
        guard descriptor >= 0 else { return false }
        while Darwin.lockf(descriptor, F_LOCK, 0) != 0 {
            if errno == EINTR { continue }
            return false
        }
        return true
    }

    deinit {
        if descriptor >= 0 {
            _ = Darwin.lockf(descriptor, F_ULOCK, 0)
            _ = Darwin.close(descriptor)
        }
    }
}

// MARK: - Payload + rename engine

struct RenameRequest {
    let path: String
    let quality: String
    let suggested: String
    let confidence: Int
    let reason: String
}

struct PreparedRename {
    let request: RenameRequest
    let oldName: String
    let originalSuffix: String
    let protectedSuffix: String
    let isExecutable: Bool
    let isDirectory: Bool
}

enum PayloadParser {
    static func parse(_ payload: String) -> RenameRequest? {
        let lines = payload.components(separatedBy: .newlines)

        guard let pathLine = lines.first(where: { $0.hasPrefix("PATH_B64=") }) else { return nil }
        let encodedPath = String(pathLine.dropFirst("PATH_B64=".count))
        guard !encodedPath.isEmpty,
              let pathData = Data(base64Encoded: encodedPath),
              let path = String(data: pathData, encoding: .utf8),
              !path.isEmpty else { return nil }

        guard let qualityLine = lines.first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("INITIAL_QUALITY=")
        }) else { return nil }

        let qualityRaw: String
        if let equalIndex = qualityLine.firstIndex(of: "=") {
            qualityRaw = String(qualityLine[qualityLine.index(after: equalIndex)...])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\r", with: "")
        } else {
            return nil
        }
        let quality = qualityRaw.lowercased()

        let suggested = lastValue(for: "suggestedFilename", in: lines)
        let reason = lastValue(for: "reason", in: lines)
        guard !suggested.isEmpty else { return nil }

        let confidenceText = lastValue(for: "confidence", in: lines)
        let digits = confidenceText.filter { $0.isNumber }
        guard !digits.isEmpty, let confidence = Int(digits) else { return nil }

        return RenameRequest(path: path,
                             quality: quality,
                             suggested: suggested,
                             confidence: confidence,
                             reason: reason)
    }

    private static func lastValue(for key: String, in lines: [String]) -> String {
        let prefix = key.lowercased() + ":"
        for line in lines.reversed() {
            let leftTrimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let lowered = leftTrimmed.lowercased()
            if lowered.hasPrefix(prefix) {
                let start = leftTrimmed.index(leftTrimmed.startIndex, offsetBy: prefix.count)
                let raw = String(leftTrimmed[start...])
                return String(raw.drop(while: { $0 == " " || $0 == "\t" }))
                    .replacingOccurrences(of: "\r", with: "")
            }
        }
        return ""
    }
}

enum RenameEngine {
    private static let executableExtensions: Set<String> = [
        "exe", "msi", "pkg", "dmg", "app", "bundle", "framework", "plugin", "kext",
        "command", "sh", "bash", "zsh", "fish", "py", "pl", "rb", "js", "jar"
    ]

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    static func prepare(_ request: RenameRequest) -> PreparedRename? {
        guard request.quality == "ambiguous" || request.quality == "meaningless" else { return nil }
        guard (60...100).contains(request.confidence) else { return nil }
        guard let kind = safeSourceKind(at: request.path) else { return nil }

        let oldName = (request.path as NSString).lastPathComponent
        let lowerOld = oldName.lowercased()
        let originalSuffix = suffixFor(name: oldName, lowerName: lowerOld, isDirectory: kind.isDirectory)
        let protectedSuffix = Preferences.shared.preserveOriginalExtension ? originalSuffix : ""

        guard validate(candidate: request.suggested,
                       oldName: oldName,
                       suffix: protectedSuffix,
                       maxLength: Preferences.shared.maximumFilenameLength) else { return nil }

        var executable = false
        let ext = (oldName as NSString).pathExtension.lowercased()
        if executableExtensions.contains(ext) { executable = true }
        let suggestedExt = (request.suggested as NSString).pathExtension.lowercased()
        if executableExtensions.contains(suggestedExt) { executable = true }

        let desc = fileDescription(path: request.path).lowercased()
        if desc.contains("executable") || desc.contains("script") { executable = true }

        return PreparedRename(request: request,
                              oldName: oldName,
                              originalSuffix: originalSuffix,
                              protectedSuffix: protectedSuffix,
                              isExecutable: executable,
                              isDirectory: kind.isDirectory)
    }

    static func validate(candidate: String,
                         oldName: String,
                         suffix: String,
                         maxLength: Int) -> Bool {
        guard !candidate.isEmpty,
              !candidate.hasPrefix("."),
              candidate != ".",
              candidate != "..",
              !candidate.contains("/"),
              !candidate.contains(":"),
              !candidate.contains("\n"),
              !candidate.contains("\r"),
              candidate.count <= maxLength,
              candidate != oldName else { return false }

        if !suffix.isEmpty {
            guard candidate.lowercased().hasSuffix(suffix.lowercased()) else { return false }
        }
        return true
    }

    static func needsConfirmation(_ prepared: PreparedRename) -> Bool {
        !confirmationReasons(prepared).isEmpty
    }

    static func confirmationReasons(_ prepared: PreparedRename) -> [String] {
        let prefs = Preferences.shared
        var reasons: [String] = []
        if !prefs.autoRenameHighConfidence {
            reasons.append(L("confirmation.auto_disabled"))
        }
        if prefs.alwaysConfirmAmbiguous && prepared.request.quality == "ambiguous" {
            reasons.append(L("confirmation.ambiguous"))
        }
        if prepared.request.confidence < prefs.confirmationThreshold {
            reasons.append(LF("confirmation.low_confidence", prefs.confirmationThreshold))
        }
        if prefs.alwaysConfirmExecutable && prepared.isExecutable {
            reasons.append(L("confirmation.executable"))
        }
        return reasons
    }

    static func confirmationReasonText(_ prepared: PreparedRename) -> String {
        let reasons = confirmationReasons(prepared)
        guard !reasons.isEmpty else { return "" }
        return LF("confirmation.required", reasons.joined(separator: " · "))
    }

    @discardableResult
    static func rename(_ prepared: PreparedRename, candidate requestedCandidate: String) -> Bool {
        let prefs = Preferences.shared
        guard validate(candidate: requestedCandidate,
                       oldName: prepared.oldName,
                       suffix: prepared.protectedSuffix,
                       maxLength: prefs.maximumFilenameLength) else { return false }
        guard safeSourceKind(at: prepared.request.path) != nil else { return false }

        let sourceURL = URL(fileURLWithPath: prepared.request.path)
        let directoryURL = sourceURL.deletingLastPathComponent()
        guard let targetURL = resolvedTargetURL(directoryURL: directoryURL,
                                               requestedCandidate: requestedCandidate,
                                               prepared: prepared,
                                               strategy: prefs.conflictStrategy) else { return false }

        guard safeSourceKind(at: prepared.request.path) != nil else { return false }
        guard !pathLexicallyExists(targetURL.path) else { return false }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            return true
        } catch {
            return false
        }
    }

    static func editableText(for candidate: String, protectedSuffix: String) -> String {
        guard !protectedSuffix.isEmpty,
              candidate.lowercased().hasSuffix(protectedSuffix.lowercased()),
              candidate.count >= protectedSuffix.count else { return candidate }
        return String(candidate.dropLast(protectedSuffix.count))
    }

    private static func resolvedTargetURL(directoryURL: URL,
                                          requestedCandidate: String,
                                          prepared: PreparedRename,
                                          strategy: ConflictStrategy) -> URL? {
        let direct = directoryURL.appendingPathComponent(requestedCandidate)
        if !pathLexicallyExists(direct.path) { return direct }

        switch strategy {
        case .cancelRename:
            return nil
        case .addNumber:
            let parts = conflictNameParts(candidate: requestedCandidate, prepared: prepared)
            var counter = 2
            while true {
                let addon = " \(counter)"
                guard let name = conflictName(stem: parts.stem, suffix: parts.suffix, addon: addon) else { return nil }
                let target = directoryURL.appendingPathComponent(name)
                if !pathLexicallyExists(target.path) { return target }
                counter += 1
            }
        case .addTimestamp:
            let parts = conflictNameParts(candidate: requestedCandidate, prepared: prepared)
            let timestamp = timestampFormatter.string(from: Date())
            var addon = " \(timestamp)"
            guard var name = conflictName(stem: parts.stem, suffix: parts.suffix, addon: addon) else { return nil }
            var target = directoryURL.appendingPathComponent(name)
            if !pathLexicallyExists(target.path) { return target }
            var counter = 2
            while true {
                addon = " \(timestamp) \(counter)"
                guard let nextName = conflictName(stem: parts.stem, suffix: parts.suffix, addon: addon) else { return nil }
                name = nextName
                target = directoryURL.appendingPathComponent(name)
                if !pathLexicallyExists(target.path) { return target }
                counter += 1
            }
        }
    }

    private static func conflictName(stem: String, suffix: String, addon: String) -> String? {
        let maxLength = Preferences.shared.maximumFilenameLength
        let reserved = suffix.count + addon.count
        guard maxLength > reserved else { return nil }
        let availableStemLength = maxLength - reserved
        let trimmedStem = String(stem.prefix(availableStemLength))
        guard !trimmedStem.isEmpty else { return nil }
        return trimmedStem + addon + suffix
    }

    private static func conflictNameParts(candidate: String, prepared: PreparedRename) -> (stem: String, suffix: String) {
        if !prepared.protectedSuffix.isEmpty,
           candidate.lowercased().hasSuffix(prepared.protectedSuffix.lowercased()),
           candidate.count >= prepared.protectedSuffix.count {
            return (String(candidate.dropLast(prepared.protectedSuffix.count)), prepared.protectedSuffix)
        }

        guard !prepared.isDirectory else { return (candidate, "") }
        let lower = candidate.lowercased()
        let suffix = suffixFor(name: candidate, lowerName: lower, isDirectory: false)
        guard !suffix.isEmpty, candidate.count >= suffix.count else { return (candidate, "") }
        return (String(candidate.dropLast(suffix.count)), suffix)
    }

    private static func suffixFor(name: String, lowerName: String, isDirectory: Bool) -> String {
        if isDirectory {
            for ext in ["app", "bundle", "framework", "plugin", "kext"] {
                if lowerName.hasSuffix(".\(ext)") {
                    let rawExt = (name as NSString).pathExtension
                    return rawExt.isEmpty ? "" : ".\(rawExt)"
                }
            }
            return ""
        }

        if lowerName.hasSuffix(".tar.gz") { return String(name.suffix(7)) }
        if lowerName.hasSuffix(".tar.bz2") { return String(name.suffix(8)) }
        if lowerName.hasSuffix(".tar.xz") { return String(name.suffix(7)) }

        guard name.contains(".") else { return "" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    private static func safeSourceKind(at path: String) -> (isDirectory: Bool, isRegular: Bool)? {
        let url = URL(fileURLWithPath: path)
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if values.isSymbolicLink == true { return nil }
            let regular = values.isRegularFile == true
            let directory = values.isDirectory == true
            guard regular || directory else { return nil }
            return (directory, regular)
        } catch {
            return nil
        }
    }

    private static func pathLexicallyExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private static func fileDescription(path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = ["-b", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

// MARK: - View helpers

func label(_ text: String,
           font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
           color: NSColor = .labelColor,
           wraps: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.maximumNumberOfLines = wraps ? 0 : 1
    field.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

func frostedWindow(contentRect: NSRect, title: String) -> NSWindow {
    let window = NSWindow(contentRect: contentRect,
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear

    let effect = NSVisualEffectView(frame: contentRect)
    effect.material = .underWindowBackground
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.autoresizingMask = [.width, .height]
    window.contentView = effect
    return window
}

private func informationCard(title: String,
                             valueLabel: NSTextField,
                             emphasized: Bool = false) -> NSBox {
    let box = NSBox()
    box.boxType = .custom
    box.borderWidth = 0
    box.cornerRadius = 8
    box.fillColor = emphasized
        ? NSColor.controlAccentColor.withAlphaComponent(0.10)
        : NSColor.controlBackgroundColor.withAlphaComponent(0.42)
    box.translatesAutoresizingMaskIntoConstraints = false
    box.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    box.contentView?.addSubview(stack)

    let header = label(title,
                       font: .systemFont(ofSize: 11.5, weight: .medium),
                       color: .secondaryLabelColor)
    stack.addArrangedSubview(header)
    stack.addArrangedSubview(valueLabel)

    if let content = box.contentView {
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -9)
        ])
    }
    return box
}

private func extensionPill(suffix: String) -> NSView {
    let box = NSBox()
    box.boxType = .custom
    box.borderWidth = 0
    box.cornerRadius = 6
    box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.58)
    box.translatesAutoresizingMaskIntoConstraints = false

    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 5
    row.translatesAutoresizingMaskIntoConstraints = false

    let ext = label(suffix, font: .systemFont(ofSize: 13, weight: .medium), color: .secondaryLabelColor)
    row.addArrangedSubview(ext)

    if let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: L("extension.locked")) {
        let lock = NSImageView()
        lock.image = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        lock.contentTintColor = .secondaryLabelColor
        lock.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lock.widthAnchor.constraint(equalToConstant: 13),
            lock.heightAnchor.constraint(equalToConstant: 13)
        ])
        row.addArrangedSubview(lock)
    }

    box.contentView?.addSubview(row)
    if let content = box.contentView {
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -9),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5)
        ])
    }
    return box
}

// MARK: - Confirmation window

final class ConfirmationWindowController: NSWindowController, NSTextFieldDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let prepared: PreparedRename
    private var candidate: String
    private let onFinished: () -> Void

    private let bodyStack = NSStackView()
    private let oldValueLabel = label("", font: .systemFont(ofSize: 13.5, weight: .regular), wraps: true)
    private let suggestedValueLabel = label("", font: .systemFont(ofSize: 15.5, weight: .semibold), color: .controlAccentColor, wraps: true)
    private let reasonValueLabel = label("", font: .systemFont(ofSize: 13), color: .secondaryLabelColor, wraps: true)
    private let confidenceLabel = label("", font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium))
    private let confidenceProgress = NSProgressIndicator()
    private let editField = NSTextField()
    private let previewLabel = label("", font: .systemFont(ofSize: 13.5, weight: .medium), wraps: true)
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var confirmationReasonLabel: NSTextField!
    private var keepButton: NSButton!
    private var editButton: NSButton!
    private var renameButton: NSButton!
    private var cancelEditButton: NSButton!
    private var normalViews: [NSView] = []
    private var editViews: [NSView] = []
    private var confidenceViews: [NSView] = []
    private var explanationViews: [NSView] = []
    private var keyMonitor: Any?
    private var isEditingName = false

    init(prepared: PreparedRename, onFinished: @escaping () -> Void) {
        self.prepared = prepared
        self.candidate = prepared.request.suggested
        self.onFinished = onFinished
        super.init(window: frostedWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 414), title: "Auto Filename"))
        window?.delegate = self
        buildUI()
        installKeyboardShortcuts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 42),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22)
        ])

        let iconView = NSImageView()
        iconView.image = NSWorkspace.shared.icon(forFile: prepared.request.path)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.toolTip = L("file_actions.tooltip")
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72)
        ])
        iconView.menu = fileActionsMenu()
        root.addArrangedSubview(iconView)

        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 8
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(bodyStack)
        bodyStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 350).isActive = true

        oldValueLabel.stringValue = prepared.oldName
        suggestedValueLabel.stringValue = candidate
        reasonValueLabel.stringValue = prepared.request.reason
        confidenceLabel.stringValue = "\(prepared.request.confidence)%"

        titleLabel = label(L("rename.title"), font: .systemFont(ofSize: 22, weight: .bold))
        subtitleLabel = label(L("rename.subtitle"), color: .secondaryLabelColor, wraps: true)
        confirmationReasonLabel = label(RenameEngine.confirmationReasonText(prepared),
                                        font: .systemFont(ofSize: 11.5, weight: .medium),
                                        color: .secondaryLabelColor,
                                        wraps: true)
        bodyStack.addArrangedSubview(titleLabel)
        bodyStack.addArrangedSubview(subtitleLabel)
        bodyStack.addArrangedSubview(confirmationReasonLabel)
        bodyStack.setCustomSpacing(14, after: confirmationReasonLabel)

        let originalCard = informationCard(title: L("original_filename"), valueLabel: oldValueLabel)
        let suggestedCard = informationCard(title: L("suggested_filename"), valueLabel: suggestedValueLabel, emphasized: true)
        bodyStack.addArrangedSubview(originalCard)
        bodyStack.addArrangedSubview(suggestedCard)
        originalCard.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true
        suggestedCard.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true

        bodyStack.setCustomSpacing(12, after: suggestedCard)
        let confidenceHeader = label(L("confidence"), font: .systemFont(ofSize: 11.5, weight: .medium), color: .secondaryLabelColor)
        let confidenceRow = NSStackView()
        confidenceRow.orientation = .horizontal
        confidenceRow.alignment = .centerY
        confidenceRow.spacing = 9
        confidenceProgress.style = .bar
        confidenceProgress.isIndeterminate = false
        confidenceProgress.minValue = 0
        confidenceProgress.maxValue = 100
        confidenceProgress.doubleValue = Double(prepared.request.confidence)
        confidenceProgress.controlSize = .small
        confidenceProgress.translatesAutoresizingMaskIntoConstraints = false
        confidenceProgress.widthAnchor.constraint(equalToConstant: 205).isActive = true
        confidenceRow.addArrangedSubview(confidenceProgress)
        confidenceRow.addArrangedSubview(confidenceLabel)
        bodyStack.addArrangedSubview(confidenceHeader)
        bodyStack.addArrangedSubview(confidenceRow)
        confidenceViews = [confidenceHeader, confidenceRow]

        bodyStack.setCustomSpacing(10, after: confidenceRow)
        let reasonHeader = label(L("reason"), font: .systemFont(ofSize: 11.5, weight: .medium), color: .secondaryLabelColor)
        bodyStack.addArrangedSubview(reasonHeader)
        bodyStack.addArrangedSubview(reasonValueLabel)
        explanationViews = [reasonHeader, reasonValueLabel]

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
        bodyStack.addArrangedSubview(spacer)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY
        keepButton = NSButton(title: L("keep_original"), target: self, action: #selector(keepOriginal))
        keepButton.refusesFirstResponder = true
        editButton = NSButton(title: L("edit_name"), target: self, action: #selector(enterEditMode))
        editButton.refusesFirstResponder = true
        renameButton = NSButton(title: L("rename"), target: self, action: #selector(renameNow))
        buttons.addArrangedSubview(keepButton)
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(buttonSpacer)
        buttons.addArrangedSubview(editButton)
        buttons.addArrangedSubview(renameButton)
        bodyStack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true

        normalViews = [originalCard, suggestedCard, confirmationReasonLabel,
                       confidenceHeader, confidenceRow, reasonHeader, reasonValueLabel, spacer, buttons]

        let editHeader = label(L("edit_filename"), font: .systemFont(ofSize: 21, weight: .bold))
        let editHelpKey = prepared.protectedSuffix.isEmpty ? "extension_unlocked_help" : "extension_locked_help"
        let editHelp = label(L(editHelpKey), color: .secondaryLabelColor, wraps: true)
        let filenameHeader = label(L("filename"), font: .systemFont(ofSize: 11.5, weight: .medium), color: .secondaryLabelColor)

        let editRow = NSStackView()
        editRow.orientation = .horizontal
        editRow.spacing = 8
        editRow.alignment = .centerY
        editField.stringValue = RenameEngine.editableText(for: candidate, protectedSuffix: prepared.protectedSuffix)
        editField.delegate = self
        editField.translatesAutoresizingMaskIntoConstraints = false
        editField.widthAnchor.constraint(greaterThanOrEqualToConstant: 245).isActive = true
        editRow.addArrangedSubview(editField)
        if !prepared.protectedSuffix.isEmpty {
            editRow.addArrangedSubview(extensionPill(suffix: prepared.protectedSuffix))
        }

        let previewHeader = label(L("preview"), font: .systemFont(ofSize: 11.5, weight: .medium), color: .secondaryLabelColor)
        previewLabel.stringValue = candidate

        let editButtons = NSStackView()
        editButtons.orientation = .horizontal
        editButtons.spacing = 10
        let editSpacer = NSView()
        editSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        editSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        editButtons.addArrangedSubview(editSpacer)
        cancelEditButton = NSButton(title: L("cancel"), target: self, action: #selector(cancelEditMode))
        cancelEditButton.refusesFirstResponder = true
        let confirmEditButton = NSButton(title: L("rename"), target: self, action: #selector(renameEdited))
        editButtons.addArrangedSubview(cancelEditButton)
        editButtons.addArrangedSubview(confirmEditButton)

        editViews = [editHeader, editHelp, filenameHeader, editRow, previewHeader, previewLabel, editButtons]
        for view in editViews {
            view.isHidden = true
            bodyStack.addArrangedSubview(view)
        }
        editButtons.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true

        applyVisibilityPreferences()
        window?.defaultButtonCell = renameButton.cell as? NSButtonCell
        window?.center()
        window?.setContentSize(NSSize(width: 520, height: 414))
    }

    private func fileActionsMenu() -> NSMenu {
        let menu = NSMenu()
        let quickLook = NSMenuItem(title: L("quick_look"), action: #selector(toggleQuickLook), keyEquivalent: "")
        quickLook.target = self
        menu.addItem(quickLook)
        let reveal = NSMenuItem(title: L("show_in_finder"), action: #selector(showInFinder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        let copy = NSMenuItem(title: L("copy_path"), action: #selector(copyPath), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        return menu
    }

    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "e" {
                if !self.isEditingName { self.enterEditMode() }
                return nil
            }

            switch event.keyCode {
            case 36, 76: // Return / keypad Enter
                if self.isEditingName { self.renameEdited() } else { self.renameNow() }
                return nil
            case 53: // Escape
                if self.isEditingName { self.cancelEditMode() } else { self.keepOriginal() }
                return nil
            case 49: // Space = Quick Look, except while typing a filename
                if !self.isEditingName {
                    self.toggleQuickLook()
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    private func applyVisibilityPreferences() {
        let prefs = Preferences.shared
        confidenceViews.forEach { $0.isHidden = !prefs.showConfidence }
        let hideExplanation = !prefs.showExplanation || prepared.request.reason.isEmpty
        explanationViews.forEach { $0.isHidden = hideExplanation }
    }

    @objc private func keepOriginal() { finish() }

    @objc private func renameNow() {
        _ = RenameEngine.rename(prepared, candidate: candidate)
        finish()
    }

    @objc private func enterEditMode() {
        isEditingName = true
        normalViews.forEach { $0.isHidden = true }
        titleLabel.isHidden = true
        subtitleLabel.isHidden = true
        editViews.forEach { $0.isHidden = false }
        editField.stringValue = RenameEngine.editableText(for: candidate, protectedSuffix: prepared.protectedSuffix)
        updatePreview()
        window?.setContentSize(NSSize(width: 520, height: 292))
        window?.makeFirstResponder(editField)
        editField.currentEditor()?.selectAll(nil)
    }

    @objc private func cancelEditMode() {
        isEditingName = false
        editViews.forEach { $0.isHidden = true }
        titleLabel.isHidden = false
        subtitleLabel.isHidden = false
        normalViews.forEach { $0.isHidden = false }
        applyVisibilityPreferences()
        window?.setContentSize(NSSize(width: 520, height: 414))
        window?.defaultButtonCell = renameButton.cell as? NSButtonCell
    }

    @objc private func renameEdited() {
        let newCandidate = editField.stringValue + prepared.protectedSuffix
        guard RenameEngine.validate(candidate: newCandidate,
                                    oldName: prepared.oldName,
                                    suffix: prepared.protectedSuffix,
                                    maxLength: Preferences.shared.maximumFilenameLength) else {
            NSSound.beep()
            return
        }
        candidate = newCandidate
        _ = RenameEngine.rename(prepared, candidate: candidate)
        finish()
    }

    func controlTextDidChange(_ obj: Notification) { updatePreview() }

    private func updatePreview() {
        previewLabel.stringValue = editField.stringValue + prepared.protectedSuffix
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: prepared.request.path)])
    }

    @objc private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prepared.request.path, forType: .string)
    }

    @objc private func toggleQuickLook() {
        guard FileManager.default.fileExists(atPath: prepared.request.path),
              let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        FileManager.default.fileExists(atPath: prepared.request.path) ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        URL(fileURLWithPath: prepared.request.path) as NSURL
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish()
        return false
    }

    private func finish() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        window?.delegate = nil
        window?.orderOut(nil)
        onFinished()
    }
}

// MARK: - Settings

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private struct SidebarItem {
        let title: String
        let symbol: String
    }

    private var sidebarItems: [SidebarItem] {
        [
            SidebarItem(title: L("settings.general"), symbol: "gearshape"),
            SidebarItem(title: L("settings.filename"), symbol: "doc"),
            SidebarItem(title: L("settings.interface"), symbol: "paintbrush")
        ]
    }

    private let sidebarTable = NSTableView()
    private let contentHost = NSView()
    private var conflictExampleLabel: NSTextField?
    private var maximumLengthField: NSTextField?
    private var maximumLengthStepper: NSStepper?
    private let onLanguageChanged: () -> Void

    init(onLanguageChanged: @escaping () -> Void) {
        self.onLanguageChanged = onLanguageChanged
        super.init(window: frostedWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 390), title: "Auto Filename"))
        window?.titleVisibility = .hidden
        window?.styleMask.insert(.miniaturizable)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let sidebarEffect = NSVisualEffectView()
        sidebarEffect.material = .sidebar
        sidebarEffect.blendingMode = .withinWindow
        sidebarEffect.state = .active
        sidebarEffect.translatesAutoresizingMaskIntoConstraints = false
        sidebarEffect.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        sidebarTable.addTableColumn(column)
        sidebarTable.headerView = nil
        sidebarTable.dataSource = self
        sidebarTable.delegate = self
        sidebarTable.rowHeight = 30
        sidebarTable.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTable.backgroundColor = .clear
        sidebarTable.focusRingType = .none
        sidebarTable.selectionHighlightStyle = .regular
        sidebarTable.allowsEmptySelection = false
        sidebarTable.allowsMultipleSelection = false
        sidebarTable.style = .sourceList
        scrollView.documentView = sidebarTable

        sidebarEffect.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sidebarEffect.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: sidebarEffect.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: sidebarEffect.topAnchor, constant: 50),
            scrollView.bottomAnchor.constraint(equalTo: sidebarEffect.bottomAnchor, constant: -12)
        ])

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(sidebarEffect)
        split.addArrangedSubview(contentHost)

        sidebarTable.reloadData()
        sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showPane(0)
        window?.center()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sidebarItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let item = sidebarItems[row]

        if let reusable = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            reusable.textField?.stringValue = item.title
            reusable.imageView?.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
            return reusable
        }

        let cell = NSTableCellView()
        cell.identifier = identifier

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .secondaryLabelColor
        if let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title) {
            icon.image = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        }

        let text = label(item.title, font: .systemFont(ofSize: 13, weight: .medium))
        cell.imageView = icon
        cell.textField = text
        cell.addSubview(icon)
        cell.addSubview(text)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTable.selectedRow
        if row >= 0 { showPane(row) }
    }

    private func showPane(_ index: Int) {
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        conflictExampleLabel = nil
        maximumLengthField = nil
        maximumLengthStepper = nil

        let view: NSView
        switch index {
        case 1: view = filenamePane()
        case 2: view = interfacePane()
        default: view = generalPane()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 30),
            view.trailingAnchor.constraint(lessThanOrEqualTo: contentHost.trailingAnchor, constant: -30),
            view.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 48),
            view.bottomAnchor.constraint(lessThanOrEqualTo: contentHost.bottomAnchor, constant: -26)
        ])
    }

    private func generalPane() -> NSView {
        let stack = paneStack(title: L("settings.general"))
        let prefs = Preferences.shared

        let auto = checkbox(L("general.auto_rename"), state: prefs.autoRenameHighConfidence)
        auto.target = self
        auto.action = #selector(toggleAuto(_:))
        stack.addArrangedSubview(auto)
        stack.setCustomSpacing(16, after: auto)

        let thresholdLabel = label(L("general.require_below"), font: .systemFont(ofSize: 12.5, weight: .medium))
        stack.addArrangedSubview(thresholdLabel)

        let sliderRow = NSStackView()
        sliderRow.orientation = .horizontal
        sliderRow.alignment = .centerY
        sliderRow.spacing = 10
        let slider = NSSlider(value: Double(prefs.confirmationThreshold), minValue: 60, maxValue: 100, target: self, action: #selector(changeThreshold(_:)))
        slider.numberOfTickMarks = 9
        slider.allowsTickMarkValuesOnly = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let value = label("\(prefs.confirmationThreshold)%", font: .monospacedDigitSystemFont(ofSize: 13, weight: .regular))
        value.identifier = NSUserInterfaceItemIdentifier("thresholdValue")
        sliderRow.addArrangedSubview(slider)
        sliderRow.addArrangedSubview(value)
        stack.addArrangedSubview(sliderRow)
        stack.addArrangedSubview(label(L("general.threshold_help"), font: .systemFont(ofSize: 11.5), color: .secondaryLabelColor))

        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        let executable = checkbox(L("general.confirm_executable"), state: prefs.alwaysConfirmExecutable)
        executable.target = self
        executable.action = #selector(toggleExecutable(_:))
        stack.addArrangedSubview(executable)

        let ambiguous = checkbox(L("general.confirm_ambiguous"), state: prefs.alwaysConfirmAmbiguous)
        ambiguous.target = self
        ambiguous.action = #selector(toggleAmbiguous(_:))
        stack.addArrangedSubview(ambiguous)
        return stack
    }

    private func filenamePane() -> NSView {
        let stack = paneStack(title: L("settings.filename"))
        let prefs = Preferences.shared

        stack.addArrangedSubview(label(L("filename.conflict_label"), font: .systemFont(ofSize: 12.5, weight: .medium)))
        let conflictPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        conflictPopup.addItems(withTitles: [
            L("conflict.add_number"),
            L("conflict.add_timestamp"),
            L("conflict.cancel")
        ])
        let strategies: [ConflictStrategy] = [.addNumber, .addTimestamp, .cancelRename]
        if let index = strategies.firstIndex(of: prefs.conflictStrategy) { conflictPopup.selectItem(at: index) }
        conflictPopup.target = self
        conflictPopup.action = #selector(changeConflictStrategy(_:))
        stack.addArrangedSubview(conflictPopup)

        let example = label(conflictExample(for: prefs.conflictStrategy), font: .systemFont(ofSize: 11.5), color: .secondaryLabelColor)
        conflictExampleLabel = example
        stack.addArrangedSubview(example)

        stack.setCustomSpacing(18, after: example)
        stack.addArrangedSubview(label(L("filename.maximum_length"), font: .systemFont(ofSize: 12.5, weight: .medium)))
        let lengthRow = NSStackView()
        lengthRow.orientation = .horizontal
        lengthRow.alignment = .centerY
        lengthRow.spacing = 8

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: 1)
        formatter.maximum = NSNumber(value: 255)

        let lengthField = NSTextField()
        lengthField.stringValue = "\(prefs.maximumFilenameLength)"
        lengthField.alignment = .right
        lengthField.formatter = formatter
        lengthField.translatesAutoresizingMaskIntoConstraints = false
        lengthField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        lengthField.target = self
        lengthField.action = #selector(changeMaximumLengthField(_:))
        lengthField.delegate = self
        maximumLengthField = lengthField

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 255
        stepper.increment = 1
        stepper.integerValue = prefs.maximumFilenameLength
        stepper.target = self
        stepper.action = #selector(changeMaximumLengthStepper(_:))
        maximumLengthStepper = stepper

        lengthRow.addArrangedSubview(lengthField)
        lengthRow.addArrangedSubview(stepper)
        lengthRow.addArrangedSubview(label(L("filename.characters"), color: .secondaryLabelColor))
        stack.addArrangedSubview(lengthRow)

        stack.setCustomSpacing(18, after: lengthRow)
        let preserve = checkbox(L("filename.preserve_extension"), state: prefs.preserveOriginalExtension)
        preserve.target = self
        preserve.action = #selector(togglePreserveExtension(_:))
        stack.addArrangedSubview(preserve)
        stack.addArrangedSubview(label(L("filename.preserve_help"), font: .systemFont(ofSize: 11.5), color: .secondaryLabelColor, wraps: true))
        return stack
    }

    private func interfacePane() -> NSView {
        let stack = paneStack(title: L("settings.interface"))
        let prefs = Preferences.shared

        stack.addArrangedSubview(label(L("interface.language"), font: .systemFont(ofSize: 12.5, weight: .medium)))
        let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.addItems(withTitles: [
            L("language.system"),
            L("language.english"),
            L("language.chinese_simplified")
        ])
        let languages: [AppLanguage] = [.system, .english, .simplifiedChinese]
        if let index = languages.firstIndex(of: prefs.language) { languagePopup.selectItem(at: index) }
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage(_:))
        stack.addArrangedSubview(languagePopup)

        stack.setCustomSpacing(18, after: languagePopup)
        let showConfidence = checkbox(L("interface.show_confidence"), state: prefs.showConfidence)
        showConfidence.target = self
        showConfidence.action = #selector(toggleShowConfidence(_:))
        stack.addArrangedSubview(showConfidence)

        let showExplanation = checkbox(L("interface.show_explanation"), state: prefs.showExplanation)
        showExplanation.target = self
        showExplanation.action = #selector(toggleShowExplanation(_:))
        stack.addArrangedSubview(showExplanation)

        stack.setCustomSpacing(18, after: showExplanation)
        stack.addArrangedSubview(label(L("interface.appearance"), font: .systemFont(ofSize: 12.5, weight: .medium)))
        let appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.addItems(withTitles: [
            L("appearance.system"),
            L("appearance.light"),
            L("appearance.dark")
        ])
        let modes: [AppearanceMode] = [.system, .light, .dark]
        if let index = modes.firstIndex(of: prefs.appearance) { appearancePopup.selectItem(at: index) }
        appearancePopup.target = self
        appearancePopup.action = #selector(changeAppearance(_:))
        stack.addArrangedSubview(appearancePopup)
        return stack
    }

    private func paneStack(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        let heading = label(title, font: .systemFont(ofSize: 21, weight: .bold))
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(20, after: heading)
        return stack
    }

    private func checkbox(_ title: String, state: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = state ? .on : .off
        return button
    }

    private func conflictExample(for strategy: ConflictStrategy) -> String {
        switch strategy {
        case .addNumber: return L("conflict.example_number")
        case .addTimestamp: return L("conflict.example_timestamp")
        case .cancelRename: return L("conflict.example_cancel")
        }
    }

    @objc private func toggleAuto(_ sender: NSButton) {
        Preferences.shared.autoRenameHighConfidence = sender.state == .on
    }

    @objc private func toggleExecutable(_ sender: NSButton) {
        Preferences.shared.alwaysConfirmExecutable = sender.state == .on
    }

    @objc private func toggleAmbiguous(_ sender: NSButton) {
        Preferences.shared.alwaysConfirmAmbiguous = sender.state == .on
    }

    @objc private func toggleShowConfidence(_ sender: NSButton) {
        Preferences.shared.showConfidence = sender.state == .on
    }

    @objc private func toggleShowExplanation(_ sender: NSButton) {
        Preferences.shared.showExplanation = sender.state == .on
    }

    @objc private func changeThreshold(_ sender: NSSlider) {
        let value = Int(sender.doubleValue.rounded())
        Preferences.shared.confirmationThreshold = value
        findSubview(in: contentHost, identifier: "thresholdValue", viewType: NSTextField.self)?.stringValue = "\(value)%"
    }

    @objc private func changeConflictStrategy(_ sender: NSPopUpButton) {
        let strategies: [ConflictStrategy] = [.addNumber, .addTimestamp, .cancelRename]
        guard strategies.indices.contains(sender.indexOfSelectedItem) else { return }
        let strategy = strategies[sender.indexOfSelectedItem]
        Preferences.shared.conflictStrategy = strategy
        conflictExampleLabel?.stringValue = conflictExample(for: strategy)
    }

    @objc private func changeMaximumLengthField(_ sender: NSTextField) {
        commitMaximumLength(sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === maximumLengthField else { return }
        commitMaximumLength(field)
    }

    private func commitMaximumLength(_ sender: NSTextField) {
        let value = min(255, max(1, sender.integerValue))
        Preferences.shared.maximumFilenameLength = value
        sender.stringValue = "\(value)"
        maximumLengthStepper?.integerValue = value
    }

    @objc private func changeMaximumLengthStepper(_ sender: NSStepper) {
        let value = min(255, max(1, sender.integerValue))
        Preferences.shared.maximumFilenameLength = value
        maximumLengthField?.stringValue = "\(value)"
    }

    @objc private func togglePreserveExtension(_ sender: NSButton) {
        Preferences.shared.preserveOriginalExtension = sender.state == .on
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        let languages: [AppLanguage] = [.system, .english, .simplifiedChinese]
        guard languages.indices.contains(sender.indexOfSelectedItem) else { return }
        Preferences.shared.language = languages[sender.indexOfSelectedItem]
        sidebarTable.reloadData()
        let selected = max(0, sidebarTable.selectedRow)
        showPane(selected)
        onLanguageChanged()
    }

    @objc private func changeAppearance(_ sender: NSPopUpButton) {
        let modes: [AppearanceMode] = [.system, .light, .dark]
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        Preferences.shared.appearance = modes[sender.indexOfSelectedItem]
        AppearanceManager.apply()
    }

    private func findSubview<T: NSView>(in view: NSView,
                                        identifier: String,
                                        viewType type: T.Type) -> T? {
        if let typed = view as? T, typed.identifier?.rawValue == identifier { return typed }
        for child in view.subviews {
            if let found: T = findSubview(in: child, identifier: identifier, viewType: type) { return found }
        }
        return nil
    }
}

// MARK: - Welcome window

final class WelcomeWindowController: NSWindowController {
    private let showSettings: () -> Void

    init(showSettings: @escaping () -> Void) {
        self.showSettings = showSettings
        super.init(window: frostedWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 255), title: "Auto Filename"))
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -36)
        ])

        let icon = NSImageView()
        icon.image = NSApplication.shared.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label("Auto Filename", font: .systemFont(ofSize: 20, weight: .bold)))
        stack.addArrangedSubview(label(L("welcome.description"), color: .secondaryLabelColor, wraps: true))
        stack.addArrangedSubview(label(L("welcome.shortcut_description"), color: .tertiaryLabelColor, wraps: true))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let settings = NSButton(title: L("welcome.open_settings"), target: self, action: #selector(openSettings))
        let shortcuts = NSButton(title: L("welcome.open_shortcuts"), target: self, action: #selector(openShortcuts))
        buttons.addArrangedSubview(settings)
        buttons.addArrangedSubview(shortcuts)
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[3])
        stack.addArrangedSubview(buttons)
        window?.center()
    }

    @objc private func openSettings() { showSettings() }
    @objc private func openShortcuts() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
    }
}

// MARK: - Application delegate + menu

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prepared: PreparedRename?
    private let manualLaunch: Bool
    private var confirmationController: ConfirmationWindowController?
    private var welcomeController: WelcomeWindowController?
    private var settingsController: SettingsWindowController?

    init(prepared: PreparedRename?, manualLaunch: Bool) {
        self.prepared = prepared
        self.manualLaunch = manualLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
    }

    func startInitialInterface() {
        if let prepared {
            confirmationController = ConfirmationWindowController(prepared: prepared) { [weak self] in
                self?.confirmationController = nil
                NSApp.terminate(nil)
            }

            if let window = confirmationController?.window {
                window.collectionBehavior.insert(.moveToActiveSpace)
                confirmationController?.showWindow(nil)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else if manualLaunch {
            welcomeController = WelcomeWindowController(showSettings: { [weak self] in self?.showSettings(nil) })
            if let window = welcomeController?.window {
                window.collectionBehavior.insert(.moveToActiveSpace)
                welcomeController?.showWindow(nil)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        manualLaunch
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: L("menu.about"), action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L("menu.settings"), action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsWindowController(onLanguageChanged: { [weak self] in
                self?.buildMainMenu()
            })
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutCredits()])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func aboutCredits() -> NSAttributedString {
        let website = URL(string: "https://jingyuan.is-a.dev")!
        let repository = URL(string: "https://github.com/jingyuan-zheng/AutoFilenameHelper")!
        let credits = NSMutableAttributedString(string: L("about.credits"), attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: centeredParagraphStyle()])
        let text = credits.string as NSString
        credits.addAttribute(.link, value: website, range: text.range(of: L("about.website")))
        credits.addAttribute(.link, value: repository, range: text.range(of: L("about.repository")))
        credits.addAttribute(.link, value: repository, range: text.range(of: L("about.license")))
        return credits
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }
}

// MARK: - Entry point

let inputData = FileHandle.standardInput.readDataToEndOfFile()
let input = String(data: inputData, encoding: .utf8) ?? ""

if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    guard let request = PayloadParser.parse(input),
          let initialPrepared = RenameEngine.prepare(request) else {
        exit(0)
    }

    if !RenameEngine.needsConfirmation(initialPrepared) {
        _ = RenameEngine.rename(initialPrepared, candidate: initialPrepared.request.suggested)
        exit(0)
    }

    // Serialize confirmation UIs across simultaneous Shortcut invocations. Waiting
    // processes do not initialize AppKit, so they do not create extra Dock icons/windows.
    let confirmationQueue = ConfirmationQueueLock()
    if let confirmationQueue {
        _ = confirmationQueue.waitForTurn()
    }

    // Re-check the file and current preferences after waiting for our turn.
    guard let prepared = RenameEngine.prepare(request) else { exit(0) }
    if !RenameEngine.needsConfirmation(prepared) {
        _ = RenameEngine.rename(prepared, candidate: prepared.request.suggested)
        exit(0)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    AppearanceManager.apply()
    let delegate = AppDelegate(prepared: prepared, manualLaunch: false)
    app.delegate = delegate
    app.finishLaunching()
    delegate.startInitialInterface()
    withExtendedLifetime(confirmationQueue) {
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    AppearanceManager.apply()
    let delegate = AppDelegate(prepared: nil, manualLaunch: true)
    app.delegate = delegate
    app.finishLaunching()
    delegate.startInitialInterface()
    withExtendedLifetime(delegate) {
        app.run()
    }
}
