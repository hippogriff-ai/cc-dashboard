// Vendored from sindresorhus/KeyboardShortcuts (MIT). See LICENSE-VENDORED.md.
// Source: Sources/KeyboardShortcuts/Utilities.swift
// Local modifications:
//   - Stripped the `bundle: .module` argument from `String.localized` because
//     the upstream `.module` Bundle only exists when the package is built via
//     SwiftPM. We vendor the source files into the app target directly, so
//     `.module` is unresolved here. Loop 32: extended `String.localized` with
//     a literal `[String: String]` dictionary mirroring the upstream
//     `Sources/KeyboardShortcuts/Localization/en.lproj/Localizable.strings`
//     so the Recorder UI renders human-readable English instead of the
//     untranslated key strings (e.g. "Record Shortcut" not "record_shortcut").
//     Unknown keys still fall through to `self`.
//   - Replaced both `isolated deinit` with plain `deinit` in
//     `LocalEventMonitor` and `RunLoopLocalEventMonitor`. Upstream uses
//     Swift 6.1's `IsolatedDeinit` experimental feature; cc-dashboard builds
//     in Swift 5 language mode without that flag.

import SwiftUI
import os

#if os(macOS)
import Carbon.HIToolbox


/// Drift detector for the literal English string table below. Upstream may
/// add new `.localized` call sites in a future re-sync — without observability
/// the missing keys would silently render as raw snake_case (e.g.
/// `"clear_shortcut"`) in the Recorder UI. Logging via `os.Logger` makes that
/// visible in Console.app the moment it happens.
private let keyboardShortcutsLocalizationLogger = Logger(
    subsystem: "dev.vcheval.cc-dashboard",
    category: "KeyboardShortcuts.Localization"
)

/// English string table mirroring upstream's
/// `Sources/KeyboardShortcuts/Localization/en.lproj/Localizable.strings`.
/// Keys absent here fall through to `self` (matching the upstream "missing
/// resource" behavior). Add new keys when vendoring additional Recorder code.
private let keyboardShortcutsEnStrings: [String: String] = [
    "record_shortcut": "Record Shortcut",
    "press_shortcut": "Press Shortcut",
    "keyboard_shortcut_used_by_menu_item": "This keyboard shortcut cannot be used as it’s already used by the “%@” menu item.",
    "keyboard_shortcut_used_by_system": "This keyboard shortcut cannot be used as it’s already a system-wide keyboard shortcut.",
    "keyboard_shortcuts_can_be_changed": "Most system-wide keyboard shortcuts can be changed in “System Settings › Keyboard › Keyboard Shortcuts”.",
    "keyboard_shortcut_disallowed": "Option modifier must be combined with Command or Control.",
    "clear_shortcut": "Clear Shortcut",
    "force_use_shortcut": "Use Anyway",
    "ok": "OK",
    "space_key": "Space"
]

extension String {
	/**
	Makes the string localizable.

	VENDORED MODIFICATION: the upstream version used `bundle: .module` which
	is only resolved when this code is built as a SwiftPM target. cc-dashboard
	inlines the sources into the app target, so `.module` is undefined here.
	We resolve via the literal English string table above; unknown keys fall
	through to `self`, matching upstream's missing-resource behavior.
	*/
	var localized: String {
		if let v = keyboardShortcutsEnStrings[self] { return v }
		// Vendor-drift defense: a future re-sync of Recorder.swift /
		// RecorderCocoa.swift / ViewModifiers.swift could introduce a new
		// `.localized` call site whose key isn't in the dictionary above.
		// We preserve the upstream contract (return the key as fallback) so
		// the UI doesn't crash, but log the miss so the gap shows up in
		// Console.app instead of silently rendering raw snake_case to users.
		keyboardShortcutsLocalizationLogger.error("missing localization key: \(self, privacy: .public)")
		return self
	}
}


extension Data {
	nonisolated var toString: String? { String(data: self, encoding: .utf8) }
}


extension NSEvent {
	nonisolated var isKeyEvent: Bool { type == .keyDown || type == .keyUp }
}


extension NSTextField {
	func hideCaret() {
		(currentEditor() as? NSTextView)?.insertionPointColor = .clear
	}

	func restoreCaret() {
		(currentEditor() as? NSTextView)?.insertionPointColor = .labelColor
	}
}


extension NSView {
	func focus() {
		window?.makeFirstResponder(self)
	}

	func blur() {
		window?.makeFirstResponder(nil)
	}
}


