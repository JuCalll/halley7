#!/usr/bin/env bash
set -euo pipefail

RAIZ_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ_REPO"

echo "=== PRUEBAS DE ROBUSTEZ HALLEY-7 (PR #12) ==="
echo "Directorio de trabajo: $RAIZ_REPO"

command -v swipl >/dev/null 2>&1 || {
  echo "ERROR: swipl no esta disponible en PATH" >&2
  exit 1
}

HECHOS="prolog/hechos_ejemplo.pl"
RAZONADOR="prolog/razonador.pl"

for arch in "$HECHOS" "$RAZONADOR"; do
  if [ ! -f "$arch" ]; then
    echo "ERROR: falta el archivo requerido $arch" >&2
    exit 1
  fi
done

echo "[1/5] Verificando carga limpia de hechos y razonador..."
swipl -q -s "$RAZONADOR" -g "consult('$HECHOS'), halt"

echo "[2/5] Probando consulta 'donde' (caso con evidencia y caso sin evidencia)..."
swipl -q -s "$RAZONADOR" -- "$HECHOS" donde valcarcel 2254786200
swipl -q -s "$RAZONADOR" -- "$HECHOS" donde persona_inexistente 2254786200

echo "[3/5] Probando consulta 'quien_tarjeta' (tarjeta reportada perdida LP-04)..."
swipl -q -s "$RAZONADOR" -- "$HECHOS" quien_tarjeta LP-04 2254786787

echo "[4/5] Probando consulta 'recorrido' (terminacion sin ciclos en anillo)..."
swipl -q -s "$RAZONADOR" -- "$HECHOS" recorrido cualquiera DOR GEN 2254781524 120

echo "[5/5] Probando consulta 'exterior' (indicios en ventana del corte)..."
swipl -q -s "$RAZONADOR" -- "$HECHOS" exterior 2254786800 2254788900

echo "=== TODAS LAS PRUEBAS DE ROBUSTEZ PASARON ==="