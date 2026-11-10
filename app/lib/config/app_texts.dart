/// Alle sichtbaren Texte der App an einer Stelle.
///
/// Zum Anpassen einfach den Text rechts vom Gleichheitszeichen ändern.
/// Texte mit Platzhaltern sind Funktionen, z. B. `T.remainingHashtags(12)`.
class T {
  T._();

  // --- Allgemein -------------------------------------------------------
  static const appName = 'Content-Hub';
  static const save = 'Speichern';
  static const cancel = 'Abbrechen';
  static const delete = 'Löschen';
  static const edit = 'Bearbeiten';
  static const add = 'Hinzufügen';
  static const close = 'Schließen';
  static const retry = 'Erneut versuchen';
  static const copy = 'Kopieren';
  static const share = 'Teilen';
  static const copied = 'In die Zwischenablage kopiert';
  static const open = 'Öffnen';
  static const done = 'Fertig';
  static const search = 'Suchen';
  static const all = 'Alle';
  static const none = 'Keine';
  static const noData = 'keine Daten';
  static const loading = 'Lädt …';
  static const refresh = 'Aktualisieren';
  static String dataAsOf(String when) => 'Stand: $when';
  static const dataNever = 'Stand: noch kein Abruf';

  // --- Fehler ----------------------------------------------------------
  static const errorTitle = 'Das hat nicht geklappt';
  static const errorNetwork = 'Der Server ist nicht erreichbar. Bitte Internetverbindung prüfen und erneut versuchen.';
  static const errorTimeout = 'Der Server antwortet nicht rechtzeitig. Bitte erneut versuchen.';
  static const errorNoBackend = 'Es ist noch kein Server eingetragen (BACKEND_URL). Siehe Anleitung im Projekt.';
  static const errorUnknown = 'Unerwarteter Fehler. Bitte erneut versuchen.';
  static const errorSession = 'Bitte erneut anmelden.';

  // --- Anmeldung -------------------------------------------------------
  static const loginTitle = 'Anmelden';
  static const registerTitle = 'Konto erstellen';
  static const loginIntro = 'Mehrere Instagram-Accounts, Statistiken, Trends und Ideen an einem Ort.';
  static const email = 'E-Mail';
  static const password = 'Passwort';
  static const passwordHint = 'Mindestens 10 Zeichen';
  static const name = 'Name';
  static const inviteCode = 'Einladungscode (optional)';
  static const inviteCodeHint = 'Nur ausfüllen, wenn du einem bestehenden Team beitrittst.';
  static const loginButton = 'Anmelden';
  static const registerButton = 'Konto erstellen';
  static const toRegister = 'Noch kein Konto? Konto erstellen';
  static const toLogin = 'Schon ein Konto? Anmelden';
  static const consentRegister =
      'Mit dem Erstellen des Kontos stimmst du zu, dass Content-Hub deine Angaben und die Daten verbundener Instagram-Accounts verarbeitet, um die Funktionen der App bereitzustellen. Details stehen unter Mehr → Datenschutz.';
  static const fieldRequired = 'Bitte ausfüllen';
  static const emailInvalid = 'Bitte eine gültige E-Mail-Adresse eingeben';
  static const passwordTooShort = 'Mindestens 10 Zeichen';

  // --- Navigation ------------------------------------------------------
  static const tabToday = 'Heute';
  static const tabStats = 'Statistiken';
  static const tabTrends = 'Trends';
  static const tabPlan = 'Planen';
  static const tabMore = 'Mehr';

  // --- Account-Umschalter ----------------------------------------------
  static const allAccounts = 'Alle Accounts';
  static const switchAccount = 'Account wählen';
  static const allAccountsHint = 'Übersicht über alle Accounts';
  static const noAccountsYet = 'Noch kein Account angelegt';
  static const statusConnected = 'Verbunden';
  static const statusSyncing = 'Synchronisiert gerade';
  static const statusDisconnected = 'Getrennt – neu verbinden nötig';
  static const statusManual = 'Manuell geführt, ohne Statistiken';
  static String statusExpiring(int days) =>
      days <= 0 ? 'Verbindung läuft heute ab' : 'Verbindung läuft in $days ${days == 1 ? 'Tag' : 'Tagen'} ab';
  static const statusExpiringSoon = 'Verbindung läuft bald ab';