/**
Listen to local events.

- Important: Don't forget to call `.start()`.

```swift
eventMonitor = LocalEventMonitor(events: [.leftMouseDown, .rightMouseDown]) { event in
	// Do something

	return event
}
.start()
```
*/
final class LocalEventMonitor {
	private let events: NSEvent.EventTypeMask
	private let callback: (NSEvent) -> NSEvent?
	private weak var monitor: AnyObject?

	init(events: NSEvent.EventTypeMask, callback: @escaping (NSEvent) -> NSEvent?) {
		self.events = events
		self.callback = callback
	}

	deinit {
		// VENDORED MODIFICATION: dropped `isolated` keyword — see header note.
		stop()
	}

	@discardableResult
	func start() -> Self {
		monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: callback) as AnyObject
		return self
	}

	func stop() {
		guard let monitor else {
			return
		}

		NSEvent.removeMonitor(monitor)
	}
}


final class RunLoopLocalEventMonitor {
	private let runLoopMode: RunLoop.Mode
	private let callback: (NSEvent) -> NSEvent?
	private let observer: CFRunLoopObserver

	init(
		events: NSEvent.EventTypeMask,
		runLoopMode: RunLoop.Mode,
		callback: @escaping (NSEvent) -> NSEvent?
	) {
		self.runLoopMode = runLoopMode
		self.callback = callback

		self.observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeSources.rawValue, true, 0) { _, _ in
			// Pull all events from the queue and handle the ones matching the given types.
			// Non-matching events are left untouched, maintaining their order in the queue.

			var eventsToHandle = [NSEvent]()

			// Retrieve all events from the event queue to preserve their order (instead of using the `matching` parameter).
			while let eventToHandle = NSApp.nextEvent(matching: .any, until: nil, inMode: runLoopMode, dequeue: true) {
				eventsToHandle.append(eventToHandle)
			}

			// Iterate over the gathered events, instead of doing it directly in the `while` loop, to avoid potential infinite loops caused by re-retrieving undiscarded events.
			for eventToHandle in eventsToHandle {
				var handledEvent: NSEvent?

				if !events.contains(NSEvent.EventTypeMask(rawValue: 1 << eventToHandle.type.rawValue)) {
					handledEvent = eventToHandle
				} else if let callbackEvent = callback(eventToHandle) {
					handledEvent = callbackEvent
				}

				guard let handledEvent else {
					continue
				}

				NSApp.postEvent(handledEvent, atStart: false)
			}
		}
	}

	deinit {
		// VENDORED MODIFICATION: dropped `isolated` keyword — see header note.
		stop()
	}

	@discardableResult
	func start() -> Self {
		CFRunLoopAddObserver(RunLoop.current.getCFRunLoop(), observer, CFRunLoopMode(runLoopMode.rawValue as CFString))
		return self
	}

	func stop() {
		CFRunLoopRemoveObserver(RunLoop.current.getCFRunLoop(), observer, CFRunLoopMode(runLoopMode.rawValue as CFString))
	}
}


extension NSEvent {
	private static func normalizedModifiers(from flags: ModifierFlags) -> ModifierFlags {
		flags
			.intersection(.deviceIndependentFlagsMask)
			// We remove `capsLock` as it shouldn't affect the modifiers.
			// We remove `numericPad` as arrow keys trigger it, use `event.specialKeys` instead.
			.subtracting([.capsLock, .numericPad])
	}

	static var modifiers: ModifierFlags {
		normalizedModifiers(from: modifierFlags)
	}

	/**
	Real modifiers.

	- Note: Prefer this over `.modifierFlags`.

	```swift
	// Check if Command is one of possible more modifiers keys
	event.modifiers.contains(.command)

	// Check if Command is the only modifier key
	event.modifiers == .command

	// Check if Command and Shift are the only modifiers
	event.modifiers == [.command, .shift]
	```
	*/
	var modifiers: ModifierFlags {
		Self.normalizedModifiers(from: modifierFlags)
	}
}


extension NSSearchField {
	/**
	Clear the search field.
	*/
	func clear() {
		(cell as? NSSearchFieldCell)?.cancelButtonCell?.performClick(self)
	}
}


