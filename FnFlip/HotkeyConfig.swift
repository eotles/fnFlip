import AppKit
import Carbon.HIToolbox

enum HotkeyConfig {
    // MARK: Public settings
    static let keyEquivalent = "f"
    static let cocoaModifiers: NSEvent.ModifierFlags = [.command, .option]
    static let carbonKeyCode: UInt32 = UInt32(kVK_ANSI_F)
    static let carbonModifiers: UInt32 = UInt32(cmdKey | optionKey)

    // Pretty string for tooltips or copy
    static var displayString: String { "⌘⌥F" }

    // MARK: Registration
    private static var hotKeyRef: EventHotKeyRef?
    private static var eventHandlerRef: EventHandlerRef?
    private static var action: (() -> Void)?
    private static var userDataPtr: UnsafeMutableRawPointer?

    /// Register the global hotkey and call `action` when it fires.
    static func register(action: @escaping () -> Void) {
        unregister()  // in case it was registered already
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
            box.closure()
            return noErr
        }

        // Box the closure for Carbon callback
        let box = CallbackBox { HotkeyConfig.action?() }
        userDataPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())

        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, userDataPtr, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x464E544F), id: 1) // "FNTO"
        RegisterEventHotKey(carbonKeyCode, carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    static func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let ptr = userDataPtr {
            // balance passRetained in register(action:)
            Unmanaged<CallbackBox>.fromOpaque(ptr).release()
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        userDataPtr = nil
        action = nil
    }

    // MARK: UI helpers
    /// Apply the configured key equivalent to a menu item so the hint shows on the right.
    static func applyShortcut(to item: NSMenuItem) {
        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = cocoaModifiers
    }
}

// Private box to carry a Swift closure through Carbon APIs
private final class CallbackBox {
    let closure: () -> Void
    init(closure: @escaping () -> Void) { self.closure = closure }
}
