#!/usr/bin/env bash
# =============================================================================
# ps1_transfer.sh
# Descomprime un juego de PS1 (.7z) en el seedbox y lo transfiere al
# SuperStation vía SCP (pasando por la Mac como puente).
#
# Uso:
#   ./ps1_transfer.sh "Nombre Del Juego"
# =============================================================================

# ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────

SEEDBOX_USER="danisdead"
SEEDBOX_HOST="192.168.1.191"
SEEDBOX_ROOT="/mnt/torrents/incomplete"

DIR_AMERICA="PSX (America) 2014-12-21"
DIR_JAPAN_1="Playstation 1 (Japan) Part 1"
DIR_JAPAN_2="Playstation 1 (Japan) Part 2"

SEEDBOX_TMP_DIR="/tmp/ps1_extract"

SUPERSTATION_USER="root"
SUPERSTATION_HOST="192.168.1.163"
SUPERSTATION_BASE="/media/fat/games/PSX"

# ─── VALIDACIÓN ───────────────────────────────────────────────────────────────

if [[ -z "$1" ]]; then
  echo "❌  Uso: $0 \"Nombre Del Juego\""
  echo "    Ejemplo: $0 \"Wipeout\""
  exit 1
fi

GAME_NAME="$1"
SUPERSTATION_DEST="${SUPERSTATION_BASE}/${GAME_NAME}"

# ─── SELECTOR DE REGIÓN ───────────────────────────────────────────────────────

echo ""
echo "🌎  ¿De qué región es el juego?"
echo ""
echo "   1) América"
echo "   2) Japón"
echo ""
read -rp "   Elige [1/2]: " REGION_CHOICE
echo ""

case "$REGION_CHOICE" in
  1)
    REGION_LABEL="América"
    SEARCH_DIRS=("${SEEDBOX_ROOT}/${DIR_AMERICA}")
    ;;
  2)
    REGION_LABEL="Japón"
    SEARCH_DIRS=(
      "${SEEDBOX_ROOT}/${DIR_JAPAN_1}"
      "${SEEDBOX_ROOT}/${DIR_JAPAN_2}"
    )
    ;;
  *)
    echo "❌  Opción inválida. Elige 1 o 2."
    exit 1
    ;;
esac

echo "🎮  Juego    : $GAME_NAME"
echo "🌍  Región   : $REGION_LABEL"
echo "📺  Destino  : ${SUPERSTATION_USER}@${SUPERSTATION_HOST}:${SUPERSTATION_DEST}"
echo ""

# ─── PASO 1: BUSCAR EL .7z EN LAS CARPETAS CORRESPONDIENTES ──────────────────

echo "🔍  Buscando el archivo en el seedbox..."

ARCHIVE=""
for DIR in "${SEARCH_DIRS[@]}"; do
  CANDIDATE="${DIR}/${GAME_NAME}.7z"
  if ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "test -f '${CANDIDATE}'"; then
    ARCHIVE="$CANDIDATE"
    echo "✅  Encontrado en: ${CANDIDATE}"
    break
  fi
done

if [[ -z "$ARCHIVE" ]]; then
  echo "❌  No se encontró \"${GAME_NAME}.7z\" en ninguna carpeta de ${REGION_LABEL}."
  echo ""
  echo "    Archivos disponibles que coinciden:"
  for DIR in "${SEARCH_DIRS[@]}"; do
    echo "    📁 ${DIR}:"
    ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "ls '${DIR}' | grep -i '${GAME_NAME}'" 2>/dev/null || echo "       (ninguno)"
  done
  exit 1
fi
echo ""

# ─── PASO 2: DESCOMPRIMIR EN EL SEEDBOX ──────────────────────────────────────

GAME_EXTRACT_DIR="${SEEDBOX_TMP_DIR}/${GAME_NAME}"

echo "📂  Descomprimiendo en el seedbox..."
ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" bash <<EOF
  set -e
  mkdir -p '${GAME_EXTRACT_DIR}'
  7z x '${ARCHIVE}' -o'${GAME_EXTRACT_DIR}' -y -bd | grep -E "^(Extracting|ERROR)" || true
  echo "Archivos extraídos:"
  ls -lh '${GAME_EXTRACT_DIR}'
EOF

[[ $? -ne 0 ]] && { echo "❌  Error al descomprimir."; exit 1; }
echo "✅  Descompresión completada."
echo ""

# ─── PASO 3: VERIFICAR .bin Y .cue ───────────────────────────────────────────

echo "🔎  Verificando archivos .bin y .cue..."
BIN_COUNT=$(ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "find '${GAME_EXTRACT_DIR}' -maxdepth 2 -iname '*.bin' | wc -l")
CUE_COUNT=$(ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "find '${GAME_EXTRACT_DIR}' -maxdepth 2 -iname '*.cue' | wc -l")

echo "   .bin encontrados: $BIN_COUNT"
echo "   .cue encontrados: $CUE_COUNT"

if [[ "$BIN_COUNT" -eq 0 ]] || [[ "$CUE_COUNT" -eq 0 ]]; then
  echo "⚠️   No se encontraron ambos tipos. Contenido del .7z:"
  ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "ls -lh '${GAME_EXTRACT_DIR}'"
  ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "rm -rf '${GAME_EXTRACT_DIR}'"
  exit 1
fi
echo ""

# ─── PASO 4: CREAR CARPETA DESTINO EN EL SUPERSTATION ────────────────────────

echo "📁  Preparando destino en el SuperStation..."
ssh "${SUPERSTATION_USER}@${SUPERSTATION_HOST}" "mkdir -p '${SUPERSTATION_DEST}'" || {
  echo "❌  No se pudo conectar al SuperStation."
  exit 1
}
echo "✅  Directorio listo."
echo ""

# ─── PASO 5: TRANSFERIR (seedbox → Mac → SuperStation) ────────────────────────

echo "🚀  Transfiriendo archivos..."
echo "    (seedbox → Mac → SuperStation)"
echo ""

LOCAL_TMP=$(mktemp -d)
trap 'rm -rf "$LOCAL_TMP"; ssh "${SEEDBOX_USER}@${SEEDBOX_HOST}" "rm -rf '"'"'${GAME_EXTRACT_DIR}'"'"'" 2>/dev/null' EXIT

echo "   ⬇️  Descargando desde seedbox a Mac..."
scp -r "${SEEDBOX_USER}@${SEEDBOX_HOST}:${GAME_EXTRACT_DIR}/." "$LOCAL_TMP/"

echo "   ⬆️  Subiendo desde Mac al SuperStation..."
scp -r "$LOCAL_TMP/." "${SUPERSTATION_USER}@${SUPERSTATION_HOST}:${SUPERSTATION_DEST}/"

echo ""
echo "✅  Transferencia completada."
echo ""

# ─── LISTO ────────────────────────────────────────────────────────────────────

echo "🎉  ¡Listo! \"${GAME_NAME}\" ya está en tu SuperStation."
echo "    Ruta: ${SUPERSTATION_DEST}/"