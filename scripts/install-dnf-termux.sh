#!/data/data/com.termux/files/usr/bin/bash
# install-dnf-termux.sh - Instala DNF en Termux
# Inspirado en termux-pacman/pacman-for-termux/install.sh

set -e

echo "=== dnf-for-termux Installer ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Check Termux
if [ ! -d "$PREFIX" ]; then
    echo -e "${RED}❌ Esto solo funciona en Termux${NC}"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
case $ARCH in
    aarch64) TERMUX_ARCH="aarch64" ;;
    armv7l|armhf) TERMUX_ARCH="arm" ;;
    x86_64) TERMUX_ARCH="x86_64" ;;
    i686) TERMUX_ARCH="i686" ;;
    *)
        echo -e "${RED}❌ Arquitectura no soportada: $ARCH${NC}"
        exit 1
        ;;
esac
echo -e "${GREEN}✓${NC} Arquitectura: $TERMUX_ARCH"

# Check required tools
for cmd in curl gpg tar xz; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${YELLOW}⚠  Instalando $cmd...${NC}"
        pkg install -y $cmd
    fi
done

# Create directories
echo "Creando directorios..."
mkdir -p $PREFIX/etc/dnf/vars
mkdir -p $PREFIX/etc/yum.repos.d
mkdir -p $PREFIX/var/lib/dnf
mkdir -p $PREFIX/var/cache/dnf
mkdir -p $PREFIX/share/dnf

# Install DNF package
echo "Instalando dnf..."
DNF_PKG="dnf5_${TERMUX_ARCH}.deb"
DNF_URL="https://packages.termux.dev/rpm/${DNF_PKG}"

curl -L -o "$TMPDIR/$DNF_PKG" "$DNF_URL"
dpkg -i "$TMPDIR/$DNF_PKG" || {
    echo -e "${YELLOW}⚠  Instalando dependencias...${NC}"
    apt install -f -y
    dpkg -i "$TMPDIR/$DNF_PKG"
}
rm -f "$TMPDIR/$DNF_PKG"

# Configure GPG keys
echo "Configurando llaves GPG..."
curl -L -o "$TMPDIR/termux-rpm.gpg" "https://packages.termux.dev/rpm/termux-rpm.gpg"
mkdir -p $PREFIX/etc/pki/rpm-gpg
cp "$TMPDIR/termux-rpm.gpg" $PREFIX/etc/pki/rpm-gpg/
rm -f "$TMPDIR/termux-rpm.gpg"

# Verify installation
if command -v dnf &>/dev/null; then
    echo -e "${GREEN}✅ DNF instalado exitosamente${NC}"
    dnf --version
else
    echo -e "${RED}❌ DNF no se pudo instalar${NC}"
    exit 1
fi

echo ""
echo "=== Instalación completada ==="
echo "Ejecuta 'dnf update' para actualizar"
