#!/usr/bin/env bash
# Instala o kiosk Pharus Terminal nesta máquina (Debian 13 / DietPi), direto da última versão publicada aqui.
#
#   curl -fsSL https://raw.githubusercontent.com/IFNMG-Almenara/PharusTerminal/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/IFNMG-Almenara/PharusTerminal/main/install.sh | bash -s -- --reverb-key CHAVE --yes
#
# Roda como root (padrão do DietPi; em Debian comum use sudo). Detecta a arquitetura (armhf/arm64/amd64) e o Debian
# da máquina, baixa o Release mais recente deste repositório, confere o SHA-256, instala as dependências, grava
# /etc/pharus-terminal.conf e liga o autostart (DietPi) ou deixa os arquivos prontos (Debian comum, sem autostart
# automático). Pode ser executado de novo para atualizar ou reconfigurar.
#
# Opções (tudo o que não for informado é perguntado, exceto com --yes, que usa os padrões):
#   --url URL            origem da API/front (padrão: https://eventos.ifnmg.edu.br)
#   --reverb-key CHAVE   chave pública do app Reverb (REVERB_APP_KEY do backend; obrigatória, sem ela o pareamento
#                        por OTP não aparece). Não é segredo: o próprio site já a expõe no JavaScript do navegador
#                        (NEXT_PUBLIC_REVERB_APP_KEY); o que precisa ficar privado é o REVERB_APP_SECRET, que nunca
#                        sai do backend. Ainda assim ela é só perguntada/recebida por flag, nunca fixada aqui, porque
#                        varia por ambiente (produção, homologação, servidor local).
#   --printer NOME       impressora das etiquetas já cadastrada no CUPS (opcional)
#   --printer-ip IP      instala o CUPS e cria a fila da Brother QL de rede (IPP) neste IP
#   --printer-usb        idem, para a QL ligada por USB
#   --roll TAMANHO       rolo da impressora (padrão 29x90, cortado; 29 ou 62 = fita contínua)
#   --render MODO        software (padrão) ou hardware (GPU); troca depois com 'pharus-render' no dispositivo
#   --repo DONO/REPO     repositório dos Releases a instalar e a usar na atualização automática (padrão: este)
#   --yes, -y            não pergunta nada (usa os padrões); ainda exige --reverb-key, pois não há padrão seguro
#   --sem-iniciar        não inicia o kiosk ao terminar (fica pronto para o próximo boot)
#   --root-password S    define a nova senha de root desta máquina (opcional; também lida de PHARUS_SENHA_ROOT).
#                        Prefira a variável: o argumento fica visível no histórico do shell e na lista de processos.
set -euo pipefail

URL_PADRAO="https://eventos.ifnmg.edu.br"
REPO_PADRAO="IFNMG-Almenara/PharusTerminal"

RENDER="software" IMPRESSORA_IP="" IMPRESSORA_USB=0 ROLO="29x90"
SENHA_ROOT="${PHARUS_SENHA_ROOT:-}" REPO="" HOST_URL="" CHAVE="${TERMINAL_REVERB_KEY:-}" IMPRESSORA="" SIM=0 INICIAR=1

erro() { printf '\033[31mErro:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[32m OK\033[0m %s\n' "$*"; }

ajuda() {
	cat <<'EOF'
Instala o kiosk Pharus Terminal nesta máquina (Debian 13 / DietPi).

  curl -fsSL https://raw.githubusercontent.com/IFNMG-Almenara/PharusTerminal/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/IFNMG-Almenara/PharusTerminal/main/install.sh | bash -s -- --reverb-key CHAVE --yes

Opções:
  --url URL            origem da API/front (padrão: https://eventos.ifnmg.edu.br)
  --reverb-key CHAVE   chave pública do app Reverb (REVERB_APP_KEY do backend; obrigatória)
  --printer NOME       impressora das etiquetas já cadastrada no CUPS (opcional)
  --printer-ip IP      instala o CUPS e cria a fila da Brother QL de rede (IPP) neste IP
  --printer-usb        idem, para a QL ligada por USB
  --roll TAMANHO       rolo da impressora (padrão 29x90; 29 ou 62 = fita contínua)
  --render MODO        software (padrão) ou hardware (GPU)
  --repo DONO/REPO     repositório dos Releases (padrão: IFNMG-Almenara/PharusTerminal)
  --yes, -y            não pergunta nada (usa os padrões)
  --sem-iniciar        não inicia o kiosk ao terminar
  --root-password S    nova senha de root (opcional; ou PHARUS_SENHA_ROOT=...)
EOF
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--url) HOST_URL="${2:?}"; shift 2 ;;
	--reverb-key) CHAVE="${2:?}"; shift 2 ;;
	--printer) IMPRESSORA="${2:?}"; shift 2 ;;
	--printer-ip) IMPRESSORA_IP="${2:?}"; shift 2 ;;
	--printer-usb) IMPRESSORA_USB=1; shift ;;
	--roll) ROLO="${2:?}"; shift 2 ;;
	--render) RENDER="${2:?}"; shift 2 ;;
	--repo) REPO="${2:?}"; shift 2 ;;
	--yes | -y) SIM=1; shift ;;
	--sem-iniciar) INICIAR=0; shift ;;
	--root-password) SENHA_ROOT="${2:?}"; shift 2 ;;
	-h | --help) ajuda ;;
	*) erro "opção desconhecida: $1 (use --help)" ;;
	esac