  // --- Heute -----------------------------------------------------------
  static const todayAccounts = 'Letzte 7 Tage';
  static const todayNoAccounts = 'Verbinde deinen ersten Instagram-Account, um Statistiken zu sehen.';
  static const todayConnectButton = 'Account verbinden';
  static const todayStandout = 'Auffälligster Beitrag der Woche';
  static const todayNoStandout = 'In den letzten 7 Tagen gibt es keinen Beitrag mit Reichweiten-Daten.';
  static String standoutFactor(String factor) => '$factor× der üblichen Reichweite dieses Accounts';
  static const todayTrends = 'Neue Trends';
  static const todayNoTrends =
      'Noch keine Trends. Trends kommen aus deinen Quellen: eigene Beobachtungen, RSS-Feeds und beobachtete Hashtags.';
  static const todayInProgress = 'Ideen in Arbeit';
  static const todayNoInProgress = 'Gerade ist keine Idee in Arbeit.';
  static const todayWarnings = 'Hinweise';
  static String warnDisconnected(String handle) => '@$handle: Verbindung getrennt. Bitte neu verbinden.';
  static String warnExpiring(String handle) => '@$handle: Verbindung läuft bald ab.';
  static String warnStale(String handle, String when) => '@$handle: Daten veraltet (Stand $when).';
  static String warnNeverSynced(String handle) => '@$handle: Daten wurden noch nicht synchronisiert.';
  static String unansweredComments(int n) => n == 1 ? '1 unbeantworteter Kommentar' : '$n unbeantwortete Kommentare';
  static const notifications = 'Benachrichtigungen';
  static const noNotifications = 'Keine Benachrichtigungen.';
  static const pushNote =
      'Benachrichtigungen erscheinen hier in der App. Push-Nachrichten aufs Gerät brauchen einen Push-Dienst und sind noch nicht eingerichtet.';

  // --- Kennzahlen ------------------------------------------------------
  static const reach = 'Reichweite';
  static const views = 'Aufrufe';
  static const interactions = 'Interaktionen';
  static const likes = 'Likes';
  static const comments = 'Kommentare';
  static const shares = 'Shares';
  static const saves = 'Speicherungen';
  static const follows = 'Follows';
  static const unfollows = 'Unfollows';
  static const followers = 'Follower';
  static const followerBalance = 'Follower-Saldo';
  static const avgWatchTime = 'Ø Wiedergabedauer';
  static const vsPrevWeek = 'zur Vorwoche';
  static const vsPrevPeriod = 'zum Zeitraum davor';
  static const replies = 'Antworten';
  static const navigation = 'Navigation';
  static const profileVisits = 'Profilbesuche';
  static const posts = 'Beiträge';

  // --- Statistiken -----------------------------------------------------
  static String periodDays(int days) => '$days Tage';
  static const statsChart = 'Verlauf';
  static const statsFollowerChart = 'Follower-Entwicklung';
  static const followerHistoryNote = 'Der Follower-Verlauf entsteht aus täglichen eigenen Snapshots und beginnt am Tag der Verbindung.';
  static const statsPosts = 'Beiträge';
  static const statsNoPosts = 'In diesem Zeitraum gibt es keine Beiträge.';
  static const sortBy = 'Sortieren nach';
  static const statsCompare = 'Vergleich aller Accounts';
  static const statsNoAccounts = 'Noch kein Account vorhanden. Unter Mehr → Accounts kannst du einen verbinden.';
  static const statsNotEnoughPoints = 'Noch zu wenige Tageswerte für einen Verlauf.';
  static const competitors = 'Wettbewerber';
  static const storyStats = 'Story-Statistik';
  static const whyMissing = 'Warum fehlen Werte?';
  static const storyOnly24h = 'Instagram stellt Story-Statistiken nur 24 Stunden bereit. Die App sichert sie alle 4 Stunden.';