extension NSAlert {
	/**
	Show an alert as a window-modal sheet, or as an app-modal (window-independent) alert if the window is `nil` or not given.
	*/
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		title: String,
		message: String? = nil,
		style: Style = .warning,
		icon: NSImage? = nil,
		buttonTitles: [String] = []
	) -> NSApplication.ModalResponse {
		NSAlert(
			title: title,
			message: message,
			style: style,
			icon: icon,
			buttonTitles: buttonTitles
		).runModal(for: window)
	}

	convenience init(
		title: String,
		message: String? = nil,
		style: Style = .warning,
		icon: NSImage? = nil,
		buttonTitles: [String] = []
	) {
		self.init()
		self.messageText = title
		self.alertStyle = style
		self.icon = icon

		for buttonTitle in buttonTitles {
			addButton(withTitle: buttonTitle)
		}

		if let message {
			self.informativeText = message
		}
	}

	/**
	Runs the alert as a window-modal sheet, or as an app-modal (window-independent) alert if the window is `nil` or not given.
	*/
	@discardableResult
	func runModal(for window: NSWindow? = nil) -> NSApplication.ModalResponse {
		guard let window else {
			return runModal()
		}

		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}

		return NSApp.runModal(for: window)
	}
}


enum UnicodeSymbols {
	/**
	Represents the Function (Fn) key on the keyboard.
	*/
	nonisolated static let functionKey = "🌐\u{FE0E}"
}


extension NSEvent.ModifierFlags {
	// Not documented anywhere, but reverse-engineered by me.
	nonisolated private static let functionKey = 1 << 17 // 131072 (0x20000)

	nonisolated var carbon: Int {
		var modifierFlags = 0

		if contains(.control) {
			modifierFlags |= controlKey
		}

		if contains(.option) {
			modifierFlags |= optionKey
		}

		if contains(.shift) {
			modifierFlags |= shiftKey
		}

		if contains(.command) {
			modifierFlags |= cmdKey
		}

		if contains(.function) {
			modifierFlags |= Self.functionKey
		}

		return modifierFlags
	}

	nonisolated init(carbon: Int) {
		self.init()

		if carbon & controlKey == controlKey {
			insert(.control)
		}

		if carbon & optionKey == optionKey {
			insert(.option)
		}

		if carbon & shiftKey == shiftKey {
			insert(.shift)
		}

		if carbon & cmdKey == cmdKey {
			insert(.command)
		}

		if carbon & Self.functionKey == Self.functionKey {
			insert(.function)
		}
	}
}

extension SwiftUI.EventModifiers {
	// `.function` is deprecated, so we use the raw value.
	nonisolated fileprivate static let function_nonDeprecated = Self(rawValue: 64)
}

extension NSEvent.ModifierFlags {
	nonisolated var toEventModifiers: SwiftUI.EventModifiers {
		var modifiers = SwiftUI.EventModifiers()

		if contains(.capsLock) {
			modifiers.insert(.capsLock)
		}

		if contains(.command) {
			modifiers.insert(.command)
		}

		if contains(.control) {
			modifiers.insert(.control)
		}

		if contains(.numericPad) {
			modifiers.insert(.numericPad)
		}

		if contains(.option) {
			modifiers.insert(.option)
		}

		if contains(.shift) {
			modifiers.insert(.shift)
		}

		if contains(.function) {
			modifiers.insert(.function_nonDeprecated)
		}

		return modifiers
	}
}

extension NSEvent.ModifierFlags {
	/**
	The string representation of the modifier flags.

	```swift
	print(NSEvent.ModifierFlags([.command, .shift]).presentableDescription)
	//=> "⇧⌘"
	```
	*/
	@available(*, deprecated, renamed: "ks_symbolicRepresentation")
	var presentableDescription: String {
		ks_symbolicRepresentation
	}
}


extension NSEvent.ModifierFlags {
	/**
	The symbolic representation of the modifier flags.

	```swift
	let modifiers = NSEvent.ModifierFlags([.command, .shift])
	print(modifiers.ks_symbolicRepresentation)
	//=> "⇧⌘"
	```
	*/
	nonisolated public var ks_symbolicRepresentation: String {
		var description = ""

		if contains(.control) {
			description += "⌃"
		}

		if contains(.option) {
			description += "⌥"
		}

		if contains(.shift) {
			description += "⇧"
		}

		if contains(.command) {
			description += "⌘"
		}

		if contains(.function) {
			description += UnicodeSymbols.functionKey
		}

		return description
	}
}


extension NSEvent.SpecialKey {
	nonisolated(unsafe) static let functionKeys: Set<Self> = [
		.f1,
		.f2,
		.f3,
		.f4,
		.f5,
		.f6,
		.f7,
		.f8,
		.f9,
		.f10,
		.f11,
		.f12,
		.f13,
		.f14,
		.f15,
		.f16,
		.f17,
		.f18,
		.f19,
		.f20,
		.f21,
		.f22,
		.f23,
		.f24,
		.f25,
		.f26,
		.f27,
		.f28,
		.f29,
		.f30,
		.f31,
		.f32,
		.f33,
		.f34,
		.f35
	]

