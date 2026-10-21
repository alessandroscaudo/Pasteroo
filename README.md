# Pasteroo

Clipboard manager per la barra dei menu di macOS (14+).

## Build

```sh
./scripts/build-app.sh            # firma con il certificato "Pasteroo Self-Signed"
SIGN_ID=- ./scripts/build-app.sh  # firma ad-hoc, se il certificato non c'è
open build/Pasteroo.app
```

Bastano i Command Line Tools (`xcode-select --install`), Xcode non serve.

## Release e aggiornamenti

Gli aggiornamenti arrivano con [Sparkle 2](https://sparkle-project.org): l'app legge
`appcast.xml` dall'ultima release di GitHub (voce di menu "Check for Updates…").

Per pubblicare una versione:

```sh
git tag v0.3.0 && git push origin v0.3.0
```

La GitHub Action `release.yml` compila, firma, genera l'appcast e crea la release.
Secrets richiesti dal repository:

- `SIGNING_P12`: il certificato autofirmato in base64 (`~/.config/pasteroo-signing/signing.p12`)
- `SIGNING_P12_PASSWORD`: la sua password (`~/.config/pasteroo-signing/p12-password.txt`)
- `SPARKLE_PRIVATE_KEY`: la chiave EdDSA (`generate_keys -x <file>`, dal Portachiavi login)

Il certificato autofirmato mantiene il permesso Accessibilità tra un aggiornamento e
l'altro. Gatekeeper però non lo riconosce: al primo avvio dopo il download si apre da
Impostazioni › Privacy e sicurezza › "Apri comunque". Gli aggiornamenti via Sparkle non
lo richiedono più.

## Funzioni

- Cronologia della clipboard (solo testo), con dedup e limite configurabile (max 9.999)
- Menu nella barra con gli ultimi N elementi, tasti 1–0 per sceglierli
- Pannello di ricerca con hotkey globale (default ⇧⌘V), frecce + Invio
- Incolla automatico (richiede il permesso Accessibilità)
- App ignorate (password manager preimpostati); il contenuto `org.nspasteboard.ConcealedType` viene sempre saltato
- Gestione della cronologia: ricerca, elimina selezionati o tutto, conferma opzionale
- Avvio al login, interruttore "Registra cronologia"

La cronologia è salvata in `~/Library/Application Support/Pasteroo/history.json`.
