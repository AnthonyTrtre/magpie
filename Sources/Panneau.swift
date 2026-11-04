import AppKit
import SwiftUI

/// Panneau flottant qui prend le clavier sans activer Magpie : l'app d'où l'on vient reste devant
/// et reçoit le collage.
private final class PanneauFlottant: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class Panneau: NSObject, NSWindowDelegate {
    private let panneau: PanneauFlottant
    private let controleur: ControleurMagpie
    private let etat = EtatListe()

    init(controleur: ControleurMagpie) {
        self.controleur = controleur
        panneau = PanneauFlottant(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                                  styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                  backing: .buffered, defer: true)
        super.init()
        panneau.titleVisibility = .hidden
        panneau.titlebarAppearsTransparent = true
        panneau.isMovableByWindowBackground = true
        panneau.level = .floating
        panneau.hidesOnDeactivate = false
        panneau.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panneau.delegate = self
        panneau.contentView = NSHostingView(rootView: VueListe(controleur: controleur, etat: etat) { [weak self] e, coller in
            self?.fermer()
            if let e { controleur.choisir(e, coller: coller) }
        })
    }

    func basculer() { panneau.isVisible ? fermer() : afficher() }

    func afficher() {
        etat.recherche = ""
        etat.selection = 0
        let ecran = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let zone = ecran?.visibleFrame {
            panneau.setFrameOrigin(NSPoint(x: zone.midX - panneau.frame.width / 2,
                                           y: zone.midY - panneau.frame.height / 2 + zone.height / 8))
        }
        panneau.makeKeyAndOrderFront(nil)
    }

    func fermer() { panneau.orderOut(nil) }

    func windowDidResignKey(_ notification: Notification) { fermer() }
}

@MainActor @Observable
final class EtatListe {
    var recherche = ""
    var selection = 0
}

private struct VueListe: View {
    let controleur: ControleurMagpie
    @Bindable var etat: EtatListe
    /// `nil` = fermer sans rien faire ; sinon l'élément choisi et s'il faut le coller.
    let terminer: (Element?, Bool) -> Void
    @FocusState private var focus: Bool

    private var resultats: [Element] { controleur.historique.rechercher(etat.recherche) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Rechercher dans l'historique", text: $etat.recherche)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused($focus)
                .onChange(of: etat.recherche) { etat.selection = 0 }
            Divider()
            if resultats.isEmpty {
                ContentUnavailableView(controleur.historique.elements.isEmpty ? "Rien de copié pour l'instant" : "Aucun résultat",
                                       systemImage: "list.clipboard")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { defilement in
                    List(Array(resultats.prefix(200).enumerated()), id: \.element.id) { rang, element in
                        Ligne(element: element, rang: rang, choisie: rang == etat.selection, stockage: controleur.stockage)
                            .id(rang)
                            .contentShape(Rectangle())
                            .onTapGesture { terminer(element, true) }
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .onChange(of: etat.selection) { defilement.scrollTo(etat.selection) }
                }
            }
            Divider()
            piedDePage
        }
        .frame(width: 560, height: 460)
        .onAppear { focus = true }
        .onKeyPress(.downArrow) { deplacer(1) }
        .onKeyPress(.upArrow) { deplacer(-1) }
        .onKeyPress(.escape) { terminer(nil, false); return .handled }
        .onKeyPress(.return, phases: .down) { touche in
            guard let e = resultats[safe: etat.selection] else { return .ignored }
            terminer(e, !touche.modifiers.contains(.option))  // ⌥↩ : copier sans coller
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { touche in
            guard touche.modifiers.contains(.command), let n = Int(touche.characters), n >= 1,
                  let e = resultats[safe: n - 1] else { return .ignored }
            terminer(e, true)
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { touche in
            guard touche.modifiers.contains(.command), let e = resultats[safe: etat.selection] else { return .ignored }
            controleur.supprimer(e)
            return .handled
        }
    }

    private var piedDePage: some View {
        HStack {
            Text("↩ coller · ⌥↩ copier · ⌘1–9 · ⌘⌫ supprimer · échap")
            Spacer()
            if !Collage.autorise {
                Button("Autoriser le collage automatique") { Collage.demanderAutorisation() }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func deplacer(_ pas: Int) -> KeyPress.Result {
        etat.selection = min(max(etat.selection + pas, 0), max(resultats.count - 1, 0))
        return .handled
    }
}

private struct Ligne: View {
    let element: Element
    let rang: Int
    let choisie: Bool
    let stockage: Stockage

    var body: some View {
        HStack(spacing: 10) {
            apercu.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(element.resume).lineLimit(2)
                Text([element.appSource, element.date.formatted(.relative(presentation: .named))]
                    .compactMap(\.self).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if rang < 9 {
                Text("⌘\(rang + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(choisie ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var apercu: some View {
        switch element.contenu {
        case .image(let nom, _, _, _):
            if let image = NSImage(contentsOf: stockage.urlImage(nom)) {
                Image(nsImage: image).resizable().scaledToFill().clipShape(.rect(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
            }
        case .lien: Image(systemName: "link").foregroundStyle(.blue)
        case .fichiers: Image(systemName: "doc")
        case .texte: Image(systemName: "text.alignleft").foregroundStyle(.secondary)
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
