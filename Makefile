# make projet | build | test | lancer | installer
# Les produits de compilation vont hors iCloud (D008).
DD := $(HOME)/Developer/builds/magpie
XB := xcodebuild -project Magpie.xcodeproj -scheme Magpie -derivedDataPath $(DD)
APP := $(DD)/Build/Products/Release/Magpie.app

projet: ; xcodegen generate
build: projet ; $(XB) -configuration Release build
test: projet ; $(XB) test
lancer: build ; open "$(APP)"
installer: build ; ditto "$(APP)" "/Applications/Magpie.app" && open "/Applications/Magpie.app"
