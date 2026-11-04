import Foundation

enum Contenu: Codable, Hashable, Sendable {
    case texte(String)
    case lien(URL)
    case fichiers([URL])
    /// `fichier` : nom du PNG dans le dossier d'images ; `empreinte` : SHA-256 des octets, pour repérer les doublons.
    case image(fichier: String, largeur: Int, hauteur: Int, empreinte: String)
}

struct Element: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var contenu: Contenu
    /// Nom de l'app au premier plan au moment de la copie.
    var appSource: String?

    /// Identité du contenu : deux copies identiques ne font qu'un élément.
    var cle: String {
        switch contenu {
        case .texte(let t): "t:" + t
        case .lien(let u): "l:" + u.absoluteString
        case .fichiers(let f): "f:" + f.map(\.path).joined(separator: "\n")
        case .image(_, _, _, let e): "i:" + e
        }
    }

    var fichierImage: String? {
        if case .image(let f, _, _, _) = contenu { f } else { nil }
    }

    /// Une ligne lisible pour la liste (200 caractères au plus).
    var resume: String {
        let brut: String = switch contenu {
        case .texte(let t): t
        case .lien(let u): u.absoluteString
        case .fichiers(let f): f.map(\.lastPathComponent).joined(separator: ", ")
        case .image(_, let l, let h, _): "Image \(l) × \(h)"
        }
        let ligne = brut.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ⏎ ")
        return ligne.count > 200 ? String(ligne.prefix(200)) + "…" : ligne
    }

    /// Texte sur lequel porte la recherche.
    var texteRecherche: String {
        switch contenu {
        case .texte(let t): t
        case .lien(let u): u.absoluteString
        case .fichiers(let f): f.map(\.path).joined(separator: " ")
        case .image: "image " + (appSource ?? "")
        }
    }
}

/// L'historique, le plus récent en tête. Les méthodes qui retirent des éléments les renvoient,
/// pour que l'appelant efface les images correspondantes.
struct Historique: Codable, Sendable {
    private(set) var elements: [Element] = []

    /// Ajoute en tête. Un doublon remonte en tête avec la nouvelle date et garde son identifiant ;
    /// le nouvel élément est alors renvoyé comme « retiré » si son image est un fichier à part.
    @discardableResult
    mutating func ajouter(_ nouveau: Element) -> [Element] {
        guard let i = elements.firstIndex(where: { $0.cle == nouveau.cle }) else {
            elements.insert(nouveau, at: 0)
            return []
        }
        var ancien = elements.remove(at: i)
        ancien.date = nouveau.date
        ancien.appSource = nouveau.appSource ?? ancien.appSource
        elements.insert(ancien, at: 0)
        return nouveau.fichierImage != nil && nouveau.fichierImage != ancien.fichierImage ? [nouveau] : []
    }

    /// Garde au plus `maximum` éléments, et rien de plus vieux que `ageMaxJours` (0 = sans limite d'âge).
    mutating func purger(maximum: Int, ageMaxJours: Int, maintenant: Date = .now) -> [Element] {
        let limite = maintenant.addingTimeInterval(-Double(ageMaxJours) * 86_400)
        var gardes: [Element] = [], retires: [Element] = []
        for e in elements {
            if gardes.count < maximum && (ageMaxJours == 0 || e.date >= limite) {
                gardes.append(e)
            } else {
                retires.append(e)
            }
        }
        elements = gardes
        return retires
    }

    mutating func supprimer(_ id: Element.ID) -> Element? {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return nil }
        return elements.remove(at: i)
    }

    mutating func vider() -> [Element] {
        defer { elements = [] }
        return elements
    }

    /// Tous les mots doivent apparaître, sans tenir compte de la casse ni des accents.
    func rechercher(_ requete: String) -> [Element] {
        let mots = requete.split(separator: " ").map(String.init)
        guard !mots.isEmpty else { return elements }
        return elements.filter { e in
            mots.allSatisfy { e.texteRecherche.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
