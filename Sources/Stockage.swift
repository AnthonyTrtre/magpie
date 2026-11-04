import Foundation
import SocleCore

/// Historique dans `~/Library/Application Support/fr.anthony.magpie/` : un JSON lisible seulement par son propriétaire
/// et un dossier d'images PNG. Rien ne sort du Mac.
struct Stockage: Sendable {
    let dossier: URL

    static let standard: Stockage = {
        let dossier = URL.applicationSupportDirectory.appending(path: "fr.anthony.magpie")
        // L'app s'appelait Coffret : on reprend son historique au premier lancement.
        let ancien = URL.applicationSupportDirectory.appending(path: "fr.anthony.coffret")
        if !FileManager.default.fileExists(atPath: dossier.path), FileManager.default.fileExists(atPath: ancien.path) {
            try? FileManager.default.moveItem(at: ancien, to: dossier)
        }
        return Stockage(dossier: dossier)
    }()

    var fichierHistorique: URL { dossier.appending(path: "historique.json") }
    var dossierImages: URL { dossier.appending(path: "images") }

    func urlImage(_ nom: String) -> URL { dossierImages.appending(path: nom) }

    func charger() -> Historique {
        guard let donnees = try? Data(contentsOf: fichierHistorique) else { return Historique() }
        do {
            return try JSONDecoder().decode(Historique.self, from: donnees)
        } catch {
            Journal.app.error("Historique illisible, on repart de zéro : \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.moveItem(at: fichierHistorique, to: dossier.appending(path: "historique-illisible.json"))
            return Historique()
        }
    }

    func enregistrer(_ historique: Historique) throws {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try JSONEncoder().encode(historique).write(to: fichierHistorique, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fichierHistorique.path)
    }

    func ecrireImage(_ png: Data) throws -> String {
        try FileManager.default.createDirectory(at: dossierImages, withIntermediateDirectories: true)
        let nom = UUID().uuidString + ".png"
        try png.write(to: urlImage(nom), options: .atomic)
        return nom
    }

    /// Efface les images des éléments retirés de l'historique.
    func nettoyer(_ elements: [Element]) {
        for nom in elements.compactMap(\.fichierImage) {
            try? FileManager.default.removeItem(at: urlImage(nom))
        }
    }
}