  // --- Beitragsdetail --------------------------------------------------
  static const mediaDetail = 'Beitrag';
  static const followUpIdea = 'Folgeidee anlegen';
  static const openOnInstagram = 'Auf Instagram öffnen';
  static const vsMedian = 'Vergleich zum Account-Median';
  static const medianNote = 'Der Median ist der mittlere Wert aller synchronisierten Beiträge dieses Accounts.';
  static String medianValue(String v) => 'Median $v';
  static const carouselNote = 'Für einzelne Bilder innerhalb eines Karussells liefert Instagram keine Werte.';
  static const formatReel = 'Reel';
  static const formatCarousel = 'Karussell';
  static const formatImage = 'Einzelbild';
  static const formatStory = 'Story';
  static const formatPost = 'Post';
  static const formatVideo = 'Video';
  static String followUpTitle(String caption) => 'Folgeidee zu: $caption';

  // --- Story-Statistik -------------------------------------------------
  static const storiesEmpty = 'Noch keine Stories gesichert. Sobald eine Story läuft, sichert die App ihre Werte automatisch.';
  static String lastSaved(String when) => 'Letzte Sicherung: $when';
  static const storyNotSavedInTime = 'Nicht rechtzeitig gesichert: Die letzten Werte vor Ablauf fehlen.';
  static const storyNoValues = 'Keine Werte gesichert (unter 5 Betrachtern liefert Instagram keine Zahlen).';
  static const storyLive = 'Läuft gerade';

  // --- Wettbewerber ----------------------------------------------------
  static const competitorsIntro = 'Öffentliche Kennzahlen anderer professioneller Accounts. Der Verlauf entsteht aus täglichen Snapshots.';
  static const competitorAdd = 'Wettbewerber hinzufügen';
  static const competitorUsername = 'Benutzername';
  static const competitorsEmpty = 'Noch keine Wettbewerber. Füge den Benutzernamen eines professionellen Accounts hinzu.';
  static String competitorCount(int n, int max) => '$n von $max Wettbewerbern';
  static const avgLikes = 'Ø Likes';
  static const avgComments = 'Ø Kommentare';
  static const needsAccount = 'Bitte oben einen einzelnen Account wählen.';
  static const needsFacebookTitle = 'Nur mit Facebook Login';
  static const needsFacebook =
      'Diese Funktion gibt es nur für Accounts, die über Facebook Login mit einer Facebook-Seite verbunden sind.\n\nSo geht es: Instagram-Account in der Instagram-App mit einer Facebook-Seite verknüpfen, dann unter Mehr → Accounts „Neu verbinden“ und „Facebook Login“ wählen.';
  static const featureOffTitle = 'Noch nicht freigeschaltet';
  static const featureOff = 'Diese Funktion braucht eine Freigabe von Meta (App Review) und ist noch nicht aktiviert.';
  static const snapshotNone = 'Noch kein Snapshot';

