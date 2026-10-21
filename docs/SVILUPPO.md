# Sviluppo

## Build

```sh
./scripts/build-app.sh            # firma con il certificato "Pasteroo Self-Signed"
SIGN_ID=- ./scripts/build-app.sh  # firma ad-hoc, se il certificato non c'è
open build/Pasteroo.app
```

Bastano i Command Line Tools (`xcode-select --install`), Xcode non serve.

## Test

```sh
swift test
```

I test usano XCTest, che arriva con Xcode: con i soli Command Line Tools non partono.
Girano comunque su GitHub a ogni push e prima di ogni release.

## Release

Gli aggiornamenti arrivano con [Sparkle 2](https://sparkle-project.org): l'app legge
`appcast.xml` dall'ultima release di GitHub.

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
l'altro, ma Gatekeeper non lo riconosce: per questo il primo avvio va autorizzato a mano.
