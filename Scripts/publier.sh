#!/bin/zsh
# Fabrique une version publiable de Magpie : build Release signé « Utahpik Code Signing », archive de mise à jour
# Sparkle (Magpie-<version>.zip, signée EdDSA), appcast.xml et DMG, à joindre à la Release GitHub v<version>.
# Les apps installées lisent releases/latest/download/appcast.xml et se mettent à jour seules.
# La clé EdDSA reste dans le Trousseau (compte « utahpik-magpie ») ; elle n'est jamais affichée.
#
# Usage : Scripts/publier.sh <version>       ex. Scripts/publier.sh 0.2.0
#         puis : gh release create v<version> ~/Developer/builds/magpie-publication/{*.dmg,*.zip,appcast.xml,SHA256SUMS.txt}
set -euo pipefail
cd "${0:A:h}/.."

VERSION=${1:?usage : publier.sh <version>}
SORTIE="$HOME/Developer/builds/magpie-publication"
DD="$SORTIE/derived"
APP="$DD/Build/Products/Release/Magpie.app"
rm -rf "$SORTIE"; mkdir -p "$SORTIE"

xcodegen generate --quiet
# Toutes les versions publiées portent la même signature : Sparkle et les autorisations macOS y tiennent.
# Numéro de build croissant (date) : Sparkle compare CFBundleVersion.
xcodebuild -project Magpie.xcodeproj -scheme Magpie -configuration Release -derivedDataPath "$DD" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Utahpik Code Signing" DEVELOPMENT_TEAM="" \
  OTHER_CODE_SIGN_FLAGS="--options=runtime" -quiet build
codesign --verify --deep --strict "$APP"

SPARKLE="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"
MAJ="$SORTIE/maj"; mkdir -p "$MAJ"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$MAJ/Magpie-$VERSION.zip"
"$SPARKLE/generate_appcast" --account utahpik-magpie \
  --download-url-prefix "https://github.com/AnthonyTrtre/magpie/releases/download/v$VERSION/" \
  --link "https://github.com/AnthonyTrtre/magpie" --maximum-versions 1 "$MAJ"
mv "$MAJ/Magpie-$VERSION.zip" "$MAJ/appcast.xml" "$SORTIE/"; rm -rf "$MAJ"

PREPA="$SORTIE/dmg"; mkdir -p "$PREPA"
ditto "$APP" "$PREPA/Magpie.app"
ln -s /Applications "$PREPA/Applications"
hdiutil create -quiet -volname "Magpie $VERSION" -srcfolder "$PREPA" -fs HFS+ -format UDZO "$SORTIE/Magpie-$VERSION.dmg"
rm -rf "$PREPA" "$DD"
( cd "$SORTIE" && shasum -a 256 "Magpie-$VERSION.dmg" "Magpie-$VERSION.zip" | tee SHA256SUMS.txt )
echo "Prêt : $SORTIE (DMG, zip Sparkle, appcast.xml, SHA256SUMS.txt)"
