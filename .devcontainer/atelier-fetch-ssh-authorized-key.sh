#!/usr/bin/env bash
# Recupere la cle publique SSH autorisee pour ce Workshop et l'installe
# dans authorized_keys de l'utilisateur vscode avant que sshd ne demarre
# (voir ssh.service.d/atelier.conf : After=/Requires= ce service).
#
# Meme schema que atelier-fetch-session-auth.sh : la cle est generee par
# atelier-controller (une paire par Workshop, jamais reutilisee entre
# Workshops), stockee dans OpenBao, et servie par net-proxy sur l'adresse
# link-local fixe du lien point-a-point TAP (169.254.0.1, voir
# crates/firecracker/src/network.rs et crates/net-proxy/src/metadata.rs
# dans le depot atelier). Utilisee par crates/api-server/src/exec.rs (depot
# atelier) pour executer des commandes de facon fiable (exec_in_workshop,
# MCP) — un canal SSH separe du terminal interactif `ttyd`.
# Budget de retry : voir le commentaire equivalent dans
# atelier-fetch-session-auth.sh (~3 minutes constatees empiriquement pour
# que le lien TAP guest<->net-proxy devienne joignable dans un
# environnement de virtualisation imbriquee, largement au-dela de l'ancien
# budget de 60s).
set -euo pipefail

METADATA_URL="http://169.254.0.1:3132/ssh-authorized-key"
MAX_ATTEMPTS=150
SLEEP_SECONDS=2
SSH_DIR="/home/vscode/.ssh"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown vscode:vscode "$SSH_DIR"

for _ in $(seq 1 "$MAX_ATTEMPTS"); do
    key="$(curl -fsS --max-time 3 "$METADATA_URL" 2>/dev/null || true)"
    if [ -n "$key" ]; then
        printf '%s\n' "$key" > "$SSH_DIR/authorized_keys"
        chmod 600 "$SSH_DIR/authorized_keys"
        chown vscode:vscode "$SSH_DIR/authorized_keys"
        exit 0
    fi
    sleep "$SLEEP_SECONDS"
done

# Cle jamais recuperee (OpenBao non configure pour ce Workshop, net-proxy
# indisponible...) : authorized_keys reste absent -> sshd (PasswordAuthentication
# desactivee, voir sshd_config.d/atelier.conf) refusera alors toute
# connexion -> service inaccessible plutot qu'ouvert sans authentification.
# Sortie 0 quand meme : on ne bloque pas le demarrage de sshd pour autant.
echo "atelier-fetch-ssh-authorized-key: cle non recuperee apres $MAX_ATTEMPTS tentatives, sshd restera inaccessible" >&2
exit 0
