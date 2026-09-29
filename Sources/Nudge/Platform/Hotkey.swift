import Carbon

@MainActor final class Hotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    private let identifier: UInt32
    init(identifier: UInt32 = 1) {
        self.identifier = identifier
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
                var pressed = EventHotKeyID()
                guard let event,
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &pressed) == noErr
                else { return OSStatus(eventNotHandledErr) }
                let matches = MainActor.assumeIsolated { pressed.id == hotkey.identifier && pressed.signature == 0x4e55_4447 }
                guard matches else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { hotkey.action?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
    }
    func register(key: UInt32, modifiers: UInt32) throws {
        var newReference: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4e55_4447, id: identifier)
        // Unregister first; on failure restore the existing configured shortcut at the controller level.
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        let status = RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &newReference)
        guard status == noErr else { throw NudgeError("That shortcut is already in use. Choose another combination.") }
        reference = newReference
    }
}
