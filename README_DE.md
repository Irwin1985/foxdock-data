# foxdock-data

Das Plugin `data` für FoxDock, das Plugin-System für die IDE von Visual FoxPro 9. Tabellen, Cursor und Datenbankverbindungen aus der IDE: JSON hin und zurück, Export, SQL-Skripte und ein Explorer für ODBC-Server.

> Auch auf Englisch ([README.md](README.md)) und Spanisch ([README_ES.md](README_ES.md)).

## Installieren

Sie brauchen FoxDock und [FoxPack](https://irwinrodriguez.dev/products/foxpack).

- In FoxDock: **FoxDock > Plugins > Plugin-Center...**, **Verfügbar**, `data` auswählen und **Installieren** drücken.
- Von der Konsole: `foxpack plugin add data`.

Wenn `data` mit Ihrem FoxDock-Installer kam, zeigt das Plugin-Center seine neuen Versionen unter **Aktualisierungen**.

## Das Paket `data`

**FoxDock > Daten** (FoxDock > Data) arbeitet mit der Tabelle oder dem Cursor, die in der Datensitzung 1 (der des
Befehlsfensters) ausgewählt sind. Ist keine ausgewählt, fragt der Menüpunkt nach einer `.dbf`. Eine `.dbf`,
die dafür geöffnet wird, kommt `SHARED NOUPDATE` in einen neuen Arbeitsbereich und wird am Ende wieder
geschlossen: FoxDock schreibt nie in Ihre Tabellen, und der Datensatzzeiger, der ausgewählte
Arbeitsbereich, `SET DELETED` und `SET POINT` bleiben, wie sie waren. Gelöschte Zeilen kommen nicht mit;
Filter und Reihenfolge des Arbeitsbereichs werden beachtet.

| Menüpunkt | Was er tut |
|---|---|
| **Tabelle als JSON** (Table to JSON) | Alle Zeilen nach `<tabelle>.json` (UTF-8) in `%LOCALAPPDATA%\FoxDock\data\`, mit der Anwendung geöffnet, die Windows für `.json` hat (nie im Editor von VFP: siehe unten); die ersten 1000 Zeilen außerdem in die Zwischenablage |
| **JSON als Cursor** (JSON to cursor) | Ein Cursor `json_1`, `json_2`... in der Datensitzung 1, mit `BROWSE NOWAIT`: aus der Zwischenablage, wenn sie JSON enthält (es beginnt mit `[` oder `{`), sonst aus einer `.json`-Datei, die Sie wählen. Aus dem Dokument von **Exportieren...** kommen seine Zeilen, und mit **Nur Schema** (Schema only) ein leerer Cursor mit seinen Spalten. JSON, das sich nicht lesen lässt, meldet der Hinweis oben rechts in VFP, ohne Dialog |
| **Tabelle als Skript >** (Script table as) | `CREATE TABLE`, `INSERT` oder `UPDATE`, wie *Script Table as* im SQL Server Management Studio: `<tabelle>-<art>.sql`, oder `.prg` im VFP-Dialekt, im selben Ordner, in CP1252 und im Editor von VFP geöffnet |
| **Dialekt >** (Dialect) | VFP, SQL Server, MySQL / MariaDB, PostgreSQL, SQLite oder Firebird; der mit dem Häkchen ist der aktive |

Die Dateien werden ohne Rückfrage überschrieben (es ist der Ordner von FoxDock), und der Hinweis oben rechts in VFP und das
Log sagen, wo sie liegen.

**Welche Kodierung, und warum.** Was Sie im Editor von VFP nachbearbeiten, ist in CP1252, der Codepage
dieses Editors: die `.sql` und die `.prg` von **Tabelle als Skript**, ohne BOM. Der Editor von VFP speichert in
CP1252, deshalb hätte eine dort nachbearbeitete UTF-8-Datei zwei Kodierungen gemischt. `sqlcmd` und SQL
Server Management Studio lesen die `.sql` in CP1252 auf einem westlichen Windows so, wie sie ist (auf einem
anderen Windows `sqlcmd -f 1252`). Was in UTF-8 ist, öffnet sich nicht im Editor von VFP: Es öffnet sich mit
der Anwendung, die Windows für diese Art Datei hat, und gibt es keine, sagen der Hinweis oben rechts in VFP und das Log, wo sie liegt.

| Ausgabe | Kodierung | Geöffnet in |
|---|---|---|
| `.json` (**Tabelle als JSON**) | UTF-8, ohne BOM | der Anwendung von Windows |
| `.sql` (**Tabelle als Skript**) | CP1252, ohne BOM | dem Editor von VFP |
| `.sql` mit `script.utf8` | UTF-8 mit BOM (die von Firebird ohne BOM) | der Anwendung von Windows |
| `.prg` (VFP-Dialekt) | CP1252, ohne BOM, immer | dem Editor von VFP |

Welcher Client was will: SQL Server (`sqlcmd`, SSMS) und VFP lesen CP1252. MySQL und MariaDB lesen es mit
`mysql --default-character-set=latin1` (was MySQL latin1 nennt, ist CP1252), oder nehmen `script.utf8`.
PostgreSQL liest es mit `PGCLIENTENCODING=WIN1252` vor `psql`, oder nimmt `script.utf8`. SQLite liest Text als
UTF-8: dafür `script.utf8`. Firebird liest es mit `isql -ch WIN1252 -i`, in einer WIN1252- und in einer UTF8-Datenbank;
mit `script.utf8` mit `isql -ch UTF8 -i`, und seine Datei hat kein BOM, weil isql keins annimmt. Das Skript hat kein
`COMMIT`: isql bestätigt das Eingefügte am Ende, und ein am Ende angehängtes `QUIT;` macht es rückgängig.

Bei einer großen Tabelle reagiert die IDE nicht, solange geschrieben wird, und der Hinweis oben rechts in VFP zählt die
Zeilen mit. Als Anhaltspunkt: 100.000 Zeilen mit allen Typen brauchten auf dem Rechner, auf dem gemessen
wurde, etwa 16 s nach JSON und 19 s für `INSERT`.

Wie jeder Wert herauskommt:

- **`INSERT`**: eine Anweisung pro Zeile. **`UPDATE`**: eine pro Zeile, über den Primär- oder
  Kandidatenschlüssel des CDX (ein Tag ohne Filter auf einem Feld, oder auf mehreren mit `+` verbunden, jedes so
  wie es ist oder in `STR()`, `ALLTRIM()`, `PADR()` oder `DTOS()`: `a+STR(b)` ist der Schlüssel `a, b`); gibt es
  keinen, über alle Felder, und ein Kommentar am Anfang des Skripts sagt es. Gehören alle Spalten zum
  Schlüssel, gibt es nichts für das `SET`: Das Skript sagt es und hat kein `UPDATE`.
- Text ohne die Leerzeichen am Ende; Numeric und Float mit den Nachkommastellen ihres Felds; ein Double
  mit dem Wert, den es speichert, nicht mit den Nachkommastellen des Felds (die kürzeste Dezimalzahl, die
  dasselbe Double ergibt: `1/3` in einem `B(2)` geht als `0.3333333333333333`); Datum und Datum mit
  Uhrzeit in ISO 8601. `NULL` als `NULL`, und ein leeres Datum ebenfalls als `NULL` (im VFP-Dialekt `{}`:
  dort ist es ein eigener Wert). Ein Memo geht als Text. Felder vom Typ General kommen nicht mit, und ein
  Kommentar und der Hinweis oben rechts in VFP sagen, welche.
- Tabellen- und Feldnamen in den Anführungszeichen, die jede Datenbank will: `[name]` in SQL Server,
  `` `name` `` in MySQL, `"name"` in PostgreSQL und SQLite, `"NAME"` in Firebird, und ohne in VFP. In Firebird
  stehen sie in Großbuchstaben, damit sich die Tabelle auch ohne Anführungszeichen lesen lässt.
- In JSON: ein Objekt pro Zeile, Feldnamen in Kleinbuchstaben, `null` für `NULL` und für ein leeres Datum,
  `true` und `false`, und Varbinary und Blob in Base64.
- **JSON als Cursor** liest mit JSONFox 13.2.0: Was **Tabelle als JSON** geschrieben hat, kommt mit denselben
  Werten zurück, und wieder als JSON geschrieben ergibt es denselben Text. Ein Double kommt Bit für Bit
  zurück. Varbinary und Blob kommen als Text mit ihrem Base64 zurück: `STRCONV(feld, 14)` ergibt die Bytes.

### Die Typen, Dialekt für Dialekt

| VFP | SQL Server | MySQL / MariaDB | PostgreSQL | SQLite | Firebird | VFP-Dialekt |
|---|---|---|---|---|---|---|
| `C(n)` Character | `NVARCHAR(n)` | `VARCHAR(n)` | `VARCHAR(n)` | `TEXT` | `VARCHAR(n)` | `C(n)` |
| `V(n)` Varchar | `NVARCHAR(n)` | `VARCHAR(n)` | `VARCHAR(n)` | `TEXT` | `VARCHAR(n)` | `V(n)` |
| `M` Memo | `NVARCHAR(MAX)` | `LONGTEXT` | `TEXT` | `TEXT` | `BLOB SUB_TYPE TEXT` | `M` |
| `N(w,d)` Numeric | `DECIMAL(w,d)` | `DECIMAL(w,d)` | `NUMERIC(w,d)` | `NUMERIC` | `NUMERIC(w,d)` (`w` ≤ 18) | `N(w,d)` |
| `F(w,d)` Float | `DECIMAL(w,d)` | `DECIMAL(w,d)` | `NUMERIC(w,d)` | `NUMERIC` | `NUMERIC(w,d)` (`w` ≤ 18) | `F(w,d)` |
| `I` Integer | `INT` | `INT` | `INTEGER` | `INTEGER` | `INTEGER` | `I` |
| `B(d)` Double | `FLOAT` | `DOUBLE` | `DOUBLE PRECISION` | `REAL` | `DOUBLE PRECISION` | `B(d)` |
| `Y` Currency | `MONEY` | `DECIMAL(19,4)` | `NUMERIC(19,4)` | `NUMERIC` | `NUMERIC(18,4)` | `Y` |
| `D` Date | `DATE` | `DATE` | `DATE` | `TEXT` (ISO 8601) | `DATE` | `D` |
| `T` DateTime | `DATETIME2(0)` | `DATETIME` | `TIMESTAMP` | `TEXT` (ISO 8601) | `TIMESTAMP` | `T` |
| `L` Logical | `BIT` (`1`, `0`) | `BOOLEAN` (`TRUE`, `FALSE`) | `BOOLEAN` (`TRUE`, `FALSE`) | `INTEGER` (`1`, `0`) | `BOOLEAN` (`TRUE`, `FALSE`) | `L` |
| `Q(n)` Varbinary | `VARBINARY(n)` (`0x…`) | `VARBINARY(n)` (`X'…'`) | `BYTEA` (`'\x…'`) | `BLOB` (`X'…'`) | `VARCHAR(n) CHARACTER SET OCTETS` (`x'…'`) | `Q(n)` (`0h…`) |
| `W` Blob | `VARBINARY(MAX)` | `LONGBLOB` | `BYTEA` | `BLOB` | `BLOB SUB_TYPE BINARY` (`x'…'`) | `W` |
| `G` General | kommt nicht mit | kommt nicht mit | kommt nicht mit | kommt nicht mit | kommt nicht mit | kommt nicht mit |

Bei einer Tabelle einer Verbindung (**Erkunden...** > **Skript als...**) ist der Typ der VFP-Buchstabe, mit dem sie vom Server
kommt (der `type` von `ide_data_db_describe`): `bigint`, `uniqueidentifier` und `time` von SQL Server kommen als Text und
`varbinary` als Memo, und so gehen sie. Ein `varchar(max)` oder `nvarchar(max)` kommt als `C(0)` und geht als Memo. Eine Spalte
des Primärschlüssels ist `NOT NULL`, auch wenn die Datenbank sagt, dass sie NULL erlaubt (SQLite). Aus Firebird kommen
`BIGINT`, `INT128` und ein `NUMERIC` mit mehr als 18 Stellen als Text, `TIME` als Datum und Uhrzeit vom 30.12.1899,
und ein binäres `BLOB` als General, das ausgelassen wird.

Was keine Entsprechung hat, und was damit geschieht:

- Ein Character-Feld verliert seine feste Breite: die Leerzeichen am Ende sind keine Daten.
- In SQL Server geht Text als `N'…'` (Unicode). In MySQL werden Backslashes verdoppelt, und
  `CREATE TABLE` endet mit `DEFAULT CHARSET=utf8mb4`. SQLite kennt kein Datum: es geht als ISO-8601-Text,
  den seine Datumsfunktionen lesen.
- Ein Schlüssel auf einem Feld geht als `PRIMARY KEY` in `CREATE TABLE`, und im VFP-Dialekt als
  `INDEX ON … CANDIDATE` (eine freie Tabelle hat keinen Primärschlüssel).
- In Firebird steht nichts hinter dem Typ einer Spalte, die NULL erlaubt, und ein `N` mit mehr als 18 Stellen
  Breite geht als `NUMERIC(18,d)`. Ein Zeilenumbruch in einem Text geht als `ASCII_CHAR(13) || ASCII_CHAR(10)`,
  weil isql den eines Literals als LF speichert. Ein Text mit mehr als 20.000 Zeichen oder ein Binärwert mit mehr
  als 30.000 Bytes geht in Stücken, mit `||` verbunden, und in einem Memo oder einem Blob steht das erste in einem
  `CAST`. Eine Anweisung von Firebird darf nicht über 10.485.760 Bytes, ein größerer Wert passt also nicht.
- Im VFP-Dialekt geht eine Zeichenkette in Stücken von 200 Zeichen, mit `+` verbunden (ein Literal darf
  nicht über 255), Steuerzeichen als `CHR(n)`, und ein Wert mit mehr als 1000 Zeichen geht leer in die
  Anweisung und wird danach stückweise angehängt (`REPLACE` nach einem `INSERT`, `UPDATE` nach einem `UPDATE`).

### Die Verbindungen

**FoxDock > Daten > Verbindungen** (FoxDock > Data > Connections) speichert die Verbindungen zu Ihren Datenbankservern (SQL Server, MySQL,
MariaDB, PostgreSQL, Firebird und SQLite) und öffnet sie aus der IDE, über FoxRemote (eine Bibliothek, die das Paket
mit `requires` anfordert: sie liegt unverändert in `lib\foxremote\`). Jede Verbindung ist ein Menüpunkt mit einem eigenen Untermenü:

| Menüpunkt | Was er tut |
|---|---|
| **Verbinden...** (Connect...) | Verbindet. Hat die Verbindung einen `user` und ist kein Passwort gespeichert, fragt ein kleines Fenster danach; mit **Merken** (Remember) wird es gespeichert, verschlüsselt mit Ihrem Windows-Konto |
| **Trennen** (Disconnect) | Schließt die Verbindung |
| **Erkunden...** (Explore...) | Das Fenster der Verbindung: ihre Datenbank, ihre Tabellen und Views, und die Spalten und Zeilen jeder davon (siehe unten) |
| **Abfrage...** (Query...) | Ein Fenster mit einem Feld für ein `SELECT`, wie viele Zeilen es höchstens liest (**Limit**: anfangs 100, 0 ohne Grenze; es wird gemerkt) und **Ausführen** (Run): die Zeilen, in einem `BROWSE`. **Als Objekt** (To object) legt das Ergebnis in eine Variable für das Befehlsfenster (siehe unten) |

Leerzeichen am Ende eines in **Verbinden...** eingegebenen Passworts gehen verloren, weil das Textfeld von VFP
die Eingabe mit Leerzeichen auffüllt; Leerzeichen am Anfang bleiben erhalten.

**Erkunden...** verbindet zuerst, wenn die Verbindung nicht verbunden ist (mit dem Passwortfenster, wenn
eines nötig ist: dann **Erkunden...** noch einmal). Es öffnet ein Fenster pro Verbindung, **FoxDock - <Name>**;
ein zweiter Klick holt dieses Fenster nach vorn. Darin:

- **Datenbank** (Database): die Datenbank, in der die Verbindung ist, und eine Liste der Datenbanken des Servers, die Sie
  öffnen dürfen (SQL Server, MySQL, MariaDB und PostgreSQL). Eine andere wählen bringt die Verbindung dorthin,
  lädt die Liste der Tabellen neu und schreibt es ins Log; ab dann lesen die Tools des Agenten diese
  Datenbank. Bei SQLite und Firebird ist die Datenbank die Datei, und die Liste ist ausgegraut. Die Datenbank
  wechseln öffnet eine neue Verbindung zum Server: Mit Passwort kann FoxDock das nur, wenn das Passwort
  gespeichert ist (**Merken**); sonst sagt es das Fenster, und die Verbindung bleibt, wo sie war.
- **Filter**: Tippen Sie einen Teil eines Namens, und die Liste behält die Tabellen und Views, die ihn
  enthalten (Groß- und Kleinschreibung egal); die **Eingabetaste** bringt Sie in die Liste, auf ihre erste
  Zeile. Daneben **Tabellen und Sichten** (Tables and views), **Tabellen** (Tables) oder **Sichten** (Views)
  (ausgegraut, wenn die Datenbank nur eine Art hat; mit beiden beginnt es bei **Tabellen**), und darunter, wie viele
  beide Filter durchlassen, von denen, die das Kombinationsfeld zulässt: **N von M Tabellen**, **N von M Sichten** oder
  **N von M Tabellen und Sichten**.
- Die Liste: jede Tabelle und jede View der Datenbank, mit `table` oder `view` daneben.
- **Spalten** (Columns): die Spalten der gewählten (Name, VFP-Typ, Breite, Dezimalstellen, NULL und ob sie zum
  Primärschlüssel gehört), in einem `BROWSE`. Sein Titel nennt den Schlüssel.
- **Anzeigen** (Browse): die ersten **Limit** Zeilen der gewählten, in einem `BROWSE`. **Limit** ist das von
  **Abfrage...** (anfangs 100, 0 ohne Grenze; es wird gemerkt), und der Titel sagt, wann dort Schluss war. Mit 0
  und einer großen Tabelle wartet die IDE, bis die Zeilen da sind (250.000 Zeilen dauerten etwa eine Sekunde).
- **Als Objekt**, mit dem Feld **Variable** daneben: die Zeilen der gewählten, in einer Variablen für das
  Befehlsfenster (unten, nach den `BROWSE`).
- **Exportieren...** (Export...): die gewählte in eine Datei, in einem kleinen Fenster:
  - **das Format**: `.dbf` (eine freie Tabelle mit den Typen von VFP: `bigint` und `uuid` kommen als Text,
    `datetime2` verliert die Sekundenbruchteile, und ein Spaltenname mit mehr als 10 Buchstaben wird gekürzt, weil
    eine freie Tabelle nicht mehr erlaubt), `.json` (UTF-8 ohne BOM: ein Objekt mit `table`, `connection`, `columns` und `rows`, den Zeilen von
    **Tabelle als JSON**; mit **Nur Schema** (Schema only) ohne `rows`; **JSON als Cursor** liest es wieder) oder `.csv`
    (Trennzeichen `;`, `,` oder Tabulator; CP1252 oder UTF-8 mit BOM; eine Kopfzeile, Anführungszeichen nur um einen
    Text mit dem Trennzeichen, einem Anführungszeichen oder einem Zeilenumbruch, Zahlen mit Punkt, Datumsangaben als
    `2026-11-01` und `2026-11-01T10:20:30`, ein leeres Feld für NULL);
  - **In eine Datei** (To a file) oder **In die Zwischenablage** (To the clipboard) (JSON und CSV; eine `.dbf` nur in eine
    Datei): Mit der Zwischenablage zählen Ordner, Name, **Ersetzen**, **Öffnen** und die Kodierung nicht, und der
    Hinweis sagt, wie viele Zeilen und Zeichen hineingingen;
  - **der Ordner und der Name** (anfangs `%LOCALAPPDATA%\FoxDock\data\` und `<Tabelle>.<Endung>`);
  - **die Zeilen**: alle oder die ersten N (die Zahl lässt sich nur mit **Die ersten** eingeben); darüber, wie viele der Server hat (`SELECT COUNT(*)`), und der Hinweis
    sagt, wie viele hinausgingen;
  - eine Datei, die schon da ist, wird nur überschrieben, wenn Sie **Ersetzen** (Replace it) markieren: Das sagt das Fenster,
    nicht VFP;
  - mit **Öffnen** (Open it) (anfangs markiert; nehmen Sie die Markierung weg, wenn ein Agent Exportieren... bedient) öffnen sich
    die `.json` und die `.csv` in UTF-8 mit ihrer Windows-Anwendung, die `.csv` in CP1252 in einem Texteditor von VFP
    (CP1252 ist seine eigene: Die Akzente sehen richtig aus; in UTF-8 täten sie es nicht). Der Hinweis sagt, womit
    sie sich geöffnet hat. Die `.dbf` öffnet sich nicht, und der Hinweis sagt, wo sie liegt;
  - eine Datei, die in einem Editor von VFP offen ist oder die ein anderes Programm hält (Excel hält eine `.csv`, die
    es offen hat), wird nicht geschrieben: Das Fenster sagt es. Schließen Sie sie vorher.
- **Sicht erstellen...** (Create view...): eine Remote-View von VFP der gewählten, in einer `.dbc`:
  - **die Datenbank**: die in VFP offene, eine im Ordner des offenen Projekts oder eine neue mit dem Namen, den Sie
    eintippen (ohne Projekt in `%LOCALAPPDATA%\FoxDock\data\`);
  - **der Name** der View (nicht der Name einer Tabelle der `.dbc`; der Name einer ihrer Views schon: siehe
    **Ersetzen** unten), **die Spalten** in alphabetischer Reihenfolge
    (anfangs alle markiert; **Alle** (All), **Keine** (None) oder **Strg+A** in der Liste; die View behält die
    Reihenfolge der Tabelle) und ein optionales **WHERE** (der Server prüft es; was er sagt, sagt das Fenster);
  - **Aktualisierbar** (Updatable), wenn die Tabelle einen Primärschlüssel hat: Dann schickt `TABLEUPDATE()` Ihre Änderungen an den
    Server. Mit Schlüssel ist es anfangs markiert, ohne Schlüssel aus. Nehmen Sie die Markierung weg, öffnet sich das
    nächste Fenster ohne sie: Das wird in `config.json` gespeichert, in der Option `connections.createViewUpdatable`
    (unten). Bei SQLite bleiben die `TEXT`-Spalten draußen (in VFP sind sie Memo, und eine View schreibt sie nicht),
    und der Text kommt im UTF-8, das SQLite speichert: `STRCONV(<Feld>, 11)` gibt die Akzente zurück;
  - **kein Passwort in der `.dbc`**: Ihre Verbindung hat die Verbindungszeichenfolge ohne Passwort, auch während die
    View erstellt wird. Währenddessen steht das Passwort in einer temporären `.dsn`-Datei im temporären Ordner Ihres
    Benutzers (`%TEMP%\foxdock-*.dsn`), die FoxDock am Ende löscht, auch wenn die View scheitert. Und die Verbindung
    fragt nie (`DispLogin` 3), deshalb öffnet das Erstellen kein Fenster. Ist die
    View erstellt, bleibt sie bei `DispLogin` 1. Ohne Passwort (Windows-Authentifizierung, SQLite) öffnen
    `OPEN DATABASE` und `USE <View>` sie. Mit Passwort fragen `USE <View>` ohne Zusatz getippt und Ändern im
    Datenbank-Designer (`MODIFY DATABASE`, Rechtsklick auf die View) im Anmeldefenster des Treibers danach, statt
    mit dem Fehler 1526 («Connectivity error») zu scheitern; das Fenster sagt es, wenn es die View erstellt. Um sie
    ohne Rückfrage zu öffnen, geben Sie das Passwort beim Öffnen der View an, wie das Fenster zeigt:
    `USE <View> CONNSTRING DBGETPROP("<Verbindung>", "Connection", "ConnectString") + "PWD=<Passwort>"`.
  - **Wenn Sie mit einer früheren Version** (bis 0.9.31) Views mit Passwort in einer `.dbc` erstellt haben, die schon
    da war, oder eine zweite View in derselben `.dbc`: Diese Versionen ließen die Verbindungszeichenfolge mit dem
    Passwort in losen Blöcken der `.dct`-Datei der `.dbc` zurück. Die Verbindung selbst war sauber, aber das Passwort
    stand noch in der Datei. `PACK DATABASE`, mit der `.dbc` exklusiv geöffnet und nichts von ihr geöffnet, entfernt
    es. 0.9.32 tut das nicht mehr.
  - **Das WHERE, vorher geprüft**: Mit einem **WHERE** prüft **Sicht erstellen...** es zuerst mit dem Datenbankserver, mit
    einem SELECT ohne Zeilen über die Verbindung von FoxDock. Eine Spalte oder eine Funktion, die es nicht gibt,
    erstellt keine Sicht, und das Fenster nennt den Fehler des Servers. Einen Typ, der nicht passt (`id = 'abc'`),
    sieht es nicht; die Sicht scheitert dann beim Öffnen. Eine Sicht mit Parametern (`?x`) wird nicht geprüft. Ein
    **WHERE**, das mit einem Kommentar (`-- …`) endet, wird nicht angenommen: entfernen Sie den Kommentar.
  - **Eine Sicht, die scheitert**, lässt die Verbindung der `.dbc` so wie eine gute: Sie fragt nach dem Passwort im
    Fenster des Treibers (nicht mit dem Fehler 1526), und sie hinterlässt ihre Zeile mit dem Grund im Log.
  - **Erstellen** (Create) erstellt die View und schaltet sich ab, sobald sie erstellt ist, sodass ein zweiter Klick
    keine weitere macht. Es schaltet sich wieder ein, wenn Sie etwas ändern, das eine andere View ergäbe: den Namen,
    die Datenbank, die Spalten, das **WHERE** oder das Kästchen **Aktualisierbar**.
  - Mit einem Namen, den die gewählte `.dbc` schon als View hat, heißt die Schaltfläche **Ersetzen** (Replace), und
    das Fenster erklärt es, bevor Sie sie drücken: «Die Sicht X gibt es schon in Y.dbc: Ersetzen erstellt sie neu mit
    dem, was oben steht.». **Ersetzen** löscht die View (`DROP VIEW`) und erstellt sie neu mit dem, was im Fenster
    steht. Es lehnt ab, wenn diese View in der IDE geöffnet ist («USE IN <View> schließt sie»), weil VFP ihren Cursor
    behalten würde. Mit dem Namen einer Tabelle der `.dbc` gibt es kein **Ersetzen**: Es lehnt ab, wie immer, und
    das Fenster sagt es.
  - **Öffnen** (Open), neben **Erstellen**, macht das für Sie, sobald die View erstellt ist: Es öffnet die `.dbc` (oder
    wählt sie, wenn sie offen ist), öffnet die View in einem freien Arbeitsbereich der Datensitzung der IDE (als hätten
    Sie es getippt), mit dem Zeilenlimit von **Abfrage...**, und zeigt sie in einem `BROWSE`. Die View bleibt offen,
    wenn Sie das Fenster schließen: Sie gehört Ihnen, nicht dem Fenster. Noch einmal gedrückt, liest es die View neu,
    statt eine zweite Kopie zu öffnen. Mit Passwort nimmt es das mit **Merken** in **Verbinden...** gespeicherte, ohne es
    zu zeigen, und gibt es in `CONNSTRING` mit, fragt also nicht; ein nur getipptes Passwort behält FoxDock nicht, dann öffnet **Öffnen** nichts, sagt es, und der Weg
    sind die Zeilen oben.
- **Skript als...** (Script as...): das `CREATE TABLE`, `INSERT` oder `UPDATE` der gewählten, ohne sie zu öffnen, in einem
  kleinen Fenster: der Dialekt (anfangs der der Datenbank der Verbindung, und der von MySQL für MariaDB; ihn hier zu ändern gilt nur dieses Mal), die Zeilen (alle oder die
  ersten N, deren Zahl sich nur mit **Die ersten** eingeben lässt; nicht bei `CREATE TABLE`) und wohin es geht: **In den Editor** (To the editor) (die Datei von **Tabelle als Skript**,
  `<Tabelle>-<kind>.sql` oder `.prg` in `%LOCALAPPDATA%\FoxDock\data\`, geöffnet wie jene) oder **In die Zwischenablage** (To
  the clipboard). Die Spalten und der Primärschlüssel kommen vom Server, nicht aus den Zeilen (unten, unter der Typentabelle);
  `UPDATE` geht über die Spalten des Schlüssels, eine oder mehrere, und über alle Felder, wenn er keinen hat, und ein
  Kommentar im Skript sagt es. Die Namen stehen in den Anführungszeichen, die der Dialekt des Skripts will. Nichts bleibt in der
  IDE offen.

Beide `BROWSE` sind schreibgeschützt: Keine Zeile lässt sich ändern, hinzufügen oder löschen. Ihre Cursor
heißen `c_<Verbindung>_<Tabelle>_columns` und `c_<Verbindung>_<Tabelle>` und werden mit dem Fenster
geschlossen, außer Sie markieren **Cursor beim Schließen offen lassen** (Keep the cursors open when it closes)
(anfangs nicht markiert; es wird gemerkt, und der Hinweis sagt, welche offen bleiben). **Abfrage...** hat
dasselbe Kästchen für seinen Cursor. **Trennen**, **Neu laden** (Reload) oder das Abschalten des Pakets
schließen das Fenster und diese Cursor mit ihm, mit Kästchen oder ohne. Was das Fenster zu sagen hat, steht in seinem Feld unten,
im Hinweis oben rechts in VFP und im Log.

**Als Objekt, für das Befehlsfenster.** **Abfrage...** und **Erkunden...** haben eine Schaltfläche **Als Objekt** mit
einem Feld **Variable** daneben. In **Abfrage...** nimmt sie das Ergebnis des letzten **Ausführen**; in
**Erkunden...** die Zeilen der gewählten Tabelle oder View, bis zum **Limit** des Fensters (dasselbe wie bei
**Anzeigen**). Sie erstellt eine `Collection` mit einem Objekt pro Zeile, mit den Spalten als Eigenschaften, und legt
sie in eine `PUBLIC`-Variable. Sie muss `PUBLIC` sein: Aus einem Fenster heraus würde `_VFP.SetVar` eine private
Variable hinterlassen, die beim Zurückkehren verschwindet, und nur eine `PUBLIC` erreicht das Befehlsfenster. Ist das
Feld leer, trägt sie `lo` und den Namen der Tabelle ein (`loOrders`, `loG10_cl`); in **Abfrage...** den
Namen des Cursors des Ergebnisses (`loC_shop_query`). Sie lehnt einen Namen ab, der kein
Variablenname von VFP ist, und eine Variable, die es schon gibt: Sie überschreibt nichts. Ohne Zeilen erstellt sie
nichts. Das Fenster sagt, wie viele Zeilen, dass die Variable `PUBLIC` ist und dass `RELEASE loOrders` sie entfernt,
und wie Sie sie im Befehlsfenster benutzen: `? loOrders.Count`, `? loOrders.Item(1).<Spalte>`.

Am Ende des Untermenüs öffnet **Verbindungen bearbeiten...** (Edit connections...) das Fenster
**FoxDock - Verbindungen**: die Verbindungen der zwei Dateien, mit ihrer Id, ihrem Namen, ihrem Motor, wo sie stehen (im
Projekt oder bei Ihnen) und ob sie verbunden sind. **Neu...** (New...) und **Bearbeiten...** (Edit...) öffnen
**FoxDock - Verbindung**, mit den Feldern der Datei und keinem Passwort (das fragt Verbinden...): Es sagt, was
nicht passt (eine Id, die in einer der zwei Dateien schon steht, ein leerer Name, ein Passwort in einem Feld), und
schreibt dann nichts. **Speichern** (Save) schreibt die ganze Datei neu, in einem Format, dem des Beispiels, und
behält die Schlüssel, die es nicht kennt; mit der Datei offen im Editor speichert es nicht. **Löschen** (Delete)
fragt im Fenster, trennt die Verbindung und vergisst ihr gespeichertes Passwort. **Datei öffnen...** (Open the
file...) öffnet die `connections.json` im Editor, wie bisher (die des offenen Projekts, oder Ihre, wenn kein
Projekt offen ist; mit einem Beispiel aus zwei Verbindungen, SQLite und SQL Server, wenn es keine gab), und
**Neu laden** liest die Dateien neu. Jedes Objekt des Arrays ist eine
Verbindung, und jede ist ein Eintrag im Untermenü **Verbindungen**, mit ihrem **Verbinden...**, **Trennen**,
**Erkunden...** und **Abfrage...**: Eine Verbindung wählen heißt, ihr Untermenü öffnen. Nichts öffnet einen Dialog von VFP: Was schiefgeht, sagen der Hinweis oben rechts in VFP und das Log. Der Grund eines Fehlers steht auf Englisch und in Anführungszeichen, so wie ihn die Tools des Agenten liefern.

**Der Zustand, im Menü.** Eine verbundene Verbindung sagt es hinter ihrem Namen, **Shop (verbunden)**, und nur der passende
Eintrag lässt sich anklicken, **Verbinden...** oder **Trennen**. Das Menü ändert sich beim Verbinden, Trennen und Neuladen, und
wenn eine Verbindung verloren geht. **Eine verlorene Verbindung wird gemeldet**: Wenn der Server nicht mehr antwortet (das Netz,
ein Neustart des Servers), merkt es das Erste, was von ihr liest, schließt ihr Fenster **Erkunden...** mit seinen Cursorn, und
Hinweis und Log sagen es. Der Hinweis sagt zuerst das Wichtige, «Die Verbindung Shop ist verloren gegangen. Verbinden Sie sie
erneut unter FoxDock > Daten > Verbindungen.», und danach den Grund, den der Treiber nannte, gekürzt, damit er passt; das Log
behält die ganze Meldung. **Neu laden** behält die verbundenen Verbindungen; eine, deren Definition sich in der Datei geändert hat
(`server`, `port`, `database`, `user`, `driver` oder `windowsAuth`), wird getrennt, und der Hinweis sagt es. **Plugins neu laden**
(FoxDock > Plugins) ist etwas anderes: Es entlädt das Paket und schließt alle Verbindungen.

**Zwei Dateien, und in keiner ein Passwort.** `connections.json` im Ordner des offenen Projekts (sie gehört
zum Projekt und kann geteilt werden) und `%LOCALAPPDATA%\FoxDock\connections.json` (Ihre). Beide werden
gelesen: Die des Projekts kommen zuerst und tragen `(project)` im Menü, und bei derselben `id` in beiden
bleibt die des Projekts. Eine Datei ist ein JSON-Array:

```json
[
  {
    "id": "shop",
    "name": "Shop (test server)",
    "engine": "sqlserver",
    "server": "srv-test\\SQLEXPRESS",
    "port": 0,
    "database": "shop",
    "user": "reader",
    "driver": "ODBC Driver 18 for SQL Server",
    "windowsAuth": false,
    "allowWrite": false,
    "agentCanRead": false
  }
]
```

| Feld | Was es ist |
|---|---|
| `id` | Buchstaben, Ziffern, `_`, `-` und `.`; der Agent nennt die Verbindung damit |
| `name` | Was das Menü zeigt |
| `engine` | `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird` oder `sqlite` |
| `server`, `port`, `database` | Wo sie ist. Ein leeres `database` (SQL Server, MySQL, MariaDB, PostgreSQL) ist eine Verbindung zum Server, in der Datenbank, die der Server gibt (**Erkunden...** sagt, welche, und wechselt sie); bei SQL Server liest **Abfrage...** außerdem eine andere Datenbank desselben Servers mit dreiteiligem Namen (`verkauf.dbo.kunden`). Bei SQLite und Firebird ist `database` die Datei und darf nicht fehlen |
| `user` | Leer mit `windowsAuth`, und bei SQLite |
| `driver` | Der ODBC-Treiber; leer, der aus der Tabelle unten |
| `windowsAuth` | `true`: Windows-Authentifizierung (SQL Server), ohne Passwort |
| `allowWrite` | `true`: Der Agent darf über diese Verbindung mit `ide_data_db_execute` schreiben, mit Agentenrolle 10 oder höher. `false`, wenn es fehlt |
| `agentCanRead` | `true`: Der Agent darf über diese Verbindung lesen. `false`, wenn es fehlt |

Eine Datei mit einem Passwort darin (ein Schlüssel `password`, `pwd`, `passwd`, `secret` oder `pass`, oder
`pwd=` in einem Wert) wird gar nicht gelesen, und das Log sagt, welche Verbindung und welcher Schlüssel,
nie den Wert. Das Passwort liegt woanders: **Merken** in **Verbinden...** speichert es in
`%LOCALAPPDATA%\FoxDock\secrets\<id>.cred`, verschlüsselt mit Ihrem Windows-Konto (DPAPI), sodass nur Ihr
Windows-Benutzer auf diesem Rechner es zurücklesen kann. Löschen Sie die Datei, um es zu vergessen.

**`agentCanRead`, Verbindung für Verbindung.** Was der Agent liest, verlässt Ihren Rechner in Richtung des
KI-Anbieters. Bei Kundendaten entscheiden Sie das, deshalb ist es aus, bis Sie `"agentCanRead": true` in
diese Verbindung schreiben und **Neu laden** drücken. Damit allein liest der Agent nur: ein `SELECT`, höchstens
1000 Zeilen (AGENT-TOOLS_DE.md § 8). Diese Prüfung hält das Offensichtliche
auf, und eine Funktion des Servers kann trotzdem aus einem `SELECT` heraus schreiben. Für eine
Verbindung, die der Agent liest, nehmen Sie einen Benutzer des Servers, der nur lesen darf.

**`allowWrite`, Verbindung für Verbindung.** Der Agent schreibt auf einen Server nur mit `ide_data_db_execute`,
und nur mit zwei Schlüsseln: `"allowWrite": true` in dieser Verbindung (danach **Neu laden**) und Agentenrolle 10
oder höher (FoxDock > FoxAgent > Agentenrolle). Er schickt eine Anweisung auf einmal (`INSERT`, `UPDATE`,
`DELETE`, `CREATE`, `ALTER`, `DROP` oder `TRUNCATE`); ein `UPDATE` oder `DELETE` ohne `WHERE`, ein `DROP` und ein
`TRUNCATE` brauchen zusätzlich `wholeTable`. Jede Anweisung ist festgeschrieben, wenn sie zurückkommt, und
`foxdock.log` hält jede fest, mit ihren Zeilen und ihrer Dauer, und jede abgelehnte, mit dem Grund. Für eine
Verbindung, auf die der Agent schreibt, nehmen Sie einen Benutzer des Servers, der nur anfassen darf, was er soll.

**Die Treiber.** Visual FoxPro ist ein 32-Bit-Programm und braucht deshalb den **32-Bit-ODBC-Treiber** jeder
Datenbank, auch unter 64-Bit-Windows (VFP Advanced mit 64 Bit braucht den 64-Bit-Treiber). **Verbinden...**
ohne den Treiber sagt, welchen es erwartet hat. Mit diesen wird FoxRemote getestet:

| Datenbank | `driver` |
|---|---|
| SQL Server | `ODBC Driver 18 for SQL Server` oder `ODBC Driver 17 for SQL Server` |
| MySQL, MariaDB | `MariaDB ODBC 3.2 Driver` (der MySQL-Treiber von Oracle ist für VFP ab 8.0.35 kaputt) |
| PostgreSQL | `PostgreSQL ANSI` (psqlODBC) |
| Firebird | `Firebird ODBC Driver` 3.0, und die 32-Bit-`fbclient.dll` |
| SQLite | `SQLite3 ODBC Driver` |

### KI

**FoxDock > Daten > KI** lässt AIXL auf der Tabelle oder dem Cursor arbeiten, die Sie in der IDE offen haben: ein
Label pro Zeile (**Spalte klassifizieren...**), eine Spalte pro Schlüssel (**Aus Spalte extrahieren...**), eine
Kopie einer Spalte ohne Namen oder Telefonnummern (**Spalte anonymisieren...**), die Zeilen, die zu einer Vorgabe
passen (**Zeilen filtern...**), und eine Frage zur ganzen Tabelle (**Zur Tabelle fragen...**). **AIXL ist ein
eigenes Produkt und wird separat verkauft: FoxDock bringt es nicht mit und kopiert es nicht.** AIXL wird aus
seinem Zip installiert und mit `register.cmd` in seinem Ordner registriert; seine Lizenz und der Schlüssel Ihres
Anbieter gehören in **KI > Anbieter > Anbieter verwalten...** (unten): so viele, wie Sie haben, und mit einem Klick
wechseln Sie von einem zum anderen.

Ohne AIXL, oder mit einem AIXL, das nicht startet, hat **KI** einen einzigen Eintrag, der sagt, warum. Ein Klick
darauf schreibt den ganzen Satz in den Hinweis oben rechts in VFP und ins Log und öffnet irwinrodriguez.dev im
Browser:

| Eintrag | Wann | Was tun |
|---|---|---|
| **AIXL ist nicht installiert...** | `AIXL.Host` ist auf diesem Rechner nicht registriert | AIXL 1.1.3 oder neuer und die .NET-10-Laufzeit für x86 installieren und `register.cmd` in seinem Ordner ausführen |
| **AIXL gefunden, aber nicht seine aixl.prg...** | `AIXL.Host` ist registriert, aber `aixl.prg` liegt nicht neben seiner DLL (aus einem anderen Ordner registriert, zum Beispiel); der Satz nennt den Pfad der DLL | `register.cmd` im Ordner des AIXL-Zips ausführen, oder `ai.aixlDir` (unten) auf den Ordner von `aixl.prg` setzen |
| **AIXL nicht sichtbar: die IDE läuft als Administrator...** | Ihr VFP läuft als Administrator, und Windows lässt ein erhöhtes Programm kein für Ihren Benutzer registriertes AIXL sehen (AIXL sagt `'HOST_ELEVATED'`) | VFP ohne *Als Administrator ausführen* starten, oder `register-machine.cmd` von AIXL einmal als Administrator ausführen (das Handbuch von AIXL, § 3.3) |
| **AIXL ist nicht gestartet...** | Alles andere, was AIXL sagt (`"DOTNET_RUNTIME_MISSING"`, `"HOST_IS_64BIT"`...), oder eine Version vor 1.1.3 | Der Code, den AIXL gab, steht in Anführungszeichen im Hinweis und im Log: FoxDock erfindet keine Diagnosen |

FoxDock startet AIXL nicht beim Öffnen der IDE: Es liest nur die Registry, in etwa einer Millisekunde. Es startet
es beim ersten Gebrauch von **KI** (etwa eine Drittelsekunde, solange die .NET-Laufzeit lädt), und dann fällt ein
VFP auf, das als Administrator läuft: Das Untermenü wird zu dem Eintrag, der das sagt. `aixl.prg` wird nicht im
Ordner von AIXL kompiliert: FoxDock kopiert sie in seinen Code-Cache jeder Engine (`fxp\<engine>\aixl\` in seinem
Datenordner), wie den Code der Plugins, und lädt sie von dort. So treten sich ein VFP 9 und ein VFPA, die gleichzeitig
offen sind, nicht auf die `.fxp`, und der Ordner von AIXL darf schreibgeschützt sein. Lädt oder läuft `aixl.prg`
nicht, ist der Eintrag **AIXL ist nicht gestartet...**, mit dem Code `AIXL_LOAD_FAILED` und dem Fehler von VFP im
Hinweis und im Log, und die Tools antworten dasselbe.

Mit bereitem AIXL ist das Untermenü:

| Eintrag | Was er tut |
|---|---|
| **Spalte klassifizieren...** | Ein Label pro Zeile einer Text- oder Memospalte |
| **Aus Spalte extrahieren...** | Eine Spalte pro Schlüssel eines Schemas, aus einer Text- oder Memospalte |
| **Spalte anonymisieren...** | Eine Kopie einer Text- oder Memospalte ohne das, was Sie angeben (Namen, Telefonnummern...) |
| **Zeilen filtern...** | Markiert die passenden Zeilen in `aixl_keep`; nichts wird gelöscht |
| **Zur Tabelle fragen...** | Eine Frage zur ganzen Tabelle: die Antwort, keine Spalte |
| **Anbieter: ...** | Ein Untermenü mit dem Namen des aktiven: Ihre Anbieter, mit der Markierung beim aktiven (ein Klick, und die Operationen gehen ab sofort an einen anderen), und **Anbieter verwalten...**. FoxDock wechselt nie von selbst: Hat ein Anbieter kein Guthaben mehr, schlägt die Operation mit der Meldung des Anbieters fehl, und Sie wählen hier einen anderen |
| **Anbieter verwalten...** | Das Fenster Ihrer Anbieter: eine Liste mit **Neu**, **Speichern**, **Löschen** (zweimal klicken: es gibt keinen Dialog) und **Diesen verwenden**. Jeder hat einen Namen, den Anbieter, das Modell (eine Liste mit den Modellen dieses Anbieters, das erste ist das, das AIXL standardmäßig verwendet; man kann auch ein anderes eingeben), den Schlüssel und den lokalen Server (nur für eine KI auf Ihrem eigenen Rechner, etwa Ollama oder LM Studio). **Der Schlüssel, auf zwei Arten**: mit Ihrem Windows-Konto verschlüsselt gespeichert (DPAPI: nur Ihr Benutzer auf diesem Rechner kann ihn lesen) oder bei jeder Verwendung aus einer Umgebungsvariablen gelesen (die, die Sie angelegt haben, mit ihrem Namen: das Fenster schlägt keinen vor und sagt, ob sie gefunden wird und wie lang sie ist). Löschen Sie den aktiven, ist keiner mehr aktiv: Die Operationen sind aus, bis Sie einen anderen wählen, und der Hinweis sagt es. Darunter **die AIXL-Lizenz**, eine für alle Anbieter: die Datei Ihrer Lizenz, oder ihr Text, in das Feld eingefügt (er beginnt mit `eyJ`), der als `aixl.lic` im Datenordner von FoxDock gespeichert wird. Der Schlüssel wird nie angezeigt, nie im Klartext in eine Datei geschrieben und geht nie ins Log oder an den Agenten |
| **Letzter Lauf: ...** | Ausgegraut: Zeilen, Tokens und Sekunden der letzten Operation |

**Ohne Anbieter sind die fünf Operationen ausgegraut**, und ihre Leiste sagt, was zu tun ist: zuerst einen in
**Anbieter verwalten...** hinzufügen. Ihre Tools antworten `NO_PROVIDER`, ohne etwas zu senden.

Die AIXL-Sitzung gibt es einmal pro IDE. Was Sie im Befehlsfenster tun (`AIXL_USE_MOCK()`,
`AIXL_CONFIGURE_FROM_FILE()`), ist dieselbe Sitzung, die das Menü zeigt, und das Menü liest sie aus AIXL, nicht aus
dem, was es verlangt hat.

**Die Fenster.** Jedes hat die Tabelle, in einer Liste mit den Tabellen und Cursorn, die in Datensitzung 1 geöffnet sind
(Klassifizieren, Extrahieren und Anonymisieren listen nur die mit einer Text- oder Memospalte); es öffnet sich mit
der ausgewählten oder, wenn keine ausgewählt ist, mit einer `.dbf`, die Sie wählen. Und
seine eigenen Felder. Klassifizieren, Extrahieren und Anonymisieren fragen nach der Spalte (Text oder Memo) und dem
Ziel, mit den Namen, die dazukommen, grau darunter; Klassifizieren außerdem nach den Labels (eine feste Liste,
`hoch,mittel,niedrig`; leer, das Modell wählt), Extrahieren nach dem Schema (`prioritaet,abteilung`; leer, das
Modell wählt die Schlüssel) und Anonymisieren danach, was entfernt wird. Filtern fragt, welche Zeilen passen, nach
den Spalten, die das Modell sieht (leer: die ganze Zeile), und hat **Auch ein neuer Cursor mit den passenden
Zeilen**; Fragen nach der Frage und den Spalten. Alle außer Fragen haben **Zeilen pro Block** (200; von 1 bis 1000).

Unter den Feldern steht **der Kostensatz**, kurz vor **Ausführen** neu geschrieben aus dem, was die AIXL-Sitzung
hat: «Das sendet 300 Zeilen von ventas.notas an deepseek (deepseek-chat), über Ihr eigenes Konto.», oder
«Simulationsmodus: nichts wird gesendet, nichts kostet Geld.». Es sind die Zeilen, die Sie sehen: Filter und
`SET DELETED` zählen. Was gesendet wird, bezahlen Sie über Ihr Konto bei Ihrem Anbieter (das Handbuch von AIXL,
§ 11, sagt, wie viel).

**Ausführen** geht Block für Block: Statusleiste und Fenster zählen die Zeilen («KI: 150 von 500 Zeilen (Block
3/10)»). **Esc** hält am Ende des laufenden Blocks an: Das Erledigte bleibt, und die neuen Spalten der übrigen
Zeilen sind `.NULL.` («KI: angehalten nach Block 3: 150 Zeilen fertig, 350 bleiben NULL»). Während eines Laufs
schließt Esc das Fenster nicht. Fragen ist eine Frage zur ganzen Tabelle: ohne Blöcke und ohne Esc.

**Die Kopie.** AIXL fügt seine Spalten am Ende des Cursors an und füllt sie; es schreibt nie eine Zeile neu und
verschiebt keine. Ein schreibgeschützter Cursor (ein `SELECT ... INTO CURSOR` ohne `READWRITE`) nimmt keine neuen
Spalten an, und FoxDock schreibt nie in eine Ihrer Tabellen, auch nicht, wenn Sie sie `SHARED` und beschreibbar
offen haben. In beiden Fällen arbeitet die Operation auf einer Kopie, `ai_<name>`, `READWRITE`, mit den Zeilen, die
Sie sehen, in Datensitzung 1, und das Fenster sagt das vor dem Ausführen. Das Original bleibt, wie es war. Fragen
schreibt nichts und braucht keine Kopie.

| Operation | Was sie hinterlässt |
|---|---|
| Klassifizieren | `<ziel>`, `<ziel>_con` und `<ziel>_rea` (das Label, wie sicher, und warum), am Ende, auf zehn Zeichen gekürzt. Als Ziel schlägt sie `ai_<spalte>` auf sechs gekürzt vor, damit die drei passen |
| Extrahieren | `<ziel>` und `<ziel>_<schlüssel>` für jeden Schlüssel, auf zehn gekürzt; ohne Schema die Schlüssel, die das Modell wählt. Als Ziel schlägt sie `ax_<spalte>` vor, auf sechs gekürzt, ein anderes als beim Klassifizieren. Zwei Schlüssel, die bei zehn Zeichen denselben Namen ergeben, werden vor dem Ausführen abgelehnt. Ein Schlüssel, den der Text nicht hat, kommt leer zurück, und das ist kein Fehler |
| Anonymisieren | `<ziel>` (sie schlägt `ai_<spalte>` vor, bis zehn) mit dem Text ohne das, was Sie angegeben haben |

Ist eine der Spalten, die sie hinterlässt, schon in der Tabelle, sagt das Fenster es unter dem Ziel, vor dem **Ausführen**: Ausführen schreibt darüber.
| Filtern | `aixl_keep`, logisch: `.T.` in den passenden Zeilen. Nichts wird gelöscht. Mit dem Kästchen außerdem ein Cursor `ai_<name>_kept` mit ihnen |
| Fragen | Die Antwort, im Fenster und im Log; keine Spalte. Das Modell liest nur die ersten 4.000 Zeichen dessen, was gesendet wird: Der Kostensatz sagt das, und wenn es nicht alles gelesen hat (das `INPUT_TRUNCATED` von AIXL), sagt es auch die Statusleiste |

Am Ende kommt ein `BROWSE` des Cursors (der Kopie, oder von `ai_<name>_kept`, wenn Sie ihn verlangt haben), und
Statusleiste und Log nennen die Zeilen, die fehlgeschlagenen, die Tokens und die Sekunden («KI: ventas.notas
klassifiziert in ai_not: 500 Zeilen gut, 0 fehlgeschlagen, ...»). Die Warnungen von AIXL gehen ins Log
(`COLUMN_RENAMED`, `COLUMN_WIDENED`), und wenn eine Zeile fehlschlug, öffnet sich ein Cursor `ai_errors` mit ihnen in
einem zweiten `BROWSE`. **Letzter Lauf** nennt die Zahlen. Wenn AIXL ohne eine erledigte Zeile antwortet
(`NO_DATA`, `LICENSE_*`, `PROVIDER_*`...), gehen sein Code in Anführungszeichen und sein Text in den Hinweis, das
Fenster und das Log.

**Was sie nicht tut.** Sie schreibt den Schlüssel Ihres Anbieters nie im Klartext: Entweder wird er mit Ihrem
Windows-Konto verschlüsselt gespeichert, oder er wird jedes Mal aus seiner Umgebungsvariable gelesen. Sie wechselt nie von
sich aus den Anbieter. Sie
sendet nichts, was nicht im Kostensatz steht. Sie schreibt nicht in eine Ihrer Tabellen. Sie sieht aus einem VFP,
das als Administrator läuft, kein für Ihren Benutzer registriertes AIXL (Windows lässt das nicht zu). Und sie
kopiert AIXL nicht: Ohne AIXL gibt es nur den Eintrag, der sagt, was fehlt.

Die Optionen stehen in `"options": { "data": { ... } }`:

| Option | Standard | |
|---|---|---|
| `json.enabled` | `.T.` | `.F.` schaltet das JSON-Modul ab: kein **Tabelle als JSON**, kein **JSON als Cursor**, kein `ide_data_to_json` und kein `ide_data_from_json` |
| `script.enabled` | `.T.` | `.F.` schaltet die Skripte ab: kein **Tabelle als Skript**, kein **Dialekt** und kein `ide_data_script` |
| `script.dialect` | `sqlserver` | `vfp`, `sqlserver`, `mysql`, `postgresql`, `sqlite` oder `firebird`; **Dialekt >** schreibt es |
| `script.utf8` | `.F.` | `.T.`: Die `.sql` wird in UTF-8 mit BOM geschrieben (die von Firebird ohne BOM) und mit der Anwendung von Windows geöffnet, nie im Editor von VFP; die `.prg` bleibt in CP1252. **Dialekt >** ändert es nicht |
| `connections.enabled` | `.T.` | `.F.` schaltet die Verbindungen ab: kein **Verbindungen** und keines der fünf `ide_data_db_*` |
| `connections.createViewUpdatable` | `.T.` | `.F.`: **Aktualisierbar** ist in **Sicht erstellen...** nicht markiert, auch wenn die Tabelle einen Primärschlüssel hat. Das Fenster schreibt es, wenn Sie das Kästchen markieren oder die Markierung wegnehmen |
| `ai.enabled` | `.T.` | `.F.` schaltet KI ab: kein **KI** und keine der sechs `ide_data_ai_*` |
| `ai.aixlDir` | leer | Der Ordner von `aixl.prg`, wenn die Registry nicht dorthin führt |
| `ai.config` | leer | Der Pfad einer `aixl.config.json` (ein relativer, vom Datenordner von FoxDock aus); leer, die im Ordner von `aixl.prg`. Sie zählt nur, wenn keiner Ihrer Anbieter aktiv ist |
| `ai.provider` | leer | Der aktive Anbieter; **Anbieter verwalten...** und das Untermenü **Anbieter** schreiben ihn. Die Liste steht in `ai-providers.json` im Datenordner von FoxDock, ohne die Schlüssel |
| `ai.license` | leer | Der Pfad der AIXL-Lizenzdatei; **Anbieter verwalten...** schreibt ihn |
| `ai.mock` | `.F.` | `.T.`: das Double von AIXL, das nichts sendet und mit erfundenen Daten antwortet. Es ist für die Tests und hat keine Leiste. Die Umgebungsvariable `FOXDOCK_AI_MOCK=on` erzwingt es |
| `ai.blockRows` | `200` | Zeilen pro Block, von 1 bis 1000 |
| `ai.agentMaxRows` | `200` | Wie viele Zeilen der Agent in einem Aufruf höchstens senden darf (AGENT-TOOLS_DE.md § 8) |

Für den Agenten gibt es die Tools `ide_data_*`, darunter die sechs `ide_data_ai_*`: AGENT-TOOLS_DE.md § 8.

## Über dieses Handbuch

Dieser Text ist der Abschnitt über `data` aus dem Plugin-Handbuch von FoxDock. Die Verweise auf andere Abschnitte (§) und auf AGENT-TOOLS zeigen auf die Dokumente, die FoxDock in seinem Ordner `docs` installiert.

## Lizenz

MIT. Siehe [LICENSE](LICENSE).