  // --- Trends ----------------------------------------------------------
  static const trendsEmpty =
      'Für diese Auswahl gibt es keine Trends. Instagram bietet keine Schnittstelle für Trends; die App zeigt nur Signale aus deinen Quellen: eigene Beobachtungen, RSS-Feeds und beobachtete Hashtags.';
  static const trendsNoNiches = 'Lege zuerst eine Nische an (Mehr → Nischen), damit Trends zugeordnet werden können.';
  static const trendAdd = 'Beobachtung erfassen';
  static const trendTitle = 'Titel';
  static const trendReason = 'Begründung (Warum ist das ein Trend?)';
  static const trendSummary = 'Beschreibung (optional)';
  static const trendLink = 'Link zur Quelle (optional)';
  static const trendNiches = 'Nischen';
  static const freshnessFresh = 'aktuell';
  static const freshnessOlder = 'älter';
  static const freshnessStale = 'veraltet';
  static const filterSource = 'Quelle';
  static const filterPeriod = 'Zeitraum';
  static const periodAll = 'Gesamt';
  static const period7 = '7 Tage';
  static const period30 = '30 Tage';
  static const trendDetail = 'Trend';
  static const trendSource = 'Quelle';
  static const trendPublished = 'Veröffentlicht';
  static const trendFetched = 'Abgerufen';
  static const trendSignal = 'Kennzahl der Quelle';
  static const trendOpenSource = 'Quelle öffnen';
  static const trendNoLink = 'Kein Link hinterlegt';
  static const saveAsIdea = 'Als Idee speichern';
  static const savedAsIdea = 'Als Idee gespeichert';
  static const watchedHashtags = 'Beobachtete Hashtags';
  static const sources = 'Quellen';
  static const sourcesTitle = 'Trendquellen';
  static const sourceAddRss = 'RSS-Feed hinzufügen';
  static const sourceName = 'Name der Quelle';
  static const sourceUrl = 'Feed-Adresse (https://…)';
  static const sourceNiche = 'Nische';
  static const sourcesEmpty = 'Noch keine RSS-Feeds. Lege je Nische 3 bis 5 Feeds von Fachmedien an.';
  static String sourceLastSuccess(String name, String when) => '$name: letzter erfolgreicher Abruf $when';
  static String sourceNeverSucceeded(String name) => '$name: noch kein erfolgreicher Abruf';
  static String sourceError(String error) => 'Fehler: $error';
  static const sourceRssNote = 'Feeds werden stündlich geprüft. Enthält die Nische Schlüsselbegriffe, erscheinen nur passende Einträge.';
  static const googleTrendsNote =
      'Google Trends ist nicht angebunden: Ein offizieller API-Zugang ist nicht gesichert. Beobachtungen von der Google-Trends-Website kannst du als eigene Beobachtung mit Link erfassen.';
  static const sourceManual = 'Eigene Beobachtung';

  // --- Hashtags --------------------------------------------------------
  static String remainingHashtags(int remaining, int quota) => 'Noch $remaining von $quota Hashtags in 7 Tagen';
  static const hashtagAdd = 'Hashtag beobachten';
  static const hashtagField = 'Hashtag';
  static const hashtagsEmpty =
      'Noch keine Hashtags. Jeder neue Hashtag zählt 7 Tage lang auf das Kontingent, auch wenn du ihn wieder entfernst.';
  static const hashtagQuotaWarning = 'Jeder neue Hashtag zählt 7 Tage lang auf das Kontingent von Instagram.';
  static const hashtagTop = 'Top-Beitrag';
  static const hashtagRecent = 'Aktueller Beitrag';
  static const adoptTrend = 'Als Trend übernehmen';
  static const adopted = 'In den Trends';
  static const hashtagNoPosts = 'Zu diesem Hashtag wurden noch keine Beiträge abgerufen.';

  // --- Planen: Ideen ---------------------------------------------------
  static const ideas = 'Ideen';
  static const calendar = 'Kalender';
  static const viewList = 'Liste';
  static const viewBoard = 'Kanban';
  static const ideasEmpty = 'Noch keine Ideen. Mit dem Plus-Button hältst du die erste fest.';
  static const ideasNoMatch = 'Keine Idee passt zu Suche und Filtern.';
  static const searchIdeas = 'Ideen durchsuchen';
  static const filters = 'Filter';
  static const filterReset = 'Filter zurücksetzen';
  static const sortUpdated = 'Zuletzt bearbeitet';
  static const sortPlanned = 'Geplant für';
  static const statusIdea = 'Idee';
  static const statusInProgress = 'In Arbeit';
  static const statusReady = 'Bereit';
  static const statusPublished = 'Veröffentlicht';
  static const statusDiscarded = 'Verworfen';
  static const quickIdea = 'Schnell-Idee';
  static const ideaTitle = 'Titel';
  static const ideaNote = 'Notiz';
  static const ideaTitleOrNote = 'Bitte Titel oder Notiz eingeben';
  static const account = 'Account';
  static const noAccount = 'Kein Account';
  static const niche = 'Nische';
  static const noNiche = 'Keine Nische';
  static const format = 'Format';
  static const noFormat = 'Offen';
  static const status = 'Status';
  static const tags = 'Tags';
  static const tagsHint = 'Mit Komma trennen';
  static const plannedFor = 'Wunschtermin';
  static const noDate = 'Kein Termin';
  static const assignee = 'Zuständig';
  static const nobody = 'Niemand';
  static const ideaSaved = 'Idee gespeichert';
  static const ideaDeleteConfirm = 'Diese Idee mit allen Vorschlägen und Anhängen löschen?';
  static const boardDragHint = 'Karte gedrückt halten und in eine andere Spalte ziehen, um den Status zu ändern.';
  static const columnEmpty = 'Leer';

