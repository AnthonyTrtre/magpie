<p align="center"><img src="docs/logo/logo.svg" width="160" alt="Icône de Magpie"></p>

# Magpie

Historique du presse-papiers pour macOS, dans la barre de menus. Gratuit, open source, sans compte, sans télémétrie.

La pie garde tout ce qui brille : Magpie garde tout ce que vous copiez (texte, liens, fichiers, images) et vous le
rend en deux secondes.

## Ce qu'elle fait

- **⌃⌘V** ouvre un panneau au centre de l'écran, recherche prête à taper (tous les mots, sans casse ni accents).
- **↩** ou clic recolle dans l'app d'où vous venez ; **⌥↩** copie seulement ; **⌘1 à ⌘9** pour les neuf premiers ;
  **⌘⌫** supprime un élément ; **échap** ferme.
- Recopier un élément le fait remonter au lieu de le dupliquer.
- Les copies marquées « mot de passe » (types [nspasteboard.org](http://nspasteboard.org)) et celles des gestionnaires
  de mots de passe ne sont jamais enregistrées. Bouton pause dans le menu.
- Conservation réglable : 100 à 2 000 éléments, 1 à 90 jours ou sans limite (par défaut 500 éléments et 30 jours).
- Ouverture à la connexion, activée au premier lancement (désactivable dans le menu).

## Vie privée

Aucun compte, aucune télémétrie. L'historique reste sur votre Mac, dans
`~/Library/Application Support/fr.anthony.magpie/` (fichier lisible par vous seul). « Vider l'historique » dans le
menu l'efface. La seule connexion vers Internet est la recherche de mises à jour sur github.com, désactivable :
`defaults write fr.anthony.magpie SUEnableAutomaticChecks -bool false`.

## Installer

1. Téléchargez `Magpie-<version>.dmg` dans les [Releases](https://github.com/AnthonyTrtre/magpie/releases/latest),
   ouvrez-le et glissez **Magpie.app** dans **Applications**.
2. L'app n'est pas notarisée par Apple : au premier lancement, faites clic droit › **Ouvrir**, puis **Ouvrir**
   (ou Réglages Système › Confidentialité et sécurité › **Ouvrir quand même**).
3. Pour le collage automatique, autorisez Magpie dans Réglages Système › Confidentialité et sécurité ›
   **Accessibilité**. Sans cette autorisation, l'élément choisi est seulement copié : faites ⌘V vous-même.

Les mises à jour arrivent ensuite toutes seules (Sparkle) : Magpie consulte `appcast.xml` de la dernière Release
toutes les 6 heures, télécharge l'archive, vérifie sa signature EdDSA et l'installe à la fermeture de l'app. Menu ›
**Rechercher des mises à jour…** pour le faire tout de suite.

Configuration : macOS 26 ou plus récent.

## Compiler

Il faut Xcode 26 et [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make test       # tests
make installer  # compile et copie dans /Applications
```

L'app est signée « ad hoc » par défaut. Pour signer avec votre équipe Apple (utile pour garder l'autorisation
Accessibilité d'une version à l'autre), créez `Config/Signing.local.xcconfig` :

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

## Licence

MIT, voir [LICENSE](LICENSE). Sparkle (MIT) pour les mises à jour.
