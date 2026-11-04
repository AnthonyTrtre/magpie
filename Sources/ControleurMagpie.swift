import AppKit
import Observation
import SocleCore

/// Cœur de l'app : capture des copies, historique, réglages, collage.
@MainActor @Observable
final class ControleurMagpie {
    private(set) var historique: Historique
    let stockage: Stockage
    @ObservationIgnored private let reglages: UserDefaults
    @ObservationIgnored private var surveillant: Surveillant?

    /// Apps dont on ne garde jamais les copies (gestionnaires de mots de passe).
    static let appsIgnorees: Set<String> = [
        "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
    ]

    init(stockage: Stockage = .standard, reglages: UserDefaults = .standard) {
        self.stockage = stockage
        self.reglages = reglages
        historique = stockage.charger()
        appliquerPurge()
    }

    /// Démarre la surveillance du presse-papiers général (pas pendant les tests).
    func demarrer() {
        surveillant = Surveillant { [weak self] pb in self?.capturer(pb) }
    }

    // MARK: Réglages

    var enPause: Bool {
        get { access(keyPath: \.enPause); return reglages.bool(forKey: "enPause") }
        set { withMutation(keyPath: \.enPause) { reglages.set(newValue, forKey: "enPause") } }
    }

    var maximum: Int {
        get { access(keyPath: \.maximum); return reglages.object(forKey: "maximum") as? Int ?? 500 }
        set { withMutation(keyPath: \.maximum) { reglages.set(newValue, forKey: "maximum") }; appliquerPurge() }
    }

    /// Âge maximum en jours, 0 = sans limite.
    var ageMaxJours: Int {
        get { access(keyPath: \.ageMaxJours); return reglages.object(forKey: "ageMaxJours") as? Int ?? 30 }
        set { withMutation(keyPath: \.ageMaxJours) { reglages.set(newValue, forKey: "ageMaxJours") }; appliquerPurge() }
    }

    // MARK: Capture

    func capturer(_ pb: NSPasteboard, appActive: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard !enPause, !Self.appsIgnorees.contains(appActive?.bundleIdentifier ?? ""),
              let lecture = Lecteur.lire(pb) else { return }
        ajouter(lecture, source: appActive?.localizedName)
    }

    func ajouter(_ lecture: Lecture, source: String?, date: Date = .now) {
        let contenu: Contenu
        switch lecture {
        case .contenu(let c):
            contenu = c
        case .image(let png, let l, let h, let empreinte):
            if let existant = historique.elements.first(where: { $0.cle == "i:" + empreinte }) {
                contenu = existant.contenu  // déjà sur disque : pas de second fichier
            } else {
                do {
                    contenu = .image(fichier: try stockage.ecrireImage(png), largeur: l, hauteur: h, empreinte: empreinte)
                } catch {
                    return Journal.app.error("Image non enregistrée : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        stockage.nettoyer(historique.ajouter(Element(date: date, contenu: contenu, appSource: source)))
        appliquerPurge()
    }

    // MARK: Actions

    /// Remet l'élément dans le presse-papiers, en tête de l'historique, et le colle dans l'app active si autorisé.
    func choisir(_ element: Element, coller: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch element.contenu {
        case .texte(let t): pb.setString(t, forType: .string)
        case .lien(let u): pb.writeObjects([u as NSURL]); pb.setString(u.absoluteString, forType: .string)
        case .fichiers(let f): pb.writeObjects(f.map { $0 as NSURL })
        case .image(let nom, _, _, _):
            if let image = NSImage(contentsOf: stockage.urlImage(nom)) { pb.writeObjects([image]) }
        }
        surveillant?.ignorerChangementActuel()
        historique.ajouter(Element(id: element.id, date: .now, contenu: element.contenu, appSource: element.appSource))
        enregistrer()
        guard coller, Collage.autorise else { return }
        // Le panneau se ferme d'abord, pour que ⌘V arrive dans l'app qui était devant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Collage.collerDansAppActive() }
    }

    func supprimer(_ element: Element) {
        if let retire = historique.supprimer(element.id) { stockage.nettoyer([retire]) }
        enregistrer()
    }

    func vider() {
        stockage.nettoyer(historique.vider())
        enregistrer()
    }

    private func appliquerPurge() {
        stockage.nettoyer(historique.purger(maximum: maximum, ageMaxJours: ageMaxJours))
        enregistrer()
    }

    private func enregistrer() {
        do {
            try stockage.enregistrer(historique)
        } catch {
            Journal.app.error("Historique non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }
}