  // --- Ideendetail -----------------------------------------------------
  static const ideaDetail = 'Idee';
  static const attachments = 'Anhänge';
  static const attachPhoto = 'Foto';
  static const attachVoice = 'Sprachnotiz';
  static const attachLink = 'Link';
  static const attachStop = 'Aufnahme beenden';
  static const recording = 'Aufnahme läuft …';
  static const micDenied = 'Kein Zugriff auf das Mikrofon. Bitte in den Einstellungen erlauben.';
  static const linkField = 'Link (https://…)';
  static const voiceNote = 'Sprachnotiz';
  static const play = 'Abspielen';
  static const stop = 'Stopp';
  static const shareMenuNote =
      'Direktes Teilen aus anderen Apps in Content-Hub gibt es erst in der iPhone-App. Bis dahin Links hier einfügen.';
  static const origin = 'Quelle';
  static String originTrend(String title) => 'Trend: $title';
  static String originMedia(String caption) => 'Beitrag: $caption';
  static const suggestion = 'Umsetzungsvorschlag';
  static const suggest = 'Umsetzung vorschlagen';
  static const suggesting = 'Vorschlag wird erstellt …';
  static const suggestIntro =
      'Die KI schlägt Format, 3 Hooks, Gliederung, Call-to-Action, Caption und Hashtags vor. Grundlage sind Idee, Nische, Account-Profil, verknüpfter Trend und deine 5 besten Beiträge.';
  static const aiNotice = 'KI-Vorschlag. Bitte Fakten prüfen.';
  static const regenerateAll = 'Alles neu erzeugen';
  static const regenerate = 'Neu erzeugen';
  static const formatRecommendation = 'Formatempfehlung';
  static const hooks = 'Hooks';
  static const outline = 'Gliederung';
  static const cta = 'Call-to-Action';
  static const caption = 'Caption-Entwurf';
  static const hashtags = 'Hashtags';
  static const versions = 'Versionen';
  static String version(int n) => 'Version $n';
  static const versionActive = 'aktiv';
  static const useVersion = 'Diese Version verwenden';
  static const onePerLine = 'Ein Eintrag pro Zeile';
  static const hashtagsHint = 'Höchstens 5, durch Leerzeichen getrennt';
  static const copyCaption = 'Caption kopieren';
  static const copyAll = 'Ganzen Vorschlag kopieren';
  static const publish = 'Veröffentlichen';
  static const planInCalendar = 'Im Kalender einplanen';
  static const markReady = 'Als „Bereit“ markieren';
  static const linkedPost = 'Veröffentlichter Beitrag';
  static const scheduledEntries = 'Kalendereinträge';

