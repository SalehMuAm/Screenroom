import AppKit
import Carbon

/// A held shortcut must not become a second action when the keyboard repeats.
struct HotKeyPressState {
    private var pressedKeys: Set<UInt32> = []

    mutating func shouldActivate(keyID: UInt32, eventKind: UInt32) -> Bool {
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            return pressedKeys.insert(keyID).inserted
        case UInt32(kEventHotKeyReleased):
            pressedKeys.remove(keyID)
            return false
        default:
            return false
        }
    }
}

/// Carbon hot keys work without Accessibility or Input Monitoring access.
@MainActor
final class HotKeyManager {
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var pressState = HotKeyPressState()
    private let onScreenshot: () -> Void
    private let onRecording: () -> Void
    var allRegistered: Bool { handler != nil && hotKeys.count == 2 }

    init(onScreenshot: @escaping () -> Void, onRecording: @escaping () -> Void) {
        self.onScreenshot = onScreenshot
        self.onRecording = onRecording
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr else { return status }
            guard key.signature == 0x53524F4D else { return OSStatus(eventNotHandledErr) }
            guard key.id == 1 || key.id == 2 else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard manager.pressState.shouldActivate(keyID: key.id, eventKind: GetEventKind(event)) else { return }
                if key.id == 1 { manager.onScreenshot() }
                if key.id == 2 { manager.onRecording() }
            }
            return noErr
        }, events.count, &events, context, &handler)
        guard status == noErr else { return }
        register(key: UInt32(kVK_ANSI_6), id: 1)
        register(key: UInt32(kVK_ANSI_7), id: 2)
    }

    private func register(key: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x53524F4D, id: id)
        let status = RegisterEventHotKey(key, UInt32(cmdKey | shiftKey), identifier,
                                        GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { hotKeys.append(reference) }
    }

    deinit {
        for key in hotKeys { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}
