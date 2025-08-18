#!/usr/bin/env bash
# Pós-instalação Deepin 25 — Dev Web/Mobile/Desktop + Apps + IA
# Autor: Jonntz
set -euo pipefail

### ========= CONFIG =========
GIT_USER=""
GIT_EMAIL=""

# Versões desejadas
PY311="3.11.9"
PY312="3.12.4"
PY313="3.13.0"
NODE22="22.7.0"
NODE24="24.0.0"
DOTNET8="8.0.401"
DOTNET9="9.0.100"
ASDF_VERSION="v0.14.0"

### ========= FUNÇÕES =========
log(){ echo -e "\n\033[1;36m$1\033[0m"; }
warn(){ echo -e "\n\033[1;33m$1\033[0m"; }
err(){ echo -e "\n\033[1;31m$1\033[0m"; }

ensure_line_in_file(){
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

install_java_series(){
  local series="$1" ver=""
  for dist in temurin zulu corretto openjdk; do
    ver=$(asdf latest java "${dist}-${series}" 2>/dev/null || true)
    if [ -n "${ver}" ]; then
      log "Instalando Java ${ver}..."
      asdf install java "${ver}"
      echo "${ver}"
      return 0
    fi
  done
  return 1
}

### ========= INÍCIO =========
log "🚀 Iniciando pós-instalação no Deepin 25..."
export DEBIAN_FRONTEND=noninteractive

### ===== ATUALIZAÇÃO E PACOTES =====
log "🔄 Atualizando sistema e instalando pacotes essenciais..."
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

sudo apt install -y \
  build-essential curl wget git unzip zip tar ca-certificates gnupg lsb-release \
  software-properties-common apt-transport-https \
  libfuse2 libssl-dev libreadline-dev zlib1g-dev libsqlite3-dev libbz2-dev \
  libffi-dev liblzma-dev xz-utils pkg-config \
  ffmpeg libavcodec-extra \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
  unrar fonts-liberation \
  android-tools-adb android-tools-fastboot \
  maven gradle flatpak

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

### ===== CONFIGURAÇÃO GIT =====
git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "code --wait" || true

### ===== INSTALAÇÃO ASDF =====
if [ ! -d "$HOME/.asdf" ]; then
  git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch "${ASDF_VERSION}"
fi

ensure_line_in_file '. $HOME/.asdf/asdf.sh' "$HOME/.bashrc"
ensure_line_in_file '. $HOME/.asdf/completions/asdf.bash' "$HOME/.bashrc"
ensure_line_in_file '. $HOME/.asdf/plugins/java/set-java-home.bash' "$HOME/.bashrc"

. "$HOME/.asdf/asdf.sh" || true
. "$HOME/.asdf/completions/asdf.bash" || true

asdf plugin add java || true
asdf plugin add python || true
asdf plugin add nodejs || true
asdf plugin remove dotnet-core 2>/dev/null || true
asdf plugin add dotnet https://github.com/hensou/asdf-dotnet.git || true

JAVA17="$(install_java_series 17 || true)"
JAVA21="$(install_java_series 21 || true)"
JAVA24="$(install_java_series 24 || true)"
if [ -n "${JAVA24}" ]; then
  asdf global java "${JAVA24}"
else
  [ -n "${JAVA21}" ] && asdf global java "${JAVA21}"
fi

asdf install python "${PY311}"
asdf install python "${PY312}"
asdf install python "${PY313}"
asdf global python "${PY311}"

asdf install nodejs "${NODE22}"
asdf install nodejs "${NODE24}"
asdf global nodejs "${NODE22}"

corepack enable
corepack prepare yarn@stable --activate || true
corepack prepare pnpm@latest --activate || true

asdf install dotnet "${DOTNET8}" || warn "Falha ao instalar .NET ${DOTNET8}"
asdf install dotnet "${DOTNET9}" || warn "Falha ao instalar .NET ${DOTNET9}"
asdf where dotnet "${DOTNET8}" >/dev/null 2>&1 && asdf global dotnet "${DOTNET8}"
asdf reshim

npm install -g @angular/cli@20

### ===== INSTALAÇÃO DOCKER =====
sudo apt remove -y docker docker-engine docker.io containerd runc || true
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
log "✅ Docker instalado. Use 'newgrp docker' para aplicar permissões sem logout."

### ===== INSTALAÇÃO LLM / Ollama =====
log "🧠 Instalando Ollama LLM local..."
OLLAMA_TMP="/tmp/ollama_install.sh"
curl -fsSL https://ollama.com/install.sh -o "$OLLAMA_TMP" || warn "Falha ao baixar Ollama."
chmod +x "$OLLAMA_TMP"

# Executa como root para evitar erro de diretório
sudo "$OLLAMA_TMP" || warn "Falha na instalação do Ollama. Ignorar se API já está disponível."

# Open WebUI via Docker
newgrp docker <<'EOF'
docker rm -f open-webui 2>/dev/null || true
docker run -d --name open-webui --restart unless-stopped -p 3000:8080 -e OLLAMA_BASE_URL=http://127.0.0.1:11434 ghcr.io/open-webui/open-webui:main || true
EOF

python3 -m pip install --upgrade pip
pip install --upgrade jupyterlab ipykernel transformers openai langchain litellm

### ===== APLICATIVOS =====
# Google Chrome
tmp_deb="/tmp/google-chrome-stable_current_amd64.deb"
wget -q -O "$tmp_deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y "$tmp_deb" || sudo apt -f install -y
rm -f "$tmp_deb"
warn "⚠️ Configure Chrome como navegador padrão manualmente."

# VS Code via .deb (contorna problema de keyrings readonly)
tmp_vscode="/tmp/code_latest_amd64.deb"
wget -q -O "$tmp_vscode" https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64
sudo apt install -y "$tmp_vscode" || sudo apt -f install -y
rm -f "$tmp_vscode"

# Flatpak apps
apps=(
io.pgadmin.pgadmin4
com.mongodb.Compass
com.jetbrains.IntelliJ-IDEA-Community
io.github.mimbrero.WhatsAppDesktop
org.telegram.desktop
com.getpostman.Postman
us.zoom.Zoom
com.microsoft.Teams
org.filezillaproject.Filezilla
com.capcut.CapCut
org.kde.kdenlive
com.spotify.Client
com.google.AndroidStudio
)
for app in "${apps[@]}"; do
  flatpak install -y flathub "$app" || true
done

### ===== VARIÁVEIS DE AMBIENTE =====
ensure_line_in_file 'export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
ensure_line_in_file 'export ANDROID_HOME="$HOME/Android/Sdk"' "$HOME/.bashrc"
ensure_line_in_file 'export ANDROID_SDK_ROOT="$HOME/Android/Sdk"' "$HOME/.bashrc"
ensure_line_in_file 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"' "$HOME/.bashrc"

sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w fs.file-max=65535

sudo apt -f install -y || true
sudo apt autoremove -y
sudo apt autoclean -y

log "🎉 Pós-instalação completa!"
echo " - Docker pronto (use 'newgrp docker' para aplicar sem logout)"
echo " - Open WebUI (LLM) em: http://localhost:3000"
echo " - Ollama LLM disponível em: 127.0.0.1:11434"
echo " - Chrome instalado. Configure como padrão manualmente."
echo " - VS Code instalado via .deb."
echo " - Angular CLI v20, Yarn/Pnpm via Corepack."
echo " - Java (asdf): 17/21/24; Python: 3.11/3.12/3.13; Node: 22/24; .NET: 8/9"
echo " - Variáveis de ambiente adicionadas ao ~/.bashrc"