  // --- Veröffentlichen -------------------------------------------------
  static const publishTitle = 'Veröffentlichen';
  static const publishNeedsAccount = 'Ordne der Idee zuerst einen Account zu.';
  static const publishNoConnection =
      'Dieser Account ist nicht mit Instagram verbunden. Du kannst einen Termin als reine Planung speichern und die Caption kopieren.';
  static const publishFormat = 'Format';
  static const publishMedia = 'Medien';
  static const addImage = 'Bild hinzufügen';
  static const addVideo = 'Video hinzufügen';
  static const publishCaption = 'Caption';
  static const publishWhen = 'Zeitpunkt';
  static const publishNow = 'Jetzt';
  static const publishSchedule = 'Termin';
  static const publishPlanOnly = 'Nur planen';
  static const pickDate = 'Termin wählen';
  static const publishNowButton = 'Jetzt veröffentlichen';
  static const publishScheduleButton = 'Termin speichern';
  static const publishPlanButton = 'Planung speichern';
  static const publishPlanOnlyNote = 'Reine Planung: Es wird nichts automatisch veröffentlicht.';
  static const publishServerNote = 'Zum Termin veröffentlicht der Server, dein Gerät muss dafür nicht an sein.';
  static const precheck = 'Vorab-Prüfung';
  static const precheckOk = 'Format passt.';
  static String limitRemaining(int remaining, int limit) => 'Tageslimit: noch $remaining von $limit Veröffentlichungen in 24 Stunden';
  static String limitUnknown(int used) => 'Tageslimit von Instagram nicht abrufbar. Über die App in 24 Stunden veröffentlicht: $used';
  static const limitReached = 'Das Tageslimit dieses Accounts ist erreicht.';
  static const uploading = 'Medien werden hochgeladen …';
  static const publishing = 'Wird veröffentlicht …';
  static const publishSuccess = 'Veröffentlicht';
  static const publishScheduled = 'Termin gespeichert';
  static const publishFailed = 'Veröffentlichung fehlgeschlagen';
  static const publishStillRunning = 'Instagram verarbeitet den Beitrag noch. Den Stand siehst du im Kalender.';
  static const viewPost = 'Beitrag ansehen';
  static const rulesPost = 'Post: genau 1 Bild im Format JPEG.';
  static const rulesReel = 'Reel: genau 1 Video (MP4 oder MOV).';
  static String rulesCarousel(int max) => 'Karussell: 2 bis $max Bilder (JPEG) oder Videos.';
  static const storiesNotPublished = 'Stories werden nicht veröffentlicht, nur ausgewertet.';

  // --- Kalender --------------------------------------------------------
  static const calMonth = 'Monat';
  static const calWeek = 'Woche';
  static const calList = 'Liste';
  static const calEmpty = 'Keine Termine in diesem Zeitraum.';
  static const calDragHint = 'Eintrag gedrückt halten und auf einen anderen Tag ziehen, um ihn zu verschieben.';
  static const postDraft = 'Geplant (nur Planung)';
  static const postScheduled = 'Geplant';
  static const postPublishing = 'Wird veröffentlicht';
  static const postPublished = 'Veröffentlicht';
  static const postFailed = 'Fehlgeschlagen';
  static const postRetry = 'Wiederholen';
  static const postDeleteConfirm = 'Diesen Kalendereintrag löschen?';
  static const postMoved = 'Termin verschoben';
  static const postReason = 'Grund';
  static const postOpenIdea = 'Idee öffnen';
  static const postChangeDate = 'Termin ändern';
  static const today = 'Heute';
  static const limitsTitle = 'Verbleibendes Tageslimit';
  static const untitled = 'Ohne Titel';

  // --- Mehr ------------------------------------------------------------
  static const moreAccounts = 'Accounts';
  static const moreAccountsSub = 'Verbinden, Farbe, Nischen, Tonalität';
  static const moreComments = 'Kommentare';
  static const moreCommentsSub = 'Eingang aller Accounts';
  static const moreNiches = 'Nischen';
  static const moreNichesSub = 'Themenfelder und Schlüsselbegriffe';
  static const moreTeam = 'Team und Workspace';
  static const moreTeamSub = 'Mitglieder einladen, Rollen';
  static const morePrivacy = 'Datenschutz und Konto';
  static const morePrivacySub = 'Datenexport, Konto löschen, Abmelden';

