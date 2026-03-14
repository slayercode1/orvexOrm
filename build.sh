#!/bin/bash
# OrvexORM Build Script
# Compiles all Lua files to bytecode (.luac) for distribution.
# Usage: bash build.sh [output_dir]

set -e

OUTPUT="${1:-dist}"
VERSION=$(node -p "require('./cli/package.json').version")

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "  ${CYAN}${BOLD}OrvexORM${NC} ${DIM}Build v${VERSION}${NC}"
echo ""

# Check for luac (local or Docker)
LUAC=""
USE_DOCKER=false

if command -v luac5.4 &> /dev/null; then
    LUAC="luac5.4"
elif command -v luac54 &> /dev/null; then
    LUAC="luac54"
elif command -v luac &> /dev/null; then
    LUAC="luac"
elif command -v docker &> /dev/null; then
    USE_DOCKER=true
    echo -e "  ${GREEN}✓${NC} Using: ${BOLD}Docker${NC} (nickblah/lua:5.4)"
else
    echo -e "  ${RED}Error: luac or docker not found.${NC}"
    echo -e "  ${DIM}Install Lua 5.4 or Docker.${NC}"
    exit 1
fi

if [ "$USE_DOCKER" = false ]; then
    echo -e "  ${GREEN}✓${NC} Using: ${BOLD}$LUAC${NC} ($($LUAC -v 2>&1 | head -1))"
fi

compile_file() {
    local infile="$1"
    local outfile="$2"
    if [ "$USE_DOCKER" = true ]; then
        docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 luac -o "$outfile" "$infile"
    else
        $LUAC -o "$outfile" "$infile"
    fi
}

# Clean output
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

# Directories to compile
DIRS=("core" "database" "utils" "lib")
COMPILED=0
ERRORS=0

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        continue
    fi

    mkdir -p "$OUTPUT/$dir"

    for file in "$dir"/*.lua; do
        [ -f "$file" ] || continue
        outfile="$OUTPUT/${file%.lua}.luac"

        if compile_file "$file" "$outfile"; then
            COMPILED=$((COMPILED + 1))
            echo -e "  ${GREEN}✓${NC} ${DIM}$file${NC} → ${BOLD}${file%.lua}.luac${NC}"
        else
            ERRORS=$((ERRORS + 1))
            echo -e "  ${RED}✗${NC} ${file} — compilation failed"
        fi
    done
done

# Abort if there were compilation errors
if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo -e "  ${RED}${BOLD}✗ Build failed with $ERRORS error(s). Fix the issues above and retry.${NC}"
    exit 1
fi

# Abort if nothing was compiled
if [ "$COMPILED" -eq 0 ]; then
    echo ""
    echo -e "  ${RED}✗ No files were compiled. Check that core/, database/, utils/, lib/ directories exist.${NC}"
    exit 1
fi

# Copy fxmanifest.lua (not compiled — FiveM needs it readable)
# But rewrite it to reference .luac files
echo -e ""
echo -e "  ${DIM}Generating fxmanifest.lua...${NC}"

cat > "$OUTPUT/fxmanifest.lua" << MANIFEST
fx_version 'cerulean'
game 'common'

name 'orvexorm'
version '${VERSION}'
author 'Orvex'
description 'Lightweight ORM for FiveM built on oxmysql'

dependency 'oxmysql'

server_scripts {
    'utils/helpers.luac',
    'utils/serializer.luac',
    'utils/validator.luac',
    'utils/cache.luac',
    'utils/logger.luac',

    'database/mysql.luac',
    'database/adapter.luac',

    'core/schema.luac',
    'core/query.luac',
    'core/relations.luac',
    'core/builder.luac',
    'core/transaction.luac',
    'core/migration.luac',
    'core/model.luac',
    'core/orm.luac',

    'lib/export.luac',
}

lua54 'yes'

provide 'orvexorm'
MANIFEST

# Copy import.lua as .lua (users include this in their fxmanifest)
cp lib/import.lua "$OUTPUT/lib/import.lua"
echo -e "  ${GREEN}✓${NC} ${DIM}lib/import.lua${NC} → copied (not compiled)"

echo ""
echo -e "  ${GREEN}${BOLD}✓ Build complete!${NC}"
echo -e "  ${DIM}$COMPILED files compiled${NC}"
echo -e "  ${DIM}Output: ${BOLD}$OUTPUT/${NC}"
echo ""
echo -e "  ${BOLD}Distribution structure:${NC}"
echo -e "  ${DIM}$OUTPUT/${NC}"
echo -e "  ${DIM}├── core/*.luac${NC}"
echo -e "  ${DIM}├── database/*.luac${NC}"
echo -e "  ${DIM}├── utils/*.luac${NC}"
echo -e "  ${DIM}├── lib/export.luac${NC}"
echo -e "  ${DIM}├── lib/import.lua${NC}"
echo -e "  ${DIM}└── fxmanifest.lua${NC}"
echo ""

# Copy dist into cli/ for npm publishing
echo -e "  ${DIM}Copying dist into cli/ for npm package...${NC}"
rm -rf cli/dist
cp -r "$OUTPUT" cli/dist
echo -e "  ${GREEN}✓${NC} ${BOLD}cli/dist/${NC} ready for npm publish"
echo ""
echo -e "  ${BOLD}To publish:${NC}"
echo -e "  ${DIM}cd cli && npm publish${NC}"
echo ""
