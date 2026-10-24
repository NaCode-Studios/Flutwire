import '../coverage.dart' show FlutwireGap;
import '../model/message.dart' show FlutwireMessageKind;
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
  String get searchHint => 'Cerca URL, stato, header o corpo';

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
  String get searchingBodies => 'Cerco nei corpi';

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
  String get saveFailed => 'Impossibile condividere questo file';

  @override
  String get moreActions => 'Altre azioni';

  @override
  String get coverageBanner => 'Flutwire potrebbe non vedere alcune chiamate';

  @override
  String get coverageDetails => 'Dettagli';

  @override
  String get coverageTitle => 'Cosa Flutwire potrebbe non vedere';

  @override
  String coverageGapTitle(FlutwireGap gap) => switch (gap) {
    FlutwireGap.clientBypassesDartIo => 'Un client che non usa dart:io',
    FlutwireGap.captureReplaced => 'La cattura di dart:io è stata sostituita',
    FlutwireGap.otherIsolate => 'Una chiamata da un altro isolate',
  };

  @override
  String coverageGapWhat(FlutwireGap gap, String subject) => switch (gap) {
    FlutwireGap.clientBypassesDartIo =>
      '$subject ha fatto una chiamata che la cattura di dart:io non ha mai '
          "visto. L'adattatore si è fatto da parte, quindi la chiamata non è "
          "nell'elenco.",
    FlutwireGap.captureReplaced =>
      'Qualcosa ha impostato HttpOverrides.global senza passare da quello '
          'installato da Flutwire, quindi le chiamate di dart:io non vengono '
          'più registrate.',
    FlutwireGap.otherIsolate =>
      "$subject. In questo isolate non registra nessuno finché non si collega "
          "a Flutwire, quindi le sue chiamate non sono nell'elenco.",
  };

  @override
  String coverageGapFix(FlutwireGap gap) => switch (gap) {
    FlutwireGap.clientBypassesDartIo =>
      "Passa force: true all'adattatore, così registra lui la chiamata.",
    FlutwireGap.captureReplaced =>
      'Imposta i tuoi override prima di Flutwire.init, oppure costruiscili su '
          'HttpOverrides.current.',
    FlutwireGap.otherIsolate =>
      "Eseguilo con Flutwire.run o Flutwire.compute, oppure chiama "
          "Flutwire.attach() all'inizio dell'isolate.",
  };

  @override
  String coverageSeen(int count) =>
      count == 1 ? 'Visto una volta' : 'Visto $count volte';

  @override
  String get resend => 'Modifica e reinvia';

  @override
  String get send => 'Invia';

  @override
  String get sending => 'Invio in corso';

  @override
  String get addHeader => 'Aggiungi header';

  @override
  String get headerName => 'Nome';

  @override
  String get headerValue => 'Valore';

  @override
  String get removeHeader => 'Rimuovi header';

  @override
  String get hiddenValue => 'Nascosto';

  @override
  String resendTarget(String host) => 'Invia una richiesta vera a $host.';

  @override
  String resendHiddenNote(String names) =>
      'Non vengono inviati, perché Flutwire ne ha nascosto il valore quando '
      'ha registrato la chiamata: $names. Scrivi un valore per inviarlo.';

  @override
  String resendBodyCut(String kept, String total) =>
      "Il corpo è stato tagliato a $kept su $total. Qui c'è solo la parte "
      'iniziale.';

  @override
  String resendBinaryBody(String size) =>
      "Un corpo che non è testo, $size. Viene inviato com'è stato registrato.";

  @override
  String get resendBinaryCut =>
      'Del corpo è stata registrata solo una parte, quindi non viene inviato.';

  @override
  String get resendSendBody => 'Invia il corpo registrato';

  @override
  String resendBodyHidden(String mask) =>
      'Alcuni valori del corpo sono stati nascosti quando la chiamata è stata '
      'registrata e compaiono come $mask. Sostituiscili per inviare quelli '
      'veri.';

  @override
  String resendUrlHidden(String mask) =>
      "Un valore dell'indirizzo è stato nascosto quando la chiamata è stata "
      'registrata e compare come $mask. Sostituiscilo per inviare quello vero.';

  @override
  String get resendBadUrl =>
      'Scrivi un indirizzo completo, per esempio https://example.com/percorso.';

  @override
  String get resendNotRecorded =>
      'Inviata, ma Flutwire non è riuscito a registrarla.';

  @override
  String get resendFailed => 'Non è stato possibile inviare la richiesta.';

  @override
  String get resentFrom => 'Reinviata da';

  @override
  String get resentFromGone => 'Una chiamata che non è più nella cronologia';

  @override
  String get resentBadge => 'Reinviata';

  @override
  String get tabMessages => 'Messaggi';

  @override
  String get tabEvents => 'Eventi';

  @override
  String messageCount(int count) =>
      count == 1 ? '1 messaggio' : '$count messaggi';

  @override
  String eventCount(int count) => count == 1 ? '1 evento' : '$count eventi';

  @override
  String get messagesAll => 'Tutti';

  @override
  String get messagesSent => 'Inviati';

  @override
  String get messagesReceived => 'Ricevuti';

  @override
  String messagesDropped(int count) => count == 1
      ? 'Un messaggio precedente non è stato conservato.'
      : '$count messaggi precedenti non sono stati conservati.';

  @override
  String get messagesEmpty => 'Non è ancora passato niente';

  @override
  String messageKind(FlutwireMessageKind kind) => switch (kind) {
    FlutwireMessageKind.text => 'Testo',
    FlutwireMessageKind.binary => 'Binario',
    FlutwireMessageKind.ping => 'Ping',
    FlutwireMessageKind.pong => 'Pong',
    FlutwireMessageKind.close => 'Chiusura',
    FlutwireMessageKind.event => 'Evento',
  };

  @override
  String get messageNoPayload => 'Nessun contenuto';

  @override
  String get messageUndecoded =>
      'Questo messaggio era compresso e non è stato possibile decomprimerlo, '
      'quindi i byte sono mostrati così come sono arrivati.';

  @override
  String get compare => 'Confronta';

  @override
  String get compareSwap => 'Scambia i lati';

  @override
  String get compareDifferencesOnly => 'Solo differenze';

  @override
  String get compareIdentical => 'Uguali';

  @override
  String compareDifferences(int count) =>
      count == 1 ? '1 differenza' : '$count differenze';

  @override
  String get compareHost => 'Host';

  @override
  String get comparePath => 'Percorso';

  @override
  String get compareQuery => 'Parametri della query';

  @override
  String get compareRequestHeaders => 'Header della richiesta';

  @override
  String get compareResponseHeaders => 'Header della risposta';

  @override
  String get compareRequestBody => 'Corpo della richiesta';

  @override
  String get compareResponseBody => 'Corpo della risposta';

  @override
  String get compareMissing => 'Assente';

  @override
  String compareSkipped(int lines) =>
      lines == 1 ? '1 riga uguale' : '$lines righe uguali';

  @override
  String compareBinarySame(String size) => 'Stessi byte ($size)';

  @override
  String compareBinaryDiffer(String left, String right) =>
      'Byte diversi: $left contro $right';

  @override
  String compareCut(String side, String kept, String total) =>
      'Il lato $side è tagliato: mostrati $kept di $total.';

  @override
  String get compareWithOriginal => "Confronta con l'originale";

  @override
  String get statistics => 'Statistiche';

  @override
  String get statsSummary => 'Riepilogo';

  @override
  String get statsTimeline => 'Linea del tempo';

  @override
  String get statsErrorRate => 'Tasso di errore';

  @override
  String get statsMedian => 'Mediana';

  @override
  String get statsP95 => '95° percentile';

  @override
  String get statsSlowest => 'Chiamate più lente';

  @override
  String get statsHosts => 'Errori per host';

  @override
  String statsHostLine(int calls, int failed) =>
      '${calls == 1 ? '1 chiamata' : '$calls chiamate'}, '
      '${failed == 1 ? '1 fallita' : '$failed fallite'}';

  @override
  String statsMoreHosts(int count) => 'Altri $count host';

  @override
  String get statsNoHost => '(nessun host)';

  @override
  String statsPeak(int count) =>
      count <= 1 ? 'Una alla volta' : 'Fino a $count insieme';

  @override
  String statsShowingLatest(int shown, int total) =>
      'Le ultime $shown di $total chiamate';

  @override
  String get statsWaiting => 'Attesa';

  @override
  String get statsReceiving => 'Ricezione';

  @override
  String get dockInspector => "Aggancia accanto all'app";

  @override
  String get undockInspector => 'Apri a schermo intero';

  @override
  String get dockToBottom => 'Sposta in basso';

  @override
  String get dockToRight => 'Sposta a destra';

  @override
  String get dockResize => "Ridimensiona l'ispettore";

  @override
  String get interceptTitle => 'Mock e breakpoint';

  @override
  String get interceptOffBody =>
      "I mock e i breakpoint cambiano ciò che l'app invia e riceve, quindi "
      "restano spenti finché l'app non li accende.";

  @override
  String get interceptOffHow => 'Accendili quando parte Flutwire:';

  @override
  String get interceptUnavailableBody =>
      "Funzionano con la cattura di dart:io, e questa app non ce l'ha: gira "
      'sul web, oppure captureDartIo è spento.';

  @override
  String get interceptEmptyTitle => 'Ancora nessuna regola';

  @override
  String get interceptEmptyBody =>
      'Apri una chiamata e scegli "Simula questa risposta" o "Ferma le '
      'richieste come questa", oppure aggiungi una regola qui.';

  @override
  String get interceptNewMock => 'Nuovo mock';

  @override
  String get interceptNewBreakpoint => 'Nuovo breakpoint';

  @override
  String get interceptMock => 'Mock';

  @override
  String get interceptBreakpoint => 'Breakpoint';

  @override
  String interceptRulesActive(int count) =>
      count == 1 ? '1 regola attiva' : '$count regole attive';

  @override
  String get ruleDelete => 'Elimina la regola';

  @override
  String get ruleDeleteTitle => 'Eliminare questa regola?';

  @override
  String get ruleEditMock => 'Mock';

  @override
  String get ruleEditBreakpoint => 'Breakpoint';

  @override
  String get rulePattern => 'Indirizzo';

  @override
  String get rulePatternHelp =>
      'Usa * per una sequenza qualsiasi di caratteri, come in '
      'api.test/items/*. Senza schema vale per host e percorso.';

  @override
  String get rulePatternBad => "Scrivi come è fatto l'indirizzo.";

  @override
  String get ruleMethodAny => 'Qualsiasi metodo';

  @override
  String get ruleName => 'Nome (facoltativo)';

  @override
  String get ruleStatus => 'Codice di stato';

  @override
  String get ruleStatusBad => 'Uno stato è un numero da 100 a 599.';

  @override
  String get ruleDelay => 'Ritardo in millisecondi';

  @override
  String get ruleBodyNotText =>
      'Il corpo salvato non è testo, quindi viene servito come era stato '
      'registrato.';

  @override
  String get heldTitle => 'Richiesta trattenuta';

  @override
  String get heldNote =>
      "Questa richiesta è trattenuta a un breakpoint e l'app la sta "
      'aspettando. Cambia quello che vuoi e mandala avanti, oppure fermala.';

  @override
  String get heldStop => 'Ferma la richiesta';

  @override
  String get heldGone => 'Questa richiesta non è più trattenuta.';

  @override
  String heldBanner(int count) => count == 1
      ? '1 richiesta è trattenuta a un breakpoint'
      : '$count richieste sono trattenute a un breakpoint';

  @override
  String get heldReview => 'Controlla';

  @override
  String get mockThisResponse => 'Simula questa risposta';

  @override
  String get breakOnThis => 'Ferma le richieste come questa';

  @override
  String get badgeMocked => 'MOCK';

  @override
  String get badgeEdited => 'MODIFICATA';

  @override
  String get badgeHeld => 'TRATTENUTA';

  @override
  String get interceptFact => 'Intercettata';

  @override
  String get interceptedMocked =>
      'Risposta da una regola mock, non è stato inviato niente';

  @override
  String get interceptedEdited =>
      'Trattenuta a un breakpoint e inviata con modifiche';

  @override
  String get interceptedHeld => 'Trattenuta a un breakpoint';
}