	nonisolated var isFunctionKey: Bool { Self.functionKeys.contains(self) }
}


enum AssociationPolicy {
	case assign
	case retainNonatomic
	case copyNonatomic
	case retain
	case copy

	var rawValue: objc_AssociationPolicy {
		switch self {
		case .assign:
			.OBJC_ASSOCIATION_ASSIGN
		case .retainNonatomic:
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		case .copyNonatomic:
			.OBJC_ASSOCIATION_COPY_NONATOMIC
		case .retain:
			.OBJC_ASSOCIATION_RETAIN
		case .copy:
			.OBJC_ASSOCIATION_COPY
		}
	}
}

final class ObjectAssociation<T> {
	private let policy: AssociationPolicy

	init(policy: AssociationPolicy = .retainNonatomic) {
		self.policy = policy
	}

	subscript(index: AnyObject) -> T? {
		get {
			// Force-cast is fine here as we want it to fail loudly if we don't use the correct type.
			// swiftlint:disable:next force_cast
			objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as! T?
		}
		set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, policy.rawValue)
		}
	}
}


extension HorizontalAlignment {
	private enum ControlAlignment: AlignmentID {
		nonisolated static func defaultValue(in context: ViewDimensions) -> CGFloat { // swiftlint:disable:this no_cgfloat
			context[HorizontalAlignment.center]
		}
	}

	nonisolated fileprivate static let controlAlignment = Self(ControlAlignment.self)
}

extension View {
	func formLabel(@ViewBuilder _ label: () -> some View) -> some View {
		HStack(alignment: .firstTextBaseline) {
			label()
			labelsHidden()
				.alignmentGuide(.controlAlignment) { $0[.leading] }
		}
		.alignmentGuide(.leading) { $0[.controlAlignment] }
	}
}


#if DEBUG
/**
Get SwiftUI dynamic shared object.

Reference: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html
*/
@usableFromInline
nonisolated(unsafe) let dynamicSharedObject: UnsafeMutableRawPointer = {
	let imageCount = _dyld_image_count()
	for imageIndex in 0..<imageCount {
		guard
			let name = _dyld_get_image_name(imageIndex),
			// Use `/SwiftUI` instead of `SwiftUI` to prevent any library named `XXSwiftUI`.
			String(cString: name).hasSuffix("/SwiftUI"),
			let header = _dyld_get_image_header(imageIndex)
		else {
			continue
		}

		return UnsafeMutableRawPointer(mutating: header)
	}

	return UnsafeMutableRawPointer(mutating: #dsohandle)
}()
#endif

@_transparent
@usableFromInline
nonisolated func runtimeWarn(
	_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String
) {
#if DEBUG
#if canImport(OSLog)
	let condition = condition()
	if !condition {
		os_log(
			.fault,
			// A token that identifies the containing executable or dylib image.
			dso: dynamicSharedObject,
			log: OSLog(subsystem: "com.apple.runtime-issues", category: "KeyboardShortcuts"),
			"%@",
			message()
		)
	}
#else
	assert(condition(), message())
#endif
#endif
}

extension KeyboardShortcuts {
	nonisolated static func isValidShortcutName(_ name: String) -> Bool {
		!name.contains(".")
	}
}
#endif


@available(iOS 14.0, *)
@available(macOS 11.0, *)
extension KeyEquivalent {
	init?(unicodeScalarValue value: Int) {
		guard let character = Character(unicodeScalarValue: value) else {
			return nil
		}

		self = KeyEquivalent(character)
	}
}


extension Sequence where Element: Hashable {
	/**
	Convert a `Sequence` with `Hashable` elements to a `Set`.
	*/
	func toSet() -> Set<Element> { Set(self) }
}



extension StringProtocol {
	func replacingPrefix(_ prefix: String, with replacement: String) -> String {
		guard hasPrefix(prefix) else {
			return String(self)
		}

		return replacement + dropFirst(prefix.count)
	}
}

extension Character {
	init?(unicodeScalarValue value: Int) {
		guard let content = UnicodeScalar(value) else {
			return nil
		}

		self = Character(content)
	}
}

enum NotificationUserInfoKey {
	nonisolated static let name = "name"
	nonisolated static let isActive = "isActive"
}

extension Notification {
	nonisolated var keyboardShortcutsName: KeyboardShortcuts.Name? {
		userInfo?[NotificationUserInfoKey.name] as? KeyboardShortcuts.Name
	}

	nonisolated var recorderIsActive: Bool {
		(userInfo?[NotificationUserInfoKey.isActive] as? Bool) ?? false
	}
}
