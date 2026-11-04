import AppKit
import Foundation
import Testing
@testable import Magpie

private func element(_ texte: String, il secondes: TimeInterval = 0, maintenant: Date = .now) -> Element {
    Element(date: maintenant.addingTimeInterval(-secondes), contenu: .texte(texte))
}

@Suite struct HistoriqueTests {
    @Test func ajoutEnTeteEtDoublonQuiRemonte() {
        var h = Historique()
        h.ajouter(element("a"))
        h.ajouter(element("b"))
        let idA = h.elements[1].id
        h.ajouter(element("a"))
        #expect(h.elements.map(\.resume) == ["a", "b"])
        #expect(h.elements[0].id == idA)
    }

    @Test func purgeParNombreEtParAge() {
        let maintenant = Date.now
        var h = Historique()
        for (i, t) in ["vieux", "moyen", "recent"].enumerated() {
            h.ajouter(element(t, il: Double(2 - i) * 10 * 86_400, maintenant: maintenant))
        }
        #expect(h.purger(maximum: 10, ageMaxJours: 15, maintenant: maintenant).map(\.resume) == ["vieux"])
        #expect(h.purger(maximum: 1, ageMaxJours: 0, maintenant: maintenant).map(\.resume) == ["moyen"])
        #expect(h.elements.map(\.resume) == ["recent"])
    }

    @Test func rechercheSansCasseNiAccentsTousLesMots() {
        var h = Historique()
        h.ajouter(element("Réunion équipe mardi"))
        h.ajouter(element("liste de courses"))
        #expect(h.rechercher("reunion MARDI").map(\.resume) == ["Réunion équipe mardi"])
        #expect(h.rechercher("reunion courses").isEmpty)
        #expect(h.rechercher("  ").count == 2)
    }

    @Test func resumeSurUneLigneEtTronque() {
        #expect(element("  un\n\ndeux  \n").resume == "un ⏎ deux")
        #expect(element(String(repeating: "x", count: 300)).resume.count == 201)
    }
}

@Suite struct LecteurTests {
    func pressePapiers() -> NSPasteboard { NSPasteboard(name: .init("magpie-test-\(UUID().uuidString)")) }

    @Test func texteEtLien() {
        let pb = pressePapiers()
        pb.clearContents(); pb.setString("bonjour", forType: .string)
        #expect(Lecteur.lire(pb) == .contenu(.texte("bonjour")))
        pb.clearContents(); pb.setString(" https://example.com/a?b=1 \n", forType: .string)
        #expect(Lecteur.lire(pb) == .contenu(.lien(URL(string: "https://example.com/a?b=1")!)))
        pb.clearContents(); pb.setString("voir https://x.fr", forType: .string)
        #expect(Lecteur.lire(pb) == .contenu(.texte("voir https://x.fr")))
    }

    @Test func videEtMotDePasseIgnores() {
        let pb = pressePapiers()
        pb.clearContents(); pb.setString("   \n", forType: .string)
        #expect(Lecteur.lire(pb) == nil)
        pb.clearContents()
        pb.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("motdepasse", forType: .string)
        #expect(Lecteur.lire(pb) == nil)
    }

    @Test func fichiers() {
        let pb = pressePapiers()
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        pb.clearContents(); pb.writeObjects([url as NSURL])
        #expect(Lecteur.lire(pb) == .contenu(.fichiers([url])))
    }

    @Test func imageEnPNGAvecEmpreinteStable() throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pb = pressePapiers()
        pb.clearContents(); pb.setData(rep.tiffRepresentation, forType: .tiff)
        guard case .image(_, let l, let h, let e1) = Lecteur.lire(pb) else { Issue.record("pas une image"); return }
        #expect(l == 4 && h == 3)
        guard case .image(_, _, _, let e2) = Lecteur.lire(pb) else { return }
        #expect(e1 == e2)
    }
}

@MainActor @Suite struct ControleurTests {
    func controleur() -> (ControleurMagpie, Stockage) {
        let s = Stockage(dossier: FileManager.default.temporaryDirectory.appending(path: "magpie-\(UUID().uuidString)"))
        return (ControleurMagpie(stockage: s, reglages: UserDefaults(suiteName: "magpie-\(UUID().uuidString)")!), s)
    }

    @Test func persisteEtRecharge() {
        let (c, s) = controleur()
        c.ajouter(.contenu(.texte("à garder")), source: "Notes")
        let relu = s.charger()
        #expect(relu.elements.map(\.resume) == ["à garder"])
        #expect(relu.elements.first?.appSource == "Notes")
        let droits = try? FileManager.default.attributesOfItem(atPath: s.fichierHistorique.path)[.posixPermissions] as? Int
        #expect(droits == 0o600)
    }

    @Test func imageDoublonUnSeulFichierEtNettoyage() throws {
        let (c, s) = controleur()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        c.ajouter(.image(png: png, largeur: 1, hauteur: 1, empreinte: "abc"), source: nil)
        c.ajouter(.image(png: png, largeur: 1, hauteur: 1, empreinte: "abc"), source: nil)
        #expect(c.historique.elements.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.dossierImages.path).count == 1)
        c.vider()
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.dossierImages.path).isEmpty)
    }

    @Test func pauseEtAppsIgnorees() {
        let (c, _) = controleur()
        let pb = NSPasteboard(name: .init("magpie-test-\(UUID().uuidString)"))
        pb.clearContents(); pb.setString("secret", forType: .string)
        c.enPause = true
        c.capturer(pb, appActive: nil)
        #expect(c.historique.elements.isEmpty)
        c.enPause = false
        c.capturer(pb, appActive: nil)
        #expect(c.historique.elements.count == 1)
    }

    @Test func reglerLeMaximumPurgeTout() {
        let (c, _) = controleur()
        for i in 0..<5 { c.ajouter(.contenu(.texte("n\(i)")), source: nil) }
        c.maximum = 2
        #expect(c.historique.elements.map(\.resume) == ["n4", "n3"])
    }
}
