# Cycles de développement OLED — keymap benji (splitkb/kyria, rev1)

Deux écrans SSD1306 **128×64**, avec `OLED_ROTATION_180` (défini via `oled_init_user` dans `keymap.c`).

- **Écran de gauche** (moitié master, USB branché à gauche) : `render_status()` — un logo de 3 lignes de 21 caractères (glyphes `0x80`–`0xD4` de `glcdfont.c`), puis du texte (`oled_write_P`).
- **Écran de droite** (moitié slave) : `render_kyria_logo()` — image plein écran brute de 1024 octets (`oled_write_raw_P`) dans `keymap.c`.

Toutes les commandes ci-dessous se lancent depuis ce dossier (`oled_tools/`).

## Boucle commune : compiler, flasher, observer

```bash
# compile (vérification rapide)
qmk compile -kb splitkb/kyria/rev1 -km benji

# flash : brancher le câble USB sur la moitié à flasher,
# puis double-appui rapide sur le bouton RESET (bootloader Caterina)
qmk flash -kb splitkb/kyria/rev1 -km benji
```

Flasher les **deux moitiés** (même firmware : brancher à gauche, flasher, brancher à droite, flasher).

Conventions validées sur ce firmware : l'art noir-sur-blanc tel que dessiné dans GIMP apparaît tel quel à l'écran (1 octet = colonne de 8 pixels, bit 0 = pixel du haut). En cas de doute, voir « Calibration » en bas.

## Cycle 1 — Écran de droite : remplacer l'image plein écran

1. **(Optionnel) Repartir de l'image actuelle** pour la modifier dans GIMP :

   ```bash
   ruby oled_tools.rb from-screen image_actuelle.pbm
   ```

2. **Dessiner** dans GIMP : 128×64 px, pixel art **au noir sur fond blanc** (les pixels noirs s'allument à l'écran). Travailler en 1:1 sans redimensionnement automatique.

3. **Exporter** : `Fichier → Exporter sous → image.pbm`, format PBM, encodage **ASCII** (pas "Raw"/binaire).

4. **Convertir et patcher** `keymap.c` (array `render_kyria_logo`) :

   ```bash
   ruby oled_tools.rb to-screen image.pbm
   # --flip180 si le résultat apparaît retournée à l'écran
   # --stdout pour juste afficher le code C sans modifier le fichier
   ```

5. Compiler, flasher, observer. Recommencer en 2.

## Cycle 2 — Écran de gauche : remplacer le logo

Le logo s'affiche comme **3 lignes de 21 « caractères »** issus de la police custom. Chaque caractère est une cellule de **6×8 px**. Canvas total : **126×24 px** (21×3 cellules). Le reste de l'écran (texte `Kyria rev …`, noms de couches, locks) se règle directement dans `keymap.c` (`oled_write_P` dans `render_status`).

1. **(Optionnel) Repartir du logo actuel** (le logo QMK) :

   ```bash
   ruby oled_tools.rb from-font logo_actuel.pbm
   ```

2. **Dessiner** dans GIMP : nouveau fichier **126×24**, noir sur blanc. Astuce : `Affichage → Grille` avec une grille de 6×8 px (`Image → Configuration de la grille`) pour voir les cellules-glyphes.

3. **Exporter** en PBM ASCII comme au cycle 1.

4. **Convertir et patcher** `glcdfont.c` (glyphes `0x80`–`0xD4`, sans toucher au reste de la police) :

   ```bash
   ruby oled_tools.rb to-font logo.pbm
   ```

5. Compiler, flasher, observer.

## Calibration (une seule fois, en cas de doute sur l'orientation)

```bash
ruby oled_tools.rb calib   # remplace l'image de droite par un motif test — flasher et vérifier
```

Tu dois voir : une **flèche vers le haut en haut à gauche**, un **carré plein en haut à droite**, un **damier en bas à gauche**, une **croix en bas à droite**. Si l'écran montre l'inverse, ajoute `--flip180` à toutes tes conversions `to-screen`. (Le motif a remplacé l'image de droite : régénère-la depuis ton `.pbm` ensuite.)

## Notes

- Les commandes `from-*`/`to-*` patchent les fichiers en place ; le contrôle se fait avec `git diff`, l'annulation avec `git restore`.
- `oled_magic.pbm` (192×56) est une ancienne source qui ne correspond pas à l'array actuel — préférer un art dessiné directement en 128×64.
- Ruby est requis (préinstallé sur macOS et la plupart des Linux).
