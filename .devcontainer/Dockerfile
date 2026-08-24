# Devcontainer de demo pour atelier : docker (via la feature
# docker-in-docker, voir devcontainer.json), ministack (emulateur AWS local,
# https://github.com/ministackorg/ministack) et code-server (VS Code dans le
# navigateur, cf. docs/ARCHITECTURE.md "dashboard" — reference coder/code-server).
# Le CLI Claude Code est installe via la feature officielle
# ghcr.io/anthropics/devcontainer-features/claude-code, pas ici.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG CODE_SERVER_VERSION=4.133.0
ARG TTYD_VERSION=1.7.7

# systemd comme PID 1 : verifie reellement (voir docs/PROGRESS.md, section
# "boot Firecracker de l'agent") que sans ca, le noyau ne trouve aucun
# `/sbin/init`/`/etc/init`/`/bin/init` dans une image devcontainer standard
# et retombe sur un `/bin/sh` nu — rien ne demarre jamais tout seul.
# `postStartCommand` (devcontainer.json) est un concept du CLI
# `devcontainer`, jamais rejoue par le noyau : nos services sont donc
# demarres via une unite systemd (`atelier-demo.service`, plus bas), pas via
# `postStartCommand`.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        systemd systemd-sysv python3 python3-venv curl ca-certificates openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    # Unites qui ne servent a rien dans une microVM (pas de vrai materiel/
    # reseau ethernet a configurer par systemd-networkd, pas de getty sur
    # un vrai terminal) : masquees comme le fait tout guest minimal.
    && systemctl mask systemd-udevd.service systemd-udev-trigger.service \
        getty.target systemd-networkd.service systemd-resolved.service

# ministack dans un venv dedie (Ubuntu 24.04 refuse `pip install` sur le
# python systeme, PEP 668) ; on expose seulement son binaire dans le PATH.
RUN python3 -m venv /opt/ministack-venv \
    && /opt/ministack-venv/bin/pip install --no-cache-dir ministack \
    && ln -s /opt/ministack-venv/bin/ministack /usr/local/bin/ministack

# Paquet .deb officiel, version epinglee (pas de curl|sh) :
# https://github.com/coder/code-server/releases
RUN curl -fsSL -o /tmp/code-server.deb \
        "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb" \
    && apt-get install -y --no-install-recommends /tmp/code-server.deb \
    && rm -f /tmp/code-server.deb

# Terminal web (xterm.js embarque) pour un acces shell direct depuis le
# dashboard atelier (cf. crates/api-server/src/terminal.rs), sans passer par
# tout code-server — binaire statique officiel, version epinglee (pas de
# curl|sh) : https://github.com/tsl0922/ttyd/releases
RUN curl -fsSL -o /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
    && chmod +x /usr/local/bin/ttyd

# Recupere le mot de passe de session (Basic Auth ttyd/code-server,
# provisionne par le controller atelier dans OpenBao) aupres de net-proxy —
# voir ce script pour le detail. Utilise par les deux unites systemd
# ci-dessous, jamais par postStartCommand (pas de mise en veille/reseau
# atelier hors d'une vraie microVM Firecracker).
COPY atelier-fetch-session-auth.sh /usr/local/bin/atelier-fetch-session-auth.sh
RUN chmod +x /usr/local/bin/atelier-fetch-session-auth.sh

# Canal SSH dedie a l'execution de commandes distantes (exec_in_workshop,
# MCP — voir crates/api-server/src/exec.rs dans le depot atelier),
# separement de la session interactive `ttyd` : cle publique par Workshop
# recuperee au boot (voir ce script), jamais de mot de passe (voir
# atelier-sshd.conf).
COPY atelier-fetch-ssh-authorized-key.sh /usr/local/bin/atelier-fetch-ssh-authorized-key.sh
RUN chmod +x /usr/local/bin/atelier-fetch-ssh-authorized-key.sh
COPY atelier-sshd.conf /etc/ssh/sshd_config.d/atelier.conf

# Demarrage au boot via systemd (pas `postStartCommand`, jamais rejoue par
# le noyau — voir plus haut) : necessaire pour que ces services tournent
# reellement une fois ce devcontainer boote comme microVM Firecracker par
# `vm-supervisor`, pas seulement via le CLI `devcontainer`.
COPY atelier-ministack.service atelier-code-server.service atelier-terminal.service atelier-ssh-authorized-key.service /etc/systemd/system/
# `ssh.service` (paquet `openssh-server`) porte bien `WantedBy=multi-user.target`
# dans son unite, mais N'EST PAS active par defaut dans cette image de base
# (verifie empiriquement : `deb-systemd-helper` n'a pas cree le symlink —
# contrairement a l'hypothese initiale de ce commentaire, `systemctl` etant
# factice ici, voir plus bas) : le lien est donc ajoute explicitement,
# meme methode que nos propres unites juste en dessous.
RUN mkdir -p /etc/systemd/system/ssh.service.d
COPY atelier-ssh-service.conf /etc/systemd/system/ssh.service.d/atelier.conf
# `systemctl enable` ne fonctionne pas ici : cette image de base intercepte
# `systemctl` par un script factice ("systemd is not running in this
# container due to its overhead", constate en pratique) pour eviter des
# echecs de paquets .deb pendant un `docker build` classique. Les unites
# installees par des paquets (ex: docker.service, ssh.service) sont
# activees par `deb-systemd-helper` (appele par leurs scripts postinst),
# qui manipule directement les symlinks sans passer par ce faux
# `systemctl` — meme methode reprise ici a la main pour nos propres unites.
RUN mkdir -p /etc/systemd/system/multi-user.target.wants \
    && ln -s ../atelier-ministack.service /etc/systemd/system/multi-user.target.wants/atelier-ministack.service \
    && ln -s ../atelier-code-server.service /etc/systemd/system/multi-user.target.wants/atelier-code-server.service \
    && ln -s ../atelier-terminal.service /etc/systemd/system/multi-user.target.wants/atelier-terminal.service \
    && ln -s ../atelier-ssh-authorized-key.service /etc/systemd/system/multi-user.target.wants/atelier-ssh-authorized-key.service \
    && ln -s /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service

LABEL atelier.version="1.1.0"

RUN mkdir -p /workspaces/atelier-workspace \
    && echo "# Atelier Workspace" > /workspaces/atelier-workspace/README.md \
    && chown -R vscode:vscode /workspaces
WORKDIR /workspaces/atelier-workspace
