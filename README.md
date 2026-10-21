# Pasteroo

Clipboard manager per la barra dei menu di macOS. Ricorda tutto quello che copi e te lo
fa incollare di nuovo con un paio di tasti.

Richiede macOS 14 Sonoma o successivo, su Mac Apple Silicon o Intel.

## Funzioni

- **Cronologia della clipboard**: salva ogni testo che copi, senza duplicati, fino a
  9.999 elementi.
- **Menu nella barra**: gli ultimi elementi a portata di clic; i tasti 1–0 scelgono
  direttamente.
- **Pannello di ricerca**: si apre ovunque con ⇧⌘V (scorciatoia modificabile). Scrivi
  per filtrare, frecce per muoverti, Invio per incollare.
- **Incolla automatico**: l'elemento scelto finisce direttamente nell'app in cui stai
  scrivendo. Con ⌥Invio viene solo copiato.
- **Elementi fissati e rinominati**: ⌘P fissa in alto quello che usi spesso, ⌘R gli dà
  un nome.
- **Privacy**: le password copiate dai password manager non vengono mai registrate, e
  puoi escludere qualsiasi altra app. La registrazione si mette in pausa con un clic.
- **Gestione della cronologia**: cerca, elimina singoli elementi o tutto, con conferma
  opzionale.
- **Avvio al login** e **aggiornamenti automatici**.

La cronologia resta sul tuo Mac, in `~/Library/Application Support/Pasteroo/history.json`.
Niente viene inviato in rete.

## Scaricare e avviare

1. Scarica `Pasteroo-<versione>.zip` dall'[ultima release](https://github.com/alessandroscaudo/Pasteroo/releases/latest).
2. Apri lo zip e trascina **Pasteroo** nella cartella **Applicazioni**.
3. Apri Pasteroo. Al primo avvio macOS lo blocca, perché l'app non è firmata da uno
   sviluppatore registrato presso Apple:
   - chiudi l'avviso;
   - vai in **Impostazioni di Sistema › Privacy e sicurezza**, scorri in fondo e
     clicca **Apri comunque** accanto a Pasteroo;
   - conferma con la password.

   In alternativa, da Terminale:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Pasteroo.app
   ```

4. L'icona del canguro compare nella barra dei menu. Pasteroo non ha icona nel Dock.
5. Per l'incolla automatico, consenti a Pasteroo l'accesso in **Impostazioni di Sistema ›
   Privacy e sicurezza › Accessibilità**. macOS lo chiede la prima volta che serve. Senza
   questo permesso l'elemento scelto viene solo copiato e lo incolli tu con ⌘V.

Per farlo partire all'accensione del Mac, attiva l'avvio al login nelle impostazioni
dell'app (menu › **Settings…**).

## Aggiornare

Pasteroo controlla da solo se c'è una nuova versione e chiede se installarla. Per
controllare subito: menu › **Check for Updates…**.

Gli aggiornamenti non richiedono di ripetere i passaggi del primo avvio: il permesso
Accessibilità resta valido.

## Disinstallare

Esci da Pasteroo (menu › **Quit Pasteroo**), sposta l'app nel Cestino e, se vuoi
cancellare anche la cronologia, elimina la cartella
`~/Library/Application Support/Pasteroo`.

---

Vuoi compilarlo da te o pubblicare una release? Vedi [docs/SVILUPPO.md](docs/SVILUPPO.md).
