import 'strings.dart';

/// Italian.
class FlutwireStringsIt extends FlutwireStrings {
  /// Creates the Italian strings.
  const FlutwireStringsIt();

  @override
  String get channelName => 'Attività di rete';

  @override
  String get channelDescription =>
      'Un riepilogo delle chiamate HTTP fatte dall\'app.';

  @override
  String get notificationTitle => 'Registrazione attività di rete';

  @override
  String get clear => 'Cancella';

  @override
  String get shortcutLabel => 'Apri Flutwire';

  @override
  String summary({required int calls, required int failed}) {
    final base = calls == 1 ? '1 chiamata' : '$calls chiamate';
    if (failed == 0) return base;
    return failed == 1
        ? '$base · 1 non riuscita'
        : '$base · $failed non riuscite';
  }

  @override
  String get inspectorTitle => 'Attività di rete';

  @override
  String get close => 'Chiudi';

  @override
  String get cancel => 'Annulla';

  @override
  String get delete => 'Elimina';

  @override
  String get copy => 'Copia';

  @override
  String get copied => 'Copiato';

  @override
  String get share => 'Condividi';

  @override
  String get save => 'Salva';

  @override
  String get search => 'Cerca';

  @override
  String get settings => 'Impostazioni';

  @override
  String get pin => 'Fissa';

  @override
  String get unpin => 'Sblocca';

  @override
  String get searchHint => 'Cerca percorso, host, stato o corpo';

  @override
  String get filters => 'Filtri';

  @override
  String get filterSuccess => '2xx';

  @override
  String get filterRedirect => '3xx';

  @override
  String get filterClientError => '4xx';

  @override
  String get filterServerError => '5xx';

  @override
  String get filterFailed => 'Fallite';

  @override
  String get filterRunning => 'In corso';

  @override
  String get filterPinned => 'Fissate';

  @override
  String get filterOtherMethods => 'Altri';

  @override
  String get clearFilters => 'Azzera i filtri';

  @override
  String get sortNewest => 'Prima le più recenti';

  @override
  String get sortSlowest => 'Prima le più lente';

  @override
  String get sortLargest => 'Prima le più grandi';

  @override
  String get sortBy => 'Ordina per';

  @override
  String get statCalls => 'Chiamate';

  @override
  String get statFailed => 'Fallite';

  @override
  String get statAverage => 'Media';

  @override
  String get statTransferred => 'Trasferiti';

  @override
  String get emptyTitle => 'Ancora niente';

  @override
  String get emptyBody =>
      'Le chiamate che l\'app fa compaiono qui mentre avvengono, e nella notifica.';

  @override
  String get emptyFiltered => 'Nessuna chiamata corrisponde';

  @override
  String get pickACall => 'Scegli una chiamata per leggerla';

  @override
  String get recording => 'In registrazione';

  @override
  String get paused => 'In pausa';

  @override
  String get pauseRecording => 'Metti in pausa';

  @override
  String get resumeRecording => 'Riprendi la registrazione';

  @override
  String get exportAll => 'Esporta tutto';

  @override
  String get clearHistory => 'Svuota la cronologia';

  @override
  String get clearHistoryTitle => 'Svuotare la cronologia?';

  @override
  String clearHistoryBody(int calls) => calls == 1
      ? 'La chiamata registrata verrà eliminata. Quelle fissate restano.'
      : 'Le $calls chiamate registrate verranno eliminate. Quelle fissate restano.';

  @override
  String selected(int count) =>
      count == 1 ? '1 selezionata' : '$count selezionate';

  @override
  String get selectAll => 'Seleziona tutto';

  @override
  String get deleteSelectedTitle => 'Eliminare le chiamate selezionate?';

  @override
  String get running => 'In corso';

  @override
  String get cancelled => 'Annullata';

  @override
  String get failed => 'Fallita';

  @override
  String get tabOverview => 'Panoramica';

  @override
  String get tabRequest => 'Richiesta';

  @override
  String get tabResponse => 'Risposta';

  @override
  String get tabBody => 'Corpo';

  @override
  String get tabHeaders => 'Header';

  @override
  String get tabCookies => 'Cookie';

  @override
  String get url => 'URL';

  @override
  String get method => 'Metodo';

  @override
  String get status => 'Stato';

  @override
  String get source => 'Registrata da';

  @override
  String get remote => 'Server';

  @override
  String get certificate => 'Certificato';

  @override
  String get started => 'Inizio';

  @override
  String get duration => 'Durata';

  @override
  String get firstByte => 'Primo byte';

  @override
  String get requestSize => 'Dimensione richiesta';

