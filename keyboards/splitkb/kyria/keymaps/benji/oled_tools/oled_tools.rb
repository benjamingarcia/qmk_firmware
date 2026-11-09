#!/usr/bin/env ruby
# frozen_string_literal: true
#
# oled_tools.rb — Outils OLED pour la keymap benji (splitkb/kyria)
#
# Conversions image <-> firmware pour les deux écrans OLED 128x64.
# Prérequis : ruby (préinstallé sur macOS et la plupart des Linux).
#
# Sous-commandes :
#   to-screen   <file.pbm> [--flip180] [--stdout]  : image 128x64 -> array render_kyria_logo (écran droite)
#   from-screen <out.pbm>                           : array actuel -> PNG lisible dans GIMP (écran droite)
#   to-font     <file.pbm> [--stdout]               : logo 126x24 -> glyphes 0x80-0xD4 de glcdfont.c (écran gauche)
#   from-font   <out.pbm>                           : logo actuel -> pbm 126x24 (écran gauche)
#   calib       [--stdout]                          : génère le motif de calibration d'orientation
#
# Formats d'entrée : PBM ASCII (P1, export GIMP par défaut) ou binaire (P4).
# Conventions vérifiées sur le firmware QMK (driver SSD1306, OLED_ROTATION_180) :
#   - écran = 128x64, organisé en 8 pages de 8 lignes
#   - 1 octet = 1 colonne de 8 pixels, bit 0 (LSB) = pixel du haut
#   - l'art tel que dessiné dans GIMP apparaît tel quel à l'écran

require 'optparse'

KEYMAP = File.expand_path('..', __dir__) # keyboards/splitkb/kyria/keymaps/benji
SCREEN_W = 128
SCREEN_H = 64
FONT_GLYPH = 6        # octets par glyphe (largeur 6 px)
LOGO_COLS = 21        # glyphes par ligne de logo
LOGO_LINES = 3        # lignes du logo
LOGO_W = LOGO_COLS * FONT_GLYPH # 126
LOGO_H = LOGO_LINES * 8         # 24

# ---------- PBM I/O ----------

