# PharusTerminal

Releases do kiosk de credenciamento **Pharus Terminal** (Qt 6 nativo) e instalador para Debian 13 (trixie) / DietPi,
nas arquiteturas **armhf** (Raspberry Pi 2), **arm64** (Raspberry Pi 3/4/5 em 64 bits) e **amd64**.

## Instalar

Execute no próprio dispositivo (console local ou SSH), como root:

```bash
curl -fsSL https://raw.githubusercontent.com/IFNMG-Almenara/PharusTerminal/main/install.sh | bash
```

O script detecta a arquitetura e a versão do Debian, baixa o Release mais recente daqui, confere o SHA-256, instala
as dependências, grava a configuração e liga o autostart (no DietPi). Pergunta a URL do Pharus (padrão
`https://eventos.ifnmg.edu.br`) e a chave do Reverb. Pode ser executado de novo para atualizar ou reconfigurar.

Sem perguntas (ex.: para automatizar a instalação de vários terminais):

```bash
curl -fsSL https://raw.githubusercontent.com/IFNMG-Almenara/PharusTerminal/main/install.sh | bash -s -- \
  --reverb-key <REVERB_APP_KEY> --yes
```

### Opções

| Opção | Padrão | Efeito |
|---|---|---|
| `--url URL` | `https://eventos.ifnmg.edu.br` | origem da API/front |
| `--reverb-key CHAVE` | (obrigatória) | chave pública do app Reverb do backend (`REVERB_APP_KEY`) |
| `--printer NOME` | impressora padrão do CUPS | impressora das etiquetas já cadastrada |
| `--printer-ip IP` | | instala o CUPS e cria a fila da Brother QL de rede (IPP) nesse IP |
| `--printer-usb` | | idem, para a QL ligada por USB |
| `--roll TAMANHO` | `29x90` | rolo da impressora (cortado: `LxA`; contínuo: só a largura, ex. `62`) |
| `--render MODO` | `software` | `software` (CPU) ou `hardware` (GPU); troca depois com `pharus-render` |
| `--repo DONO/REPO` | este repositório | de onde baixar o Release e para onde o kiosk olha na atualização automática |
| `--yes`, `-y` | | não pergunta nada (usa os padrões); ainda exige `--reverb-key` |
| `--sem-iniciar` | | não inicia o kiosk ao terminar (fica pronto para o próximo boot) |

A chave do Reverb identifica o app no servidor (como a "app key" do Pusher); não é segredo — o próprio site já a
expõe no JavaScript do navegador. O que precisa ficar privado é o `REVERB_APP_SECRET`, que fica só no backend e
nunca é usado aqui.

## Atualização automática

Instalado, o kiosk consulta o Release mais recente deste repositório ao iniciar e a cada 6 h, baixa e confere o
pacote da própria arquitetura e instala sozinho quando está parado na espera (pareamento, leitura ou desativado;
nunca durante um atendimento). A versão aparece no rodapé do kiosk.

## Suporte

Este repositório só guarda os binários publicados. Código-fonte, documentação completa (impressora, câmera, painel
de manutenção, etc.) e suporte ficam no repositório principal (privado) do projeto Pharus.
