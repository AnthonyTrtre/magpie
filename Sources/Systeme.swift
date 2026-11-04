import AppKit
import Carbon.HIToolbox

/// Surveille le presse-papiers général en comparant `changeCount` toutes les demi-secondes
/// (macOS ne fournit pas de notification de changement).
@MainActor
final class Surveillant {
    private var dernier = NSPasteboard.general.changeCount
    private var minuteur: Timer?
    private let surChangement: @MainActor (NSPasteboard) -> Void

    init(surChangement: @escaping @MainActor (NSPasteboard) -> Void) {
        self.surChangement = surChangement
        minuteur = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifier() }
        }
        minuteur?.tolerance = 0.2
    }

    /// À appeler après une écriture de Magpie lui-même, pour ne pas la reprendre comme une nouvelle copie.
    func ignorerChangementActuel() { dernier = NSPasteboard.general.changeCount }

    private func verifier() {
        let pb = NSPasteboard.general
        guard pb.changeCount != dernier else { return }
        dernier = pb.changeCount
        surChangement(pb)
    }
}

/// Raccourci clavier global par l'API Carbon : ne demande aucune autorisation.
@MainActor
final class RaccourciGlobal {
    private var ref: EventHotKeyRef?
    private var gestionnaire: EventHandlerRef?
    fileprivate let action: @MainActor () -> Void

    /// Par défaut ⌃⌘V.
    init?(touche: Int = kVK_ANSI_V, modificateurs: Int = controlKey | cmdKey, action: @escaping @MainActor () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let moi = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, donnees in
            guard let donnees else { return noErr }
            let raccourci = Unmanaged<RaccourciGlobal>.fromOpaque(donnees).takeUnretainedValue()
            MainActor.assumeIsolated { raccourci.action() }
            return noErr
        }, 1, &type, moi, &gestionnaire)
        let id = EventHotKeyID(signature: OSType(0x4346_5254), id: 1)  // « CFRT »
        guard RegisterEventHotKey(UInt32(touche), UInt32(modificateurs), id, GetApplicationEventTarget(), 0, &ref) == noErr
        else { return nil }
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let gestionnaire { RemoveEventHandler(gestionnaire) }
    }
}

/// Collage dans l'app active : on simule ⌘V. Demande l'autorisation « Accessibilité » (envoi d'événements).
@MainActor
enum Collage {
    static var autorise: Bool { CGPreflightPostEventAccess() }

    static func demanderAutorisation() { _ = CGRequestPostEventAccess() }

    static func collerDansAppActive() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for appui in [true, false] {
            let evenement = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: appui)
            evenement?.flags = .maskCommand
            evenement?.post(tap: .cghidEventTap)
        }
    }
}