def read_pbm(path)
  src = File.binread(path)
  magic = src[/\A(P\d)/] or abort "Erreur : #{path} n'est pas un PBM."
  # scan de l'en-tête : lignes commentaires/vides ignorées, jusqu'à 2 nombres (w et h)
  pos = 0
  nums = []
  while pos < src.bytesize && nums.length < 2
    nl = src.index("\n", pos)
    line_end = nl || src.bytesize
    line = src.byteslice(pos, line_end - pos).strip
    pos = line_end + 1
    next if line.empty? || line.start_with?('#')
    line.split.each do |tok|
      break if nums.length >= 2
      nums << tok.to_i if tok =~ /\A\d+\z/
    end
  end
  abort 'Erreur : dimensions PBM illisibles.' if nums.length < 2
  w, h = nums
  px = Array.new(w * h, 0)
  if magic == 'P1'
    text = src.byteslice(pos, src.bytesize - pos).force_encoding('UTF-8').gsub(/#[^\n]*/, '')
    vals = text.scan(/[01]/).map(&:to_i)
    abort "Erreur : attendu #{w * h} pixels, trouvé #{vals.length}." unless vals.length == w * h
    h.times { |y| w.times { |x| px[y * w + x] = vals[y * w + x] } }
  else # P4 : bits alignés par rangée, 1 = noir = pixel allumé
    row_bytes = (w + 7) / 8
    expected = row_bytes * h
    data = src.byteslice(pos, src.bytesize - pos)
    data = (data + ("\x00" * expected)).byteslice(0, expected) if data.bytesize < expected
    abort 'Erreur : données P4 tronquées.' if data.bytesize < expected
    h.times do |y|
      row = data.byteslice(y * row_bytes, row_bytes).unpack('C*')
      w.times do |x|
        px[y * w + x] = (row[x / 8] >> (7 - (x % 8))) & 1
      end
    end
  end
  [w, h, px]
end

def write_pbm(path, w, h, px)
  File.open(path, 'w') do |f|
    f.puts 'P1'
    f.puts '# Export oled_tools.rb (GIMP compatible)'
    f.puts "#{w} #{h}"
    h.times do |y|
      f.puts px[y * w, w].map { |v| v == 1 ? '1' : '0' }.join
    end
  end
  puts "Écrit : #{path} (#{w}x#{h})"
end

# ---------- image -> octets écran ----------

def image_to_screen_bytes(w, h, px)
  abort "Erreur : l'écran fait #{SCREEN_W}x#{SCREEN_H}, l'image fait #{w}x#{h}. Redessine en #{SCREEN_W}x#{SCREEN_H}." unless w == SCREEN_W && h == SCREEN_H
  Array.new(SCREEN_H / 8) do |page|
    Array.new(SCREEN_W) do |x|
      b = 0
      8.times do |bit|
        b |= 1 << bit if px[(page * 8 + bit) * SCREEN_W + x] == 1
      end
      b
    end
  end.flatten
end

def screen_bytes_to_image(bytes)
  Array.new(SCREEN_W * SCREEN_H) do |i|
    x = i % SCREEN_W
    y = i / SCREEN_W
    (bytes[(y / 8) * SCREEN_W + x] >> (y % 8)) & 1
  end
end

def flip180(px, w, h)
  px.reverse.each_slice(w).map(&:reverse).flatten
end

# ---------- glyphe <-> pixels ----------

# logo 126x24 : 3 lignes de 21 cellules de 6x8 ; cellule (l, c) -> code 0x80 + 0x20*l + c
def logo_cell_codes
  (0...LOGO_LINES).flat_map { |l| (0...LOGO_COLS).map { |c| 0x80 + 0x20 * l + c } }
end

def image_to_font_glyphs(w, h, px)
  abort "Erreur : le logo fait #{LOGO_W}x#{LOGO_H} (3 lignes de 21 cellules de 6x8), l'image fait #{w}x#{h}." unless w == LOGO_W && h == LOGO_H
  logo_cell_codes.map do |code|
    l = (code - 0x80) / 0x20
    c = (code - 0x80) % 0x20
    (0...FONT_GLYPH).map do |k|
      x = c * FONT_GLYPH + k
      b = 0
      8.times do |bit|
        b |= 1 << bit if px[(l * 8 + bit) * LOGO_W + x] == 1
      end
      b
    end
  end
end

def font_glyphs_to_image(glyph_map)
  Array.new(LOGO_W * LOGO_H, 0).tap do |px|
    logo_cell_codes.each do |code|
      l = (code - 0x80) / 0x20
      c = (code - 0x80) % 0x20
      gl = glyph_map[code] or next
      8.times do |bit|
        FONT_GLYPH.times do |k|
          px[(l * 8 + bit) * LOGO_W + (c * FONT_GLYPH + k)] = 1 if (gl[k] >> bit) & 1 == 1
        end
      end
    end
  end
end

# ---------- patch keymap.c (écran de droite) ----------

def patch_screen_array(bytes, stdout_only: false)
  path = File.join(KEYMAP, 'keymap.c')
  src = File.read(path)
  re = /static const char PROGMEM kyria_logo\[\] = \{.*?\};/m
  abort 'Array kyria_logo introuvable dans keymap.c.' unless src.match?(re)
  body = bytes.each_slice(128).map { |sl| '        ' + sl.join(',') + ',' }.join("\n")
  body = body.sub(/,\z/, '')
  new_array = "static const char PROGMEM kyria_logo[] = {\n#{body}\n    };"
  if stdout_only
    puts new_array
  else
    File.write(path, src.sub(re, new_array))
    puts "keymap.c mis à jour : render_kyria_logo (#{bytes.length} octets). Vérifie avec : git diff #{path}"
  end
end

def extract_screen_array
  src = File.read(File.join(KEYMAP, 'keymap.c'))
  m = src.match(/static const char PROGMEM kyria_logo\[\] = \{(.*?)\};/m)
  abort 'Array kyria_logo introuvable dans keymap.c.' if m.nil?
  body = m[1].split('//').first
  bytes = body.scan(/\d+/).map(&:to_i)
  bytes << 0 while bytes.length < 1024
  bytes
end

# ---------- patch glcdfont.c (écran de gauche) ----------

def load_font
  src = File.read(File.join(KEYMAP, 'glcdfont.c'))
  bytes = src.scan(/0x[0-9A-Fa-f]{1,2}/).map { |t| t.to_i(16) }
  abort 'glcdfont.c illisible.' unless bytes.length == 224 * FONT_GLYPH
  bytes
end

def patch_font(glyph_map)
  path = File.join(KEYMAP, 'glcdfont.c')
  bytes = load_font
  glyph_map.each do |code, gl|
    gl.each_with_index { |b, k| bytes[code * FONT_GLYPH + k] = b }
  end
  header = src_lines = nil
  src = File.read(path)
  head = src[/\A.*?static const unsigned char font\[\] PROGMEM = \{\n/m]
  abort 'Table de police introuvable dans glcdfont.c.' if head.nil?
  rest = src[(head.length)..]
  footer_idx = rest =~ /\};/
  body_lines = bytes.each_slice(FONT_GLYPH).map { |sl| '    ' + sl.map { |b| format('0x%02X', b) }.join(', ') + ',' }
  body_lines[-1] = body_lines[-1].sub(/,\z/, '')
  File.write(path, head + body_lines.join("\n") + "\n};\n")
  puts "glcdfont.c mis à jour : #{glyph_map.length} glyphes (codes 0x80-0xD4). Vérifie avec : git diff #{path}"
end

def extract_font_logo
  bytes = load_font
  map = {}
  logo_cell_codes.each { |code| map[code] = bytes[code * FONT_GLYPH, FONT_GLYPH] }
  map
end

# ---------- motif de calibration ----------

def calibration_image
  px = Array.new(SCREEN_W * SCREEN_H, 0)
  set = lambda { |x, y| px[y * SCREEN_W + x] = 1 if x >= 0 && x < SCREEN_W && y >= 0 && y < SCREEN_H }
  # flèche vers le haut en haut-gauche
  8.times { |i| set[8 + i, 16 - i] }
  12.times { |x| set[4 + x, 8] }
  12.times { |y| set[10, y + 8] if y < 12 }
  # carré plein haut-droite
  10.times { |dx| 10.times { |dy| set[SCREEN_W - 16 + dx, 4 + dy] } }
  # damier bas-gauche
  16.times do |dx|
    16.times do |dy|
      set[4 + dx, SCREEN_H - 20 + dy] if (dx / 4 + dy / 4).even?
    end
  end
  # croix bas-droite
  12.times { |i| set[SCREEN_W - 18 + i, SCREEN_H - 14] }
  9.times { |i| set[SCREEN_W - 12, SCREEN_H - 18 + i] }
  px
end

# ---------- main ----------

def main
  options = { flip180: false, stdout: false }
  parser = OptionParser.new do |o|
    o.on('--flip180', 'Retourne l image de 180° avant conversion') { options[:flip180] = true }
    o.on('--stdout', 'Affiche le C généré sans modifier les fichiers') { options[:stdout] = true }
  end
  args = ARGV.dup
  parser.parse!(args)
  cmd = args.shift
  file = args.shift

  case cmd
  when 'to-screen'
    abort 'Usage : oled_tools.rb to-screen <file.pbm> [--flip180] [--stdout]' if file.nil?
    w, h, px = read_pbm(file)
    px = flip180(px, w, h) if options[:flip180]
    patch_screen_array(image_to_screen_bytes(w, h, px), stdout_only: options[:stdout])
  when 'from-screen'
    abort 'Usage : oled_tools.rb from-screen <out.pbm>' if file.nil?
    write_pbm(file, SCREEN_W, SCREEN_H, screen_bytes_to_image(extract_screen_array))
  when 'to-font'
    abort 'Usage : oled_tools.rb to-font <file.pbm> [--stdout]' if file.nil?
    w, h, px = read_pbm(file)
    glyphs = image_to_font_glyphs(w, h, px)
    if options[:stdout]
      glyphs.each_with_index { |gl, i| puts "// glyphe 0x#{format('%02X', logo_cell_codes[i])} : #{gl.map { |b| format('0x%02X', b) }.join(', ')}" }
    else
      patch_font(logo_cell_codes.zip(glyphs).to_h)
    end
  when 'from-font'
    abort 'Usage : oled_tools.rb from-font <out.pbm>' if file.nil?
    write_pbm(file, LOGO_W, LOGO_H, font_glyphs_to_image(extract_font_logo))
  when 'calib'
    px = calibration_image
    if options[:stdout]
      patch_screen_array(image_to_screen_bytes(SCREEN_W, SCREEN_H, px), stdout_only: true)
    else
      patch_screen_array(image_to_screen_bytes(SCREEN_W, SCREEN_H, px))
    end
  else
    puts <<~USAGE
      Usage : ruby oled_tools.rb <commande> [fichier] [options]

      Commandes :
        to-screen   <file.pbm>   128x64 -> array écran de droite (keymap.c)
        from-screen <out.pbm>    écran de droite actuel -> pbm 128x64
        to-font     <file.pbm>   logo 126x24 -> glyphes écran de gauche (glcdfont.c)
        from-font   <out.pbm>    logo actuel -> pbm 126x24
        calib                    motif de calibration d'orientation (écran de droite)

      Options : --flip180 (retourner l'image), --stdout (afficher sans patcher)
    USAGE
  end
end

main