  // --- Accounts --------------------------------------------------------
  static const accountsTitle = 'Accounts';
  static const accountsEmpty = 'Noch kein Account. Verbinde einen Business- oder Creator-Account oder lege einen manuellen Account an.';
  static const connectAccount = 'Account verbinden';
  static const reconnect = 'Neu verbinden';
  static const disconnect = 'Trennen und Daten löschen';
  static const syncNow = 'Jetzt synchronisieren';
  static const addManual = 'Manuellen Account anlegen';
  static const manualUsername = 'Instagram-Benutzername';
  static const manualNote = 'Manuelle Accounts haben keine Statistiken. Sinnvoll für private Konten oder zum Planen.';
  static String lastSync(String when) => 'Letzte Synchronisation: $when';
  static const neverSynced = 'Noch nicht synchronisiert';
  static const connectInfoTitle = 'Instagram-Account verbinden';
  static const connectInfo =
      '• Nur Business- oder Creator-Accounts können verbunden werden.\n'
      '• Die App liest Profil, Beiträge, Statistiken und Kommentare dieses Accounts.\n'
      '• Es wird nichts ohne deine Zustimmung gepostet. Jede Veröffentlichung und jede Antwort löst du selbst aus.\n'
      '• Die Anmeldung läuft in einem Browser-Fenster bei Instagram. Dein Passwort sieht die App nie.';
  static const privateAccountHelp =
      'Privates Konto? In der Instagram-App unter Einstellungen → Kontotyp und Tools auf ein professionelles Konto umstellen. Alternativ hier als manuellen Account ohne Statistiken anlegen.';
  static const otherAccountHint =
      'Anderen Account verwenden: Ist im Browser-Fenster noch ein anderer Instagram-Account angemeldet, dort zuerst abmelden und dann den gewünschten Account anmelden.';
  static const loginInstagram = 'Instagram Login';
  static const loginInstagramSub = 'Standard. Keine Facebook-Seite nötig.';
  static const loginFacebook = 'Facebook Login';
  static const loginMeta = 'Meta Login';
  static const loginMetaSub = 'Empfohlen. Über dein Facebook-Konto, keine Facebook-Seite nötig.';
  static const loginFacebookSub = 'Für Hashtags und Wettbewerber. Braucht eine verknüpfte Facebook-Seite.';
  static const notConfiguredTitle = 'Auf dem Server noch nicht eingerichtet';
  static const instagramNotConfigured =
      'Für diesen Login ist auf dem Server noch keine Meta-App hinterlegt. Die Schritte stehen in der Anleitung (README, Abschnitt „Meta-App“).';
  static const connecting = 'Warte auf die Anmeldung bei Instagram …';
  static const connectCancelled = 'Die Anmeldung wurde abgebrochen.';
  static String connectSuccess(String handle) => '@$handle ist verbunden. Die erste Synchronisation läuft.';
  static const connectedSetup = 'Account einrichten';
  static const accountColor = 'Farbe';
  static const accountNiches = 'Nischen';
  static const primaryNiche = 'Hauptnische';
  static const tone = 'Tonalität';
  static const toneHint = 'z. B. locker, fachkundig, per Du';
  static const audience = 'Zielgruppe';
  static const audienceHint = 'Wen soll der Account erreichen?';
  static const language = 'Sprache der Inhalte';
  static const accountTypeBusiness = 'Business';
  static const accountTypeCreator = 'Creator';
  static const accountTypeManual = 'Manuell';
  static const disconnectTitle = 'Account trennen';
  static const disconnectText =
      'Token, Statistiken, Beiträge, Kommentare, Wettbewerber, Hashtags und Kalendereinträge dieses Accounts werden gelöscht. Das lässt sich nicht rückgängig machen.';
  static const disconnectKeepIdeas = 'Ideen behalten (ohne Account-Zuordnung)';
  static const disconnectDeleteIdeas = 'Auch die Ideen dieses Accounts löschen';
  static const ownerOnly = 'Nur die Owner-Rolle kann Accounts verbinden und trennen.';
  static const syncDone = 'Synchronisation abgeschlossen';
  static String accountLimit(int max) => 'Es sind höchstens $max Accounts möglich.';
  static const loginTypeInstagram = 'über Instagram Login';
  static const loginTypeFacebook = 'über Facebook Login';

  // --- Kommentare ------------------------------------------------------
  static const commentsTitle = 'Kommentare';
  static const commentsNew = 'Neu';
  static const commentsUnanswered = 'Unbeantwortet';
  static const commentsEmpty = 'Keine Kommentare. Neue Kommentare erscheinen nach der nächsten Synchronisation.';
  static const commentsEmptyUnanswered = 'Alles beantwortet.';
  static const reply = 'Antworten';
  static const replyHint = 'Antwort schreiben';
  static const replySend = 'Antwort senden';
  static const replySent = 'Antwort gesendet';
  static const hide = 'Ausblenden';
  static const unhide = 'Einblenden';
  static const hidden = 'Ausgeblendet';
  static const toPost = 'Zum Beitrag';
  static const answered = 'Beantwortet';
  static const noAutoReplies = 'Jede Antwort schickst du selbst ab. Automatische Antworten gibt es nicht.';