done

REPO="${REPO:-${TERMINAL_UPDATE_REPO:-$REPO_PADRAO}}"

# --- Checagens da máquina -------------------------------------------------------------------------------------------

[[ "$(id -u)" == 0 ]] || erro "execute como root (no DietPi já está; em Debian comum: sudo bash -c \"\$(curl -fsSL ...)\")."

[[ -r /etc/os-release ]] || erro "não foi possível identificar o sistema (/etc/os-release ausente)."
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == trixie ]] ||
	erro "Debian '${VERSION_CODENAME:-?}' não suportado: os pacotes publicados são para o Debian 13 (trixie), a versão atual do DietPi."

ARQ="$(dpkg --print-architecture 2>/dev/null || true)"
case "$ARQ" in
armhf) ROTULO="ARMv7 (armhf)" ;;
arm64) ROTULO="ARMv8 (arm64)" ;;
amd64) ROTULO="x86_64 (amd64)" ;;
*) erro "arquitetura '$ARQ' sem pacote publicado (suportadas: armhf = ARMv7, arm64 = ARMv8, amd64 = x86_64)." ;;
esac
DIETPI=0
[[ -e /boot/dietpi/.version ]] && DIETPI=1
MODELO=""
[[ -r /proc/device-tree/model ]] && MODELO="$(tr -d '\0' </proc/device-tree/model)"

info "Dispositivo: ${PRETTY_NAME:-Debian $VERSION_CODENAME} — $ROTULO$([[ $DIETPI == 1 ]] && echo ', DietPi')${MODELO:+ ($MODELO)}"

# --- Perguntas -------------------------------------------------------------------------------------------------------
# As respostas vêm do terminal físico (/dev/tty), não da entrada padrão: ela é o próprio script, recebido pelo `curl | bash`.

perguntar() { # variável, texto, padrão
	local -n destino=$1
	[[ -n "$destino" ]] && return 0
	local padrao="${3:-}" resposta
	if [[ $SIM -eq 1 || ! -r /dev/tty ]]; then
		destino="$padrao"
		return 0
	fi
	read -r -p "$2${padrao:+ [$padrao]}: " resposta </dev/tty
	destino="${resposta:-$padrao}"
}

perguntar HOST_URL "URL do Pharus" "$URL_PADRAO"
HOST_URL="${HOST_URL:-$URL_PADRAO}"
perguntar CHAVE "Chave do Reverb (REVERB_APP_KEY do backend)"
[[ -n "$CHAVE" ]] ||
	erro "informe a chave do Reverb (--reverb-key CHAVE, ou TERMINAL_REVERB_KEY=CHAVE antes do curl); sem ela o código de pareamento não aparece."
[[ "$RENDER" == software || "$RENDER" == hardware ]] || erro "--render deve ser software ou hardware."
perguntar IMPRESSORA "Impressora das etiquetas no CUPS (vazio = padrão do sistema)" ""

echo
echo "  Dispositivo: $ROTULO${DIETPI:+$([[ $DIETPI == 1 ]] && echo ', DietPi')}"
echo "  Pharus:      $HOST_URL"
echo "  Reverb:      ${CHAVE:0:4}…  (${#CHAVE} caracteres)"
echo "  Impressora:  ${IMPRESSORA:-padrão do sistema}"
echo "  Repositório: $REPO"
echo "  Autostart:   $([[ "$DIETPI" == 1 ]] && echo 'DietPi (dietpi-autostart 17, xinit)' || echo 'não é DietPi: só deixa os arquivos prontos')"
echo
if [[ $SIM -eq 0 && -r /dev/tty ]]; then
	read -r -p "Instalar? [S/n] " resp </dev/tty
	[[ "${resp:-s}" =~ ^[sSyY]$ ]] || erro "cancelado."
