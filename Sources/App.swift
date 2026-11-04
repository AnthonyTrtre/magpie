import AppKit
import SocleBarreDeMenus
import SocleCore
import Sparkle
import SwiftUI

@main
struct MagpieApp: App {
    @NSApplicationDelegateAdaptor private var delegue: Delegue

    var body: some Scene {
        Settings { EmptyView() }  // tout se règle depuis le menu de l'icône
    }
}

/// Mises à jour intégrées (Sparkle) : archives signées EdDSA, vérifiées avant installation.
@MainActor let miseAJour = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

@MainActor
final class Delegue: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var controleur = ControleurMagpie()
    private var panneau: Panneau?
    private var raccourci: RaccourciGlobal?
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pendant les tests l'app sert d'hôte : ne pas toucher au vrai presse-papiers ni au vrai historique.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let panneau = Panneau(controleur: controleur)
        self.panneau = panneau
        raccourci = RaccourciGlobal { panneau.basculer() }
        if raccourci == nil { Journal.app.error("Raccourci ⌃⌘V déjà pris par une autre app") }
        item.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Magpie")
        menu.delegate = self
        item.menu = menu
        controleur.demarrer()
        OuvertureALaConnexion.activerAuPremierLancement()
        miseAJour.startUpdater()
        Journal.app.info("Magpie démarré, \(self.controleur.historique.elements.count) éléments")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let c = controleur
        menu.addItem(ItemAction("Ouvrir l'historique   ⌃⌘V") { [weak self] in self?.panneau?.afficher() })
        if NSPasteboard.general.accessBehavior == .alwaysDeny {
            let alerte = NSMenuItem(title: "⚠︎ Accès au presse-papiers refusé : Réglages Système › Confidentialité",
                                    action: nil, keyEquivalent: "")
            alerte.isEnabled = false
            menu.addItem(alerte)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Derniers éléments (clic = copier)"))
        for element in c.historique.elements.prefix(8) {
            menu.addItem(ItemAction(String(element.resume.prefix(50))) { c.choisir(element, coller: false) })
        }
        if c.historique.elements.isEmpty {
            let vide = NSMenuItem(title: "Rien pour l'instant", action: nil, keyEquivalent: "")
            vide.isEnabled = false
            menu.addItem(vide)
        }
        menu.addItem(.separator())
        menu.addItem(ItemAction("Mettre en pause", coche: c.enPause) { c.enPause.toggle() })
        menu.addItem(sousMenu("Garder", valeurs: [100, 500, 1000, 2000], actuelle: c.maximum,
                              libelle: { "\($0) éléments" }) { c.maximum = $0 })
        menu.addItem(sousMenu("Pendant", valeurs: [1, 7, 30, 90, 0], actuelle: c.ageMaxJours,
                              libelle: { $0 == 0 ? "Sans limite" : "\($0) jour\($0 > 1 ? "s" : "")" }) { c.ageMaxJours = $0 })
        menu.addItem(ItemAction(Collage.autorise ? "Collage automatique : autorisé" : "Autoriser le collage automatique…",
                                coche: Collage.autorise) { Collage.demanderAutorisation() })
        menu.addItem(ItemAction("Vider l'historique…") { [weak self] in self?.confirmerVidage() })
        menu.addItem(ItemAction("Ouvrir à la connexion", coche: OuvertureALaConnexion.active) { OuvertureALaConnexion.basculer() })
        menu.addItem(.separator())
        menu.addItem(ItemAction("Rechercher des mises à jour…") { NSApp.activate(); miseAJour.checkForUpdates(nil) })
        menu.addItem(ItemAction("À propos de Magpie") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(ItemAction("Quitter Magpie", touche: "q") { NSApp.terminate(nil) })
    }

    private func sousMenu(_ titre: String, valeurs: [Int], actuelle: Int, libelle: (Int) -> String,
                          choisir: @escaping @MainActor (Int) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: titre, action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        for v in valeurs {
            item.submenu?.addItem(ItemAction(libelle(v), coche: v == actuelle) { choisir(v) })
        }
        return item
    }

    private func confirmerVidage() {
        let alerte = NSAlert()
        alerte.messageText = "Vider tout l'historique ?"
        alerte.informativeText = "Les \(controleur.historique.elements.count) éléments seront effacés définitivement."
        alerte.addButton(withTitle: "Vider")
        alerte.addButton(withTitle: "Annuler")
        NSApp.activate()
        if alerte.runModal() == .alertFirstButtonReturn { controleur.vider() }
    }
}