  @override
  String get responseSize => 'Dimensione risposta';

  @override
  String get redirects => 'Reindirizzamenti';

  @override
  String get graphql => 'GraphQL';

  @override
  String get error => 'Errore';

  @override
  String get compression => 'Compressione';

  @override
  String get noHeaders => 'Nessun header';

  @override
  String get noCookies => 'Nessun cookie';

  @override
  String get redacted => 'Nascosto';

  @override
  String get noResponseYet => 'Ancora nessuna risposta';

  @override
  String get copyUrl => 'Copia l\'URL';

  @override
  String get copyCurl => 'Copia come cURL';

  @override
  String get shareAsText => 'Condividi come testo';

  @override
  String get shareAsCurl => 'Condividi come cURL';

  @override
  String get shareAsHar => 'Condividi come HAR';

  @override
  String get shareAsJson => 'Condividi come JSON';

  @override
  String get callGone => 'Questa chiamata non è più nella cronologia';

  @override
  String get notificationSetting => 'Notifica';

  @override
  String get notificationOn => 'Mostra le ultime chiamate nella tendina';

  @override
  String get notificationDenied =>
      'Le notifiche sono disattivate per questa app';

  @override
  String get notificationUnsupported => 'Questa piattaforma non ha la notifica';

  @override
  String get allowNotifications => 'Consenti le notifiche';

  @override
  String get openSystemSettings => 'Apri le impostazioni di sistema';

  @override
  String get appearanceSetting => 'Aspetto';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get retentionSetting => 'Conserva la cronologia per';

  @override
  String get retentionHour => '1 ora';

  @override
  String get retentionDay => '1 giorno';

  @override
  String get retentionWeek => '1 settimana';

  @override
  String get retentionForever => 'Per sempre';

  @override
  String get appliesOnRestart => 'Vale dal prossimo avvio dell\'app';

  @override
  String get about => 'Informazioni';

  @override
  String get bodyEmpty => 'Nessun corpo';

  @override
  String get bodyNotLoaded => 'Il corpo non si può leggere dalla cronologia';

  @override
  String bodyBinary(String size, String type) =>
      'Dati binari, $size${type.isEmpty ? '' : ', $type'}';

  @override
  String bodyTruncated(String kept, String total) =>
      'Mostra i primi $kept di $total';

  @override
  String bodyDecodedBy(String name) => 'Decodificato come $name';

  @override
  String get showRaw => 'Mostra grezzo';

  @override
  String get showDecoded => 'Mostra decodificato';

  @override
  String get viewTree => 'Albero';

  @override
  String get viewPretty => 'Formattato';

  @override
  String get viewRaw => 'Grezzo';

  @override
  String get viewHex => 'Hex';

  @override
  String get viewFields => 'Campi';

  @override
  String get viewParts => 'Parti';

  @override
  String get viewPreview => 'Anteprima';

  @override
  String get wrapLines => 'A capo automatico';

  @override
  String get lineNumbers => 'Numeri di riga';

  @override
  String get searchInBody => 'Cerca nel corpo';

  @override
  String get noMatches => 'Nessun risultato';

  @override
  String matchCounter(int index, int total) => '$index di $total';

  @override
  String get previousMatch => 'Risultato precedente';

  @override
  String get nextMatch => 'Risultato successivo';

  @override
  String get copyBody => 'Copia il corpo';

  @override
  String get copyFormatted => 'Copia formattato';

  @override
  String get copyRaw => 'Copia grezzo';

  @override
  String get saveBody => 'Salva il corpo in un file';

  @override
  String get expandAll => 'Espandi tutto';

  @override
  String get collapseAll => 'Comprimi tutto';

  @override
  String get copyValue => 'Copia il valore';

  @override
  String get copyPath => 'Copia il percorso';

  @override
  String itemsCount(int count) => count == 1 ? '1 elemento' : '$count elementi';

  @override
  String partsCount(int count) => count == 1 ? '1 parte' : '$count parti';

  @override
  String imageSize(int width, int height) => '$width × $height px';

  @override
  String get imageFailed => 'Non è stato possibile disegnare l\'immagine';

  @override
  String get filePart => 'File';

  @override
  String get showMore => 'Mostra di più';

  // Body viewer additions

  @override
  String get viewDecoded => 'Decodificato';

  @override
  String get showLess => 'Mostra meno';

  @override
  String matchCounterCapped(int index, int total) {
    final grouped = '$total'.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '$index di $grouped+';
  }

  @override
  String get saveFormatted => 'Salva formattato';

  @override
  String get moreActions => 'Altre azioni';
}