fi

# --- Download do Release mais recente --------------------------------------------------------------------------------

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "Preparando (curl, unzip)..."
apt-get update -qq || erro "apt-get update falhou; confira a conexão com a internet."
apt-get install -y -qq --no-install-recommends ca-certificates curl unzip

info "Consultando o último Release de $REPO..."
TAG_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")" ||
	erro "não encontrei nenhum Release em $REPO (ou sem acesso à internet)."
TAG="${TAG_URL##*/}"
[[ -n "$TAG" && "$TAG" != latest ]] || erro "não consegui identificar a tag do último Release de $REPO."

ZIP="pharus-terminal-$ARQ.zip"
BASE="https://github.com/$REPO/releases/download/$TAG"
info "Baixando $ZIP ($TAG)..."
curl -fsSL -o "$TMP/$ZIP" "$BASE/$ZIP" || erro "falha ao baixar $BASE/$ZIP (Release sem pacote para $ARQ?)."
curl -fsSL -o "$TMP/$ZIP.sha256" "$BASE/$ZIP.sha256" || erro "falha ao baixar o checksum de $ZIP."
(cd "$TMP" && sha256sum -c "$ZIP.sha256") || erro "SHA-256 de $ZIP não confere; pacote descartado."

PASTA="$TMP/pacote"
mkdir -p "$PASTA"
unzip -q "$TMP/$ZIP" -d "$PASTA"
info "Versão $(cat "$PASTA/VERSAO" 2>/dev/null || echo "$TAG") baixada e verificada."

# --- Dependências, binário e arquivos de apoio (lógica mantida em instalar.sh, dentro do pacote) ---------------------

(cd "$PASTA" && sh ./instalar.sh) || erro "a instalação falhou (veja as mensagens acima)."

# --- Configuração (só na primeira instalação / reconfiguração; a atualização automática nunca toca aqui) -------------

info "Gravando /etc/pharus-terminal.conf..."
{
	echo '# Configuração do kiosk (lida pelo xinitrc). Gerada por install.sh.'
	printf 'export TERMINAL_URL=%q\n' "$HOST_URL"
	printf 'export TERMINAL_REVERB_KEY=%q\n' "$CHAVE"
	[[ -n "$IMPRESSORA" ]] && printf 'export TERMINAL_PRINTER=%q\n' "$IMPRESSORA"
	[[ "$REPO" != "$REPO_PADRAO" ]] && printf 'export TERMINAL_UPDATE_REPO=%q\n' "$REPO"
	echo '# Renderização: software (CPU) ou hardware (GPU, tela física); troca com pharus-render.'
	printf 'export TERMINAL_RENDER=%q\n' "$RENDER"
	echo 'export QT_QPA_PLATFORM=xcb'
} >"$TMP/pharus-terminal.conf"
install -m 600 "$TMP/pharus-terminal.conf" /etc/pharus-terminal.conf

# --- Raspberry Pi: vídeo e decodificação por hardware ------------------------------------------------------------------

REINICIAR=0
CONFIG_PI=/boot/firmware/config.txt
[[ -e "$CONFIG_PI" ]] || CONFIG_PI=/boot/config.txt
if [[ -e /proc/device-tree/model ]] && grep -aq Raspberry /proc/device-tree/model && [[ -e "$CONFIG_PI" ]]; then
	if ! grep -Eq '^dtoverlay=vc4-(f)?kms-v3d' "$CONFIG_PI"; then
		info "habilitando o driver de vídeo do Raspberry Pi (vc4-kms-v3d)"
		printf '\n[all]\ndtoverlay=vc4-kms-v3d\nmax_framebuffers=2\n' >>"$CONFIG_PI"
		REINICIAR=1
	fi
	if grep -Eq '^gpu_mem(_[0-9]+)?=(16|32)$' "$CONFIG_PI"; then
		info "aumentando a memória da GPU para 128 MB (decodificação de vídeo por hardware)"
		sed -i -E 's/^(gpu_mem(_[0-9]+)?)=(16|32)$/\1=128/' "$CONFIG_PI"
		REINICIAR=1
	fi
