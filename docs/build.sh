#!/usr/bin/env bash
# Render the SIH26038 design document to PDF.
# Requires chromium. Run from anywhere: bash docs/build.sh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
chromium --headless --disable-gpu --no-sandbox \
  --no-pdf-header-footer \
  --virtual-time-budget=12000 \
  --print-to-pdf=SIH26038_Technical_Design_Document.pdf \
  SIH26038_design.html
echo "Wrote $DIR/SIH26038_Technical_Design_Document.pdf"