  // --- Nischen ---------------------------------------------------------
  static const nichesTitle = 'Nischen';
  static const nichesEmpty = 'Noch keine Nische. Nischen verbinden Accounts, Trends und Ideen.';
  static const nicheAdd = 'Nische anlegen';
  static const nicheName = 'Name';
  static const nicheKeywords = 'Schlüsselbegriffe';
  static const nicheKeywordsHint = 'Mit Komma trennen. Filtert RSS-Einträge.';
  static const nicheRegion = 'Region (z. B. DE)';
  static const nicheLanguage = 'Sprache (z. B. de)';
  static const nicheDeleteConfirm = 'Diese Nische löschen? Ideen und Trends bleiben erhalten und verlieren nur die Zuordnung.';

  // --- Team ------------------------------------------------------------
  static const teamTitle = 'Team und Workspace';
  static const workspaceName = 'Name des Workspace';
  static const members = 'Mitglieder';
  static const roleOwner = 'Owner';
  static const roleMember = 'Mitglied';
  static const invite = 'Mitglied einladen';
  static const inviteExplain = 'Gib diesen Code weiter. Die Person trägt ihn beim Erstellen ihres Kontos ein.';
  static String inviteValidUntil(String when) => 'Gültig bis $when';
  static const openInvites = 'Offene Einladungen';
  static const removeMember = 'Entfernen';
  static const removeMemberConfirm = 'Dieses Mitglied entfernen? Sein Konto wird gelöscht.';
  static const you = 'du';

  // --- Datenschutz -----------------------------------------------------
  static const privacyTitle = 'Datenschutz und Konto';
  static const privacyWhat = 'Was die App speichert';
  static const privacyText =
      '• Dein Konto: Name, E-Mail, Passwort (nur als Hash).\n'
      '• Verbundene Instagram-Accounts: Profil, Beiträge, Statistiken, Kommentare. Die Zugangs-Tokens liegen verschlüsselt auf dem Server und kommen nie auf dieses Gerät.\n'
      '• Kommentare Dritter werden nur zum Anzeigen und Beantworten gespeichert und nach 90 Tagen gelöscht.\n'
      '• Von Wettbewerbern werden nur öffentliche Kennzahlen gespeichert.\n'
      '• Für Umsetzungsvorschläge gehen Idee, Nische, Account-Profil, verknüpfter Trend und die 5 besten Beiträge an den KI-Anbieter.\n'
      '• Auf diesem Gerät liegt nur deine Sitzung, geschützt im Schlüsselbund bzw. im geschützten Browser-Speicher.';
  static const privacyOperatorNote = 'Die vollständige Datenschutzerklärung stellt der Betreiber dieses Servers bereit.';
  static const connectedAccounts = 'Verbundene Konten';
  static const exportData = 'Daten exportieren';
  static const exportSub = 'Alle Workspace-Daten als JSON-Datei';
  static const exportDone = 'Export erstellt';
  static const logout = 'Abmelden';
  static const deleteAccount = 'Konto löschen';
  static const deleteAccountText =
      'Dein Konto wird sofort gelöscht. Bist du die letzte Person im Workspace, werden auch alle Accounts, Statistiken, Ideen und Dateien gelöscht. Das lässt sich nicht rückgängig machen.';
  static const deleteAccountConfirmField = 'Zum Bestätigen LÖSCHEN eingeben';
  static const deleteWord = 'LÖSCHEN';
  static String signedInAs(String email) => 'Angemeldet als $email';

  // --- Ergänzungen -----------------------------------------------------
  static const saved = 'Gespeichert';
  static const saving = 'Wird gespeichert …';
  static const requiredFields = 'Bitte alle Pflichtfelder ausfüllen.';
  static const aiNotConfigured = 'Auf dem Server ist noch kein KI-Zugang hinterlegt (AI_API_KEY). Die Schritte stehen in der Anleitung.';
  static const finish = 'Abschließen';
  static const linkedPostSub = 'Die Statistik dieses Beitrags fließt in die Idee zurück.';
}