fi
if [[ -e /proc/device-tree/model ]] && grep -aq Raspberry /proc/device-tree/model; then
	echo bcm2835-codec >/etc/modules-load.d/pharus-codec.conf
	modprobe bcm2835-codec 2>/dev/null || true
fi

# --- Autostart (só no DietPi) -------------------------------------------------------------------------------------
# O instalar.sh do pacote só copia o custom.sh se /var/lib/dietpi/dietpi-autostart já existir, o que não é o caso
# numa imagem nova (a pasta só aparece depois do primeiro uso do dietpi-autostart). Por isso instala aqui também,
# com -D (cria a pasta se faltar), antes de ligar o modo 17.

if [[ $DIETPI == 1 ]]; then
	info "ligando o autostart do DietPi (dietpi-autostart 17)"
	install -D -m 755 "$PASTA/dietpi/custom.sh" /var/lib/dietpi/dietpi-autostart/custom.sh
	/boot/dietpi/dietpi-autostart 17 >/dev/null
	# Imagem DietPi recém-gravada: dá a primeira execução (dietpi-update + dietpi-software) como concluída. Sem isso o
	# dietpi-login no tty1 abre o assistente antes do autostart e, onde o ICMP é bloqueado (ping 9.9.9.9 falha), ele
	# fica parado num menu de rede e o kiosk nunca abre. Também desliga as verificações de atualização do DietPi.
	[[ "$(cat /boot/dietpi/.install_stage 2>/dev/null || echo 0)" == 2 ]] || echo 2 >/boot/dietpi/.install_stage
	sed -i -E 's/^AUTO_SETUP_AUTOMATED=.*/AUTO_SETUP_AUTOMATED=1/; s/^(CONFIG_CHECK_(DIETPI|APT)_UPDATES)=.*/\1=0/' /boot/dietpi.txt
fi

# --- Senha de root (opcional) ------------------------------------------------------------------------------------------

if [[ -n "$SENHA_ROOT" ]]; then
	info "definindo a nova senha de root"
	printf 'root:%s\n' "$SENHA_ROOT" | chpasswd
fi

# --- Impressora --------------------------------------------------------------------------------------------------------

if [[ -n "$IMPRESSORA_IP" ]]; then
	info "Configurando a impressora de rede $IMPRESSORA_IP..."
	pharus-impressora rede "$IMPRESSORA_IP" --rolo "$ROLO" || info "Aviso: a fila da impressora não foi criada (veja acima); rode 'pharus-impressora' no dispositivo."
elif [[ $IMPRESSORA_USB -eq 1 ]]; then
	info "Configurando a impressora USB..."
	pharus-impressora usb --rolo "$ROLO" || info "Aviso: a fila da impressora não foi criada (veja acima); rode 'pharus-impressora' no dispositivo."
fi

ok "Kiosk instalado em /opt/pharus-terminal (config: /etc/pharus-terminal.conf)."
info "Para sair do kiosk no dispositivo: Ctrl+Alt+F3 (login), depois 'pharus-parar'. Para voltar: 'pharus-iniciar'."

if [[ $REINICIAR == 1 ]]; then
	echo "Reinicie o dispositivo para o driver de vídeo entrar em uso (reboot)."
	exit 0
fi

# --- Iniciar -------------------------------------------------------------------------------------------------------

if [[ $INICIAR -eq 1 && $DIETPI == 1 ]]; then
	iniciar=s
	if [[ $SIM -eq 0 && -r /dev/tty ]]; then
		read -r -p "Iniciar o kiosk agora (reinicia a sessão do console)? [S/n] " iniciar </dev/tty
	fi
	if [[ "${iniciar:-s}" =~ ^[sSyY]$ ]]; then
		info "Iniciando..."
		systemctl restart getty@tty1 || true
		for _ in $(seq 1 20); do
			if pgrep -x pharus-terminal >/dev/null; then
				ok "O kiosk está rodando. Ele abre na tela de pareamento com um código de 6 dígitos."
				exit 0
			fi
			sleep 2
		done
		erro "o kiosk não subiu. journalctl -b | tail; ou rode 'xinit /opt/pharus-terminal/xinitrc -- :0 vt7'."
	fi
fi
echo "Pronto. No próximo boot o kiosk abre sozinho."
