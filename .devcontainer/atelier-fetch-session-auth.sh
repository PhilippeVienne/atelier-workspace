#!/usr/bin/env bash
# Recupere le mot de passe de session (Basic Auth de ttyd/code-server)
# provisionne par le controller atelier et servi par net-proxy sur
# l'adresse link-local fixe du lien point-a-point TAP (169.254.0.1, voir
# crates/firecracker/src/network.rs et crates/net-proxy/src/metadata.rs
# dans le depot atelier).
#
# Reessaie pendant jusqu'a MAX_ATTEMPTS * SLEEP_SECONDS secondes : au boot,
# net-proxy (autre conteneur du meme pod) peut ne pas avoir encore termine
# son login Kubernetes-auth aupres d'OpenBao et donc repondre 503 tant
# qu'aucun cycle de rafraichissement n'a reussi.
#
# Imprime le mot de passe sur stdout (sans retour a la ligne) en cas de
# succes. En cas d'echec apres tous les essais (OpenBao non configure pour
# ce Workshop, net-proxy indisponible...), imprime un mot de passe local
# aleatoire connu de personne plutot que de laisser le service demarrer
# sans authentification — un shell/IDE inaccessible vaut mieux qu'un
# shell/IDE grand ouvert.
set -euo pipefail

METADATA_URL="http://169.254.0.1:3132/session-auth"
MAX_ATTEMPTS=30
SLEEP_SECONDS=2

for _ in $(seq 1 "$MAX_ATTEMPTS"); do
    password="$(curl -fsS --max-time 3 "$METADATA_URL" 2>/dev/null || true)"
    if [ -n "$password" ]; then
        printf '%s' "$password"
        exit 0
    fi
    sleep "$SLEEP_SECONDS"
done

# od plutot qu'openssl/xxd : toujours present (coreutils), evite d'ajouter
# une dependance au Dockerfile juste pour ce cas de repli.
od -An -tx1 -N16 /dev/urandom | tr -d ' \n'
