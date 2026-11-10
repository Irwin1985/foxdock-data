# foxdock-data

The `data` plugin of FoxDock, the plugin system for the Visual FoxPro 9 IDE. Tables, cursors and database connections from the IDE: JSON in and out, export, SQL scripts and an explorer for ODBC servers.

> Also in Spanish ([README_ES.md](README_ES.md)) and German ([README_DE.md](README_DE.md)).

## Install

You need FoxDock and [FoxPack](https://irwinrodriguez.dev/products/foxpack).

- In FoxDock: **FoxDock > Plugins > Plugin center...**, **Available**, choose `data` and press **Install**.
- From a console: `foxpack plugin add data`.

If `data` came with your FoxDock installer, the plugin center shows its new versions in **Updates**.

## The `data` package

**FoxDock > Data** works on the table or cursor selected in data session 1 (the one of the Command
window). With none selected, the bar asks you for a `.dbf`. A `.dbf` opened for this goes `SHARED NOUPDATE`
in a new work area and is closed at the end: FoxDock never writes in your tables, and the record pointer,
the selected work area, `SET DELETED` and `SET POINT` stay as they were. Deleted rows are left out; the
filter and the order of the work area are kept.

| Bar | What it does |
|---|---|
| **Table to JSON** | All the rows to `<table>.json` (UTF-8) in `%LOCALAPPDATA%\FoxDock\data\`, opened with the application Windows has for `.json` (never in the VFP editor: see below); the first 1000 rows also on the clipboard |
| **JSON to cursor** | A cursor `json_1`, `json_2`... in data session 1, with `BROWSE NOWAIT`: from the clipboard if it holds JSON (it starts with `[` or `{`), or else from a `.json` file you choose. The document of **Export...** gives its rows, and with **Schema only**, an empty cursor with its columns. JSON that cannot be read is said in the notice at the top right of VFP, with no dialog |
| **Script table as >** | `CREATE TABLE`, `INSERT` or `UPDATE`, like *Script Table as* in SQL Server Management Studio: `<table>-<kind>.sql`, or `.prg` in the VFP dialect, in the same folder, in CP1252 and opened in the VFP editor |
| **Dialect >** | VFP, SQL Server, MySQL / MariaDB, PostgreSQL, SQLite or Firebird; the one with the mark is the one in use |

The files are written over without asking (it is FoxDock's folder), and the notice at the top right of VFP and the log say
where they went.

**Which encoding, and why.** What you touch up in the VFP editor is in CP1252, the code page of that
editor: the `.sql` and the `.prg` of **Script table as**, with no BOM. The VFP editor saves in CP1252, so a
UTF-8 file touched up there would end up with two encodings mixed. `sqlcmd` and SQL Server Management
Studio read the CP1252 `.sql` as it is on a Western Windows (on another Windows, `sqlcmd -f 1252`). What goes
in UTF-8 is not opened in the VFP editor: it opens with the application Windows has for that kind of file,
and if there is none, the notice at the top right of VFP and the log say where it is.

| Output | Encoding | Opened in |
|---|---|---|
| `.json` (**Table to JSON**) | UTF-8, no BOM | the application of Windows |
| `.sql` (**Script table as**) | CP1252, no BOM | the VFP editor |
| `.sql` with `script.utf8` | UTF-8 with BOM (the one of Firebird, with no BOM) | the application of Windows |
| `.prg` (VFP dialect) | CP1252, no BOM, always | the VFP editor |

Which client wants what: SQL Server (`sqlcmd`, SSMS) and VFP read CP1252. MySQL and MariaDB read it with
`mysql --default-character-set=latin1` (what MySQL calls latin1 is CP1252), or take `script.utf8`.
PostgreSQL reads it with `PGCLIENTENCODING=WIN1252` before `psql`, or takes `script.utf8`. SQLite reads text
as UTF-8: for it, `script.utf8`. Firebird reads it with `isql -ch WIN1252 -i`, in a WIN1252 database and in a UTF8
one; with `script.utf8`, with `isql -ch UTF8 -i`, and its file has no BOM because isql does not take one. The script
has no `COMMIT`: isql commits what was inserted when it ends, and a `QUIT;` added at the end undoes it.

With a big table the IDE does not respond while it writes, and the notice at the top right of VFP counts the rows. As a guide,
100,000 rows with every type took about 16 s to JSON and 19 s to `INSERT` on the machine where it was measured.

How each value goes out:

- **`INSERT`**, one statement per row. **`UPDATE`**, one per row, by the primary or candidate key of the
  CDX (a tag with no filter on one field, or on several joined with `+`, each one as it is or inside `STR()`,
  `ALLTRIM()`, `PADR()` or `DTOS()`: `a+STR(b)` is the key `a, b`); with none, by all the fields, and a comment
  at the top of the script says so. When every column is in the key there is nothing to `SET`: the script
  says so and has no `UPDATE`.
- Text without its trailing spaces; Numeric and Float with the decimals of their field; a Double with the
  value it holds, not with the decimals of the field (the shortest decimal that gives back the same Double:
  `1/3` in a `B(2)` goes as `0.3333333333333333`); dates and datetimes in ISO 8601. `NULL` as `NULL`, and an empty date as `NULL` too (in the VFP dialect, `{}`: there it is a
  value of its own). A memo goes as text. General fields are left out, and a comment and the notice at the top right of VFP
  say which.
- Table and field names quoted as each engine wants: `[name]` in SQL Server, `` `name` `` in MySQL,
  `"name"` in PostgreSQL and SQLite, `"NAME"` in Firebird, and bare in VFP. In Firebird they go in capitals, so
  the table can be read without quotes too.
- In JSON: one object per row, field names in lower case, `null` for `NULL` and for an empty date,
  `true` and `false`, and Varbinary and Blob in base64.
- **JSON to cursor** reads with JSONFox 13.2.0: what **Table to JSON** wrote comes back with the same
  values, and written to JSON again it gives the same text. A Double comes back bit for bit. Varbinary
  and Blob come back as text with their base64: `STRCONV(field, 14)` gives the bytes.

### The types, dialect by dialect

| VFP | SQL Server | MySQL / MariaDB | PostgreSQL | SQLite | Firebird | VFP dialect |
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
| `G` General | left out | left out | left out | left out | left out | left out |

From a table of a connection (**Explore...** > **Script as...**), the type is the VFP letter it arrives as from the server
(the `type` of `ide_data_db_describe`): `bigint`, `uniqueidentifier` and `time` of SQL Server arrive as text, so they go as
such. A binary arrives as a binary, as in everything FoxDock reads from a connection (**Query...**, **Explore...**, the agent's
tools and **Queries**): `binary`, `varbinary` and `rowversion` as `Q`, and `image`, `varbinary(max)`, a `BLOB` or a `bytea` as
`W`, with their bytes. A `varchar(max)` or `nvarchar(max)` arrives as `C(0)` and goes as a memo; a `varbinary(max)` is read
again so that it arrives as `W`, and goes as `VARBINARY(MAX)`.
`ide_data_db_describe` gives the type as **Explore...** reads it: `M` for these two and for a `LONGTEXT` or a
`JSON`, and `W` for a `varbinary(max)` and for the `OCTETS` of Firebird. A column of the primary key is `NOT NULL`, even when the engine
says it allows nulls (SQLite). From Firebird, `BIGINT`, `INT128` and a `NUMERIC` of more than 18 digits arrive as text, `TIME`
arrives as the date and time of 30-12-1899, and a binary `BLOB` arrives as `W`. **Explore...** and **Script as...** read a
`CHAR` or `VARCHAR … CHARACTER SET OCTETS` as a binary, and it goes as `CHAR(n)` or `VARCHAR(n) CHARACTER SET OCTETS`; with
**Query...** it still arrives as text. In MySQL and MariaDB a `LONGTEXT` or a `JSON` is read again with `CAST(x AS CHAR(16777215))`, so it
arrives whole, as a memo; with **Query...** and an SQL of your own, the paragraph below
says what happens. A table of Firebird or PostgreSQL scripted in the dialect of its own engine keeps the names of its catalog, so
a lowercase table of Firebird or an uppercase one of PostgreSQL is created again with its name. A column that still arrives as General is in the `CREATE TABLE` with its type, and the
comment at the top says that its contents are not scripted. In the JSON of `ide_data_db_query` and `ide_queries_run`, Varbinary
and Blob go in base64.

**An SQL of your own** (**Query...** and `ide_data_db_query`): a `varchar(max)`, `nvarchar(max)` or `varbinary(max)` of
SQL Server arrives empty in the first read, and a `LONGTEXT` or `JSON` of MySQL or MariaDB arrives cut at 255 (or 252)
characters. FoxDock then reads the query again on its own, as `SELECT <columns> FROM (<your SQL>) AS q` with the `CAST`
of each one: `IMAGE` and `TEXT` on SQL Server, `CHAR(16777215)` on MySQL and MariaDB; the rows and the row limit are the
same. It does not read it again when your SQL has `ORDER BY` (a derived table does not keep the order), and when the
server does not take the wrapped query (a column without a name, two with the same name, a `WITH`) the first read stays.
Then the notice of **Query...** and `incompleteColumns` in the JSON of `ide_data_db_query` name those columns, each with
the `CAST` to write in your `SELECT`. On MySQL and MariaDB a `LONGTEXT` or a `JSON` is always read again (FoxDock knows it by its type, not by its contents), and with `ORDER BY` it is always named, even when its values are short; on MySQL a `VARCHAR(252)` arrives the same way and is read again too, as a memo. On Firebird nothing is read again: a
`CHAR` or `VARCHAR … CHARACTER SET OCTETS` arrives as text; ask for it with `CAST(x AS BLOB SUB_TYPE BINARY)`.

What has no equivalent, and what is done with it:

- A Character field loses its fixed width: the trailing spaces are not data.
- In SQL Server, text goes as `N'…'` (Unicode). In MySQL, backslashes go doubled, and `CREATE TABLE` ends
  with `DEFAULT CHARSET=utf8mb4`. SQLite has no dates: they go as ISO 8601 text, which its date functions read.
- A key on one field goes as `PRIMARY KEY` in `CREATE TABLE`, and in the VFP dialect as
  `INDEX ON … CANDIDATE` (a free table has no primary key).
- In Firebird nothing goes after the type of a column that allows nulls, and an `N` wider than 18 digits goes as
  `NUMERIC(18,d)`. A line break in a text goes as `ASCII_CHAR(13) || ASCII_CHAR(10)`, because isql leaves the one
  of a literal as LF. A text longer than 20,000 characters or a binary longer than 30,000 bytes goes in pieces
  joined with `||`, and in a memo or a Blob the first one goes inside a `CAST`. A Firebird statement cannot pass
  10,485,760 bytes, so a bigger value does not fit.
- A control character in a text (from `CHR(0)` to `CHR(31)`, except the tab and the line breaks, and `CHR(127)`) goes
  with the function of the engine, so the `.sql` stays text and the value comes back with the same bytes: `NCHAR(n)` in
  SQL Server, `CHAR(n USING utf8mb4)` inside a `CONCAT` in MySQL, `chr(n)` in PostgreSQL, `char(n)` in SQLite and
  `ASCII_CHAR(n)` in Firebird. PostgreSQL does not take a `CHR(0)` in a text, and SQLite keeps it but reads the text cut
  at it: in those two it is taken out of the value, and a comment at the top of the script names the columns.
- A row whose statement does not fit (a VFP string holds 16,777,184 characters at most, and a Firebird statement
  10,485,760 bytes) goes as a comment that says why, the other rows are written, and the notice says how many were
  left out.
- In the VFP dialect a string goes in pieces of 200 characters joined with `+` (a literal cannot pass
  255), control characters as `CHR(n)`, and a value longer than 1000 characters goes empty in the
  statement and is added after it in pieces (`REPLACE` after an `INSERT`, `UPDATE` after an `UPDATE`).

### Connections

**FoxDock > Data > Connections** keeps the connections to your database servers (SQL Server, MySQL,
MariaDB, PostgreSQL, Firebird and SQLite) and opens them from the IDE, through FoxRemote (a library the package asks for
with `requires`: it comes untouched in `lib\foxremote\`). Each connection is a bar with its own submenu:

| Bar | What it does |
|---|---|
| **Connect...** | Connects. When the connection has a `user` and no password kept, a small window asks for it; with **Remember** it is kept, encrypted with your Windows account |
| **Disconnect** | Closes the connection |
| **Explore...** | The window of the connection: its database, its tables and views, and the columns and rows of each (below) |
| **Query...** | A window with a box for a `SELECT`, the most rows to read (**Limit**: 100 to start with, 0 for no limit; it is remembered) and **Run**: the rows, in a `BROWSE`. **To object** puts the result in a variable for the Command window (below) |

Spaces at the end of a password typed in **Connect...** are lost, because the VFP text box pads what you
type with spaces; spaces at the start are kept.

**Explore...** connects first if the connection is not connected (with the password window when it needs
one: then press **Explore...** again). It opens one window per connection, **FoxDock - <name>**; pressing it
again brings that window to the front. In it:

- **Database**: the database the connection is in, and a list of the databases of the server you can open
  (SQL Server, MySQL, MariaDB and PostgreSQL). Choosing another one moves the connection there, reloads the
  list of tables and says so in the log; the agent's tools read that database from then on. For SQLite and
  Firebird the database is the file, and the list is greyed out. Changing database opens a new connection
  to the server: with a password, FoxDock can do it only if the password was kept (**Remember**); if not,
  the window says so and the connection stays where it was.
- **Filter**: type part of a name and the list keeps the tables and views that contain it (capitals do not
  matter); **Enter** takes you to the list, on its first row. Next to it, **Tables and views**, **Tables** or
  **Views** (greyed out when the database has only one kind; with both, it starts on **Tables**), and below, how many
  pass both, out of the ones the combo lets through: **N of M tables**, **N of M views** or **N of M tables and views**.
- The list: each table or view of the database, with `table` or `view` beside it.
- **Columns**: the columns of the one you chose (name, VFP type, width, decimals, nulls and whether it is in
  the primary key), in a `BROWSE`. Its title says the key.
- **Browse**: the first **Limit** rows of the one you chose, in a `BROWSE`. **Limit** is the one of
  **Query...** (100 to start with, 0 for no limit; it is remembered), and the title says when it stopped
  there. With 0 and a big table the IDE waits until the rows arrive (250,000 rows took about a second).
- **To object**, with the **Variable** box beside it: the rows of the one you chose, in a variable for the Command
  window (below, after the `BROWSE` windows).
- **Export...**: the one you chose, to a file, in a small window:
  - **the format**: `.dbf` (a free table: VFP's types; `bigint` and `uuid` come as text, `datetime2` loses its
    fraction, and a column name longer than 10 letters is cut, because a free table allows no more), `.json` (UTF-8
    without a BOM: an object with `table`, `connection`, `columns` and `rows`, the rows of **Table to JSON**; with
    **Schema only**, without `rows`; **JSON to cursor** reads it back) or `.csv` (separator `;`, `,` or tab; CP1252 or UTF-8 with a
    BOM; a header row, quotes only around a text that has the separator, a quote or a line break, numbers with a
    point, dates as `2026-11-01` and `2026-11-01T10:20:30`, an empty field for NULL);
  - **To a file** or **To the clipboard** (JSON and CSV; a `.dbf` only to a file): with the clipboard, the folder, the
    name, **Replace it**, **Open it** and the encoding do not count, and the notice says how many rows and characters
    went;
  - **the folder and the name** (to start with, `%LOCALAPPDATA%\FoxDock\data\` and `<table>.<ext>`);
  - **the rows**: all of them, or the first N (the number can be typed only with **The first**); above, how many the server has (`SELECT COUNT(*)`), and the notice
    says how many went;
  - a file that is there is not written over unless you mark **Replace it**: the window says so, not VFP;
  - with **Open it** (marked to start with; unmark it when an agent drives Export...), the `.json` and the `.csv` in
    UTF-8 open with their Windows application, and the CP1252 `.csv` in a text editor of VFP (CP1252 is its own: the
    accents look right; in UTF-8 they would not). The notice says with what it opened. The `.dbf` does not open,
    and the notice says where it is;
  - a file open in an editor of VFP, or held by another program (Excel keeps a `.csv` it has open), is not written:
    the window says so. Close it first.
- **Create view...**: a remote view of VFP of the one you chose, in a `.dbc`:
  - **the database**: the one open in VFP, one in the folder of the open project, or a new one with the name you
    type (without a project, in `%LOCALAPPDATA%\FoxDock\data\`);
  - **the name** of the view (it may not be the name of a table in the `.dbc`; the name of one of its views, yes:
    see **Replace** below), **the columns** in alphabetical order
    (all marked to start with; **All**, **None** or **Ctrl+A** in the list; the view keeps the order of the
    table), an optional **WHERE** (the server checks it: what it says, the window says);
  - **Updatable**, when the table has a primary key: `TABLEUPDATE()` then sends your changes to the server. With a
    key it is marked to start with; without one, it is off. If you unmark it, the next window opens unmarked: it is
    kept in `config.json`, in the option `connections.createViewUpdatable` (below). On
    SQLite, the `TEXT` columns stay out (they are memo in VFP, and a view does not write them), and the text comes
    as the UTF-8 that SQLite keeps: `STRCONV(<field>, 11)` gives the accents back. A column that **Explore...** reads again with a
    `CAST` goes in the view with the same one, and arrives whole: on SQL Server, a `varbinary(max)` as `IMAGE` (a Blob)
    and a `varchar(max)` or `nvarchar(max)` as `TEXT` (a memo); on MySQL and MariaDB, a `LONGTEXT` or a `JSON` as
    `CHAR(16777215)` (a memo). A `JSON` of MySQL stays out of the updatable columns (VFP cannot save it back), and the
    `OCTETS` of Firebird go without a `CAST`, as `C(n)` or `V(n)`: with one, saving them would write nothing. Such a `CHAR(n)` is a `C(n)` in VFP: a shorter value
    is saved padded with spaces, as in any `C` field;
  - **no password in the `.dbc`**: the connection in it has the connection string without the password, also while
    the view is being made. While FoxDock creates it, the password goes in a temporary `.dsn` file in the temporary
    folder of your user (`%TEMP%\foxdock-*.dsn`), which FoxDock deletes when it ends, also if the view fails. And the
    connection never asks (`DispLogin` 3), so creating opens no window. Once the view
    is made, it stays with `DispLogin` 1. Without a password (Windows authentication, SQLite), `OPEN DATABASE` and
    `USE <view>` open it. With one, `USE <view>` typed on its own and Modify in the database designer
    (`MODIFY DATABASE`, right click on the view) ask for it in the login window of the driver, instead of failing
    with error 1526 («Connectivity error»); the window says so when it makes the view. To open it without being
    asked, give the password when you open the view, as the window shows:
    `USE <view> CONNSTRING DBGETPROP("<connection>", "Connection", "ConnectString") + "PWD=<the password>"`.
  - **If you made views with a password with an earlier version** (up to 0.9.31) in a `.dbc` that was already there,
    or a second view in the same `.dbc`: those versions left the connection string with the password in loose blocks
    of the `.dct` file of the `.dbc`. The connection itself was clean, but the password was still in the file.
    `PACK DATABASE`, with the `.dbc` open exclusively and nothing of it open, removes it. 0.9.32 no longer does it.
  - **The WHERE, tried first**: with a **WHERE**, **Create view...** tries it first with the engine, with a SELECT that
    brings no rows through the connection of FoxDock. A column or a function that is not there makes no view, and the
    window says the error of the engine. It does not see a type that does not match (`id = 'abc'`), which fails when
    the view opens. A view with parameters (`?x`) is not tried. A **WHERE** that ends in a comment (`-- …`) is not
    taken: remove the comment.
  - **A view that fails** leaves the connection of the `.dbc` as a good one leaves it, asking for the password in the
    window of the driver (not with error 1526), and leaves its line in the log with the reason.
  - **Create** makes the view and turns itself off as soon as it is made, so a second click does not make another
    one. It turns on again when you change something that would make a different view: the name, the database, the
    columns, the **WHERE** or the **Updatable** box.
  - With a name the chosen `.dbc` already has as a view, the button says **Replace**, and the window explains it
    before you press it: «The view X already exists in Y.dbc: Replace makes it again with what is above.».
    **Replace** drops the view (`DROP VIEW`) and makes it again with what is in the window. It refuses when that view
    is open in the IDE («USE IN <view> closes it»), because VFP would keep its cursor. With the name of a table of
    the `.dbc` there is no **Replace**: it refuses, as always, and the window says so.
  - **Open**, next to **Create**, does it for you once the view is made: it opens the `.dbc` (or chooses it, if it is
    open), opens the view in a free work area of the IDE's data session (as if you had typed it), with the row limit
    of **Query...**, and shows it in a `BROWSE`. The view stays open when you close the window: it is yours, not one
    of the window's cursors. Pressed again, it reads the view again instead of opening a second copy. With a
    password, it uses the one kept with **Remember** in **Connect...**, without showing it, and passes it in
    `CONNSTRING`, so it does not ask; FoxDock does not keep a
    password you only typed, so then **Open** opens nothing, says so, and the lines above are the way.
- **Script as...**: the `CREATE TABLE`, `INSERT` or `UPDATE` of the one you chose, without opening it, in a small window: the
  dialect (to start with, the one of the engine of the connection, and the one of MySQL for MariaDB; changing it here is for this time only), the rows (all, or the first N, whose number
  can be typed only with **The first**; not for `CREATE TABLE`), and where it goes: **To the editor** (the file of **Script table as**, `<table>-<kind>.sql` or `.prg` in
  `%LOCALAPPDATA%\FoxDock\data\`, opened as that one opens it) or **To the clipboard**. The columns and the primary key come
  from the server, not from the rows (see below the table of types); `UPDATE` goes by the columns of the key, one or several, and
  by all the fields when it has none, and a comment in the script says which. The names are quoted as the dialect of the
  script wants them. Nothing stays open in the IDE.

Both `BROWSE` windows are read-only: you cannot change, add or delete a row. Their cursors are
`c_<connection>_<table>_columns` and `c_<connection>_<table>`, and they close with the window unless you mark
**Keep the cursors open when it closes** (unmarked to start with; it is remembered, and the notice says which
stay open). **Query...** has the same box for its cursor. **Disconnect**, **Reload** or turning the package off
closes the window and those cursors with it, box or not. What the window has to say goes in its box at the bottom, in the notice at the top
right of VFP and in the log.

**To object, for the Command window.** **Query...** and **Explore...** have a **To object** button with a
**Variable** box beside it. In **Query...** it takes the result of the last **Run**; in **Explore...**, the rows of
the table or view you chose, up to the **Limit** of the window (the same as **Browse**). It makes a `Collection` with
one object per row, with the columns as properties, and leaves it in a `PUBLIC` variable. It has to be `PUBLIC`: from
a window, `_VFP.SetVar` would leave a private variable that goes away on return, and only a `PUBLIC` one reaches the
Command window. With the box empty, it puts `lo` and the name of the table in it (`loOrders`, `loG10_cl`); in
**Query...**, the name of the cursor of the result (`loC_shop_query`). It refuses a name that is not a VFP variable
name and a variable that already exists: it overwrites nothing. With no rows, it makes nothing. The window says how many rows, that the variable is `PUBLIC` and that `RELEASE loOrders` removes it,
and how to use it in the Command window: `? loOrders.Count`, `? loOrders.Item(1).<column>`.

At the end of the submenu, **Edit connections...** opens the window **FoxDock - Connections**: the connections of
the two files, with their id, name, engine, where they are (the project or yours) and whether they are connected.
**New...** and **Edit...** open **FoxDock - Connection**, with the fields of the file and no password (Connect...
asks for it): it says what does not fit (an id taken in either file, an empty name, a password in a field) and
then writes nothing. **Save** rewrites the whole file in one format, the one of the example, and keeps the keys it
does not know; with the file open in the editor it does not save. **Delete** asks in the window, disconnects the
connection and forgets its kept password. **Open the file...** opens `connections.json` in the editor, as before
(the one of the open project, or yours when no project is open; with an example of two connections, SQLite and SQL
Server, if there was none), and **Reload** reads the files again. There is one connection per object of the array,
and each one is an entry of the **Connections** submenu, with its **Connect...**, **Disconnect**,
**Explore...** and **Query...**: to choose a connection, open its submenu. Nothing opens a VFP dialog: what goes wrong is said in the notice at the top right of VFP and in the log. The reason of a failure is the same text the agent tools give.

**The state, in the menu.** A connection that is connected says so after its name, **Shop (connected)**, and only the bar that
makes sense can be pressed, **Connect...** or **Disconnect**. The menu changes when you connect, disconnect or reload, and when a
connection is lost. **A lost connection is said**: when the server stops answering (the network, a restart of the server), the
first thing that reads from it notices, closes its **Explore...** window with its cursors, and says so in the notice and in the
log. The notice says the important part first, «The connection Shop was lost. Connect again from FoxDock > Data > Connections.»,
and then the reason the driver gave, cut to fit; the log keeps the whole message. **Reload** keeps the connections that
are connected; one whose definition changed in the file (`server`, `port`, `database`, `user`, `driver` or `windowsAuth`) is
disconnected, and the notice says so. **Reload plugins** (FoxDock > Plugins) is another thing: it unloads the package and closes
every connection.

**Two files, and no password in either.** `connections.json` in the folder of the open project (it goes
with the project, so it can be shared) and `%LOCALAPPDATA%\FoxDock\connections.json` (yours). Both are
read: the project's come first and say `(project)` in the menu, and with the same `id` in both, the
project's one stays. A file is a JSON array:

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

| Field | What it is |
|---|---|
| `id` | Letters, digits, `_`, `-` and `.`; the agent names the connection by it |
| `name` | What the menu shows |
| `engine` | `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird` or `sqlite` |
| `server`, `port`, `database` | Where it is. An empty `database` (SQL Server, MySQL, MariaDB, PostgreSQL) is a connection to the server, in the database the server gives (**Explore...** says which, and changes it); on SQL Server, **Query...** also reads another database of the same server with a three-part name (`sales.dbo.customers`). With SQLite and Firebird, `database` is the file and cannot be empty |
| `user` | Empty with `windowsAuth`, and with SQLite |
| `driver` | The ODBC driver; empty, the one in the table below |
| `windowsAuth` | `true`: Windows authentication (SQL Server), and no password |
| `allowWrite` | `true`: the agent may write through this connection with `ide_data_db_execute`, with agent role 10 or higher. `false` when it is not there |
| `agentCanRead` | `true`: the agent may read through this connection. `false` when it is not there |

A file with a password in it (a `password`, `pwd`, `passwd`, `secret` or `pass` key, or `pwd=` inside a
value) is not read at all, and the log says which connection and which key, never the value. The password
goes apart: **Remember** in **Connect...** keeps it in `%LOCALAPPDATA%\FoxDock\secrets\<id>.cred`,
encrypted with your Windows account (DPAPI), so only your Windows user on this machine can read it back.
Delete that file to forget it.

**`agentCanRead`, connection by connection.** What the agent reads leaves your machine for the provider of
the AI. With customer data that is your decision, so it is off until you put `"agentCanRead": true` in that
connection and press **Reload**. With that alone the agent only reads: one `SELECT`, 1000 rows at most
(AGENT-TOOLS_EN.md § 8). That check stops the obvious, and a server
function can still write from inside a `SELECT`. For a connection the agent reads, use a user of the server that
can only read.

**`allowWrite`, connection by connection.** The agent writes on a server only through `ide_data_db_execute`, and
only with two keys on: `"allowWrite": true` in that connection (then **Reload**) and agent role 10 or higher
(FoxDock > FoxAgent > Agent role). It sends one statement at a time (`INSERT`, `UPDATE`, `DELETE`, `CREATE`,
`ALTER`, `DROP` or `TRUNCATE`); an `UPDATE` or a `DELETE` without `WHERE`, a `DROP` and a `TRUNCATE` also need
`wholeTable`. Each statement is committed when it returns, and `foxdock.log` keeps every one, with its rows and
its time, and every one refused, with the reason. For a connection the agent writes on, use a user of the server
that can only touch what it should.

**The drivers.** Visual FoxPro is a 32-bit program, so it needs the **32-bit ODBC driver** of each engine,
also on 64-bit Windows (VFP Advanced of 64 bits needs the 64-bit one). **Connect...** without the driver
says which one it expected. These are the ones FoxRemote is tested with:

| Engine | `driver` |
|---|---|
| SQL Server | `ODBC Driver 18 for SQL Server` or `ODBC Driver 17 for SQL Server` |
| MySQL, MariaDB | `MariaDB ODBC 3.2 Driver` (Oracle's MySQL driver is broken for VFP from 8.0.35 on) |
| PostgreSQL | `PostgreSQL ANSI` (psqlODBC) |
| Firebird | `Firebird ODBC Driver` 3.0, and the 32-bit `fbclient.dll` |
| SQLite | `SQLite3 ODBC Driver` |

### AI

**FoxDock > Data > AI** puts AIXL to work on the table or cursor you have open in the IDE: one label per row
(**Classify column...**), one column per key (**Extract from column...**), a copy of a column without names or
phones (**Anonymize column...**), the rows that pass a prompt (**Filter rows...**) and one question about the
whole table (**Ask about the table...**). **AIXL is a product of its own, sold apart: FoxDock does not bring it
and does not copy it.** You install AIXL from its zip and run `register.cmd` in its folder; its licence and the
key of your providers go in **AI > Provider > Manage providers...** (below): as many as you have, and you switch from
one to another with one click.

Without AIXL, or with an AIXL that cannot start, **AI** has one bar that says why. Pressing it puts the whole
sentence in the notice at the top right of VFP and in the log, and opens irwinrodriguez.dev in your browser:

| Bar | When | What to do |
|---|---|---|
| **AIXL is not installed...** | `AIXL.Host` is not registered on this machine | Install AIXL 1.1.3 or later and the .NET 10 runtime for x86, and run `register.cmd` in its folder |
| **AIXL found, but not its aixl.prg...** | `AIXL.Host` is registered, but `aixl.prg` is not next to its DLL (registered from another folder, for example); the sentence says the path of the DLL | Run `register.cmd` from the folder of the AIXL zip, or set `ai.aixlDir` (below) to the folder of `aixl.prg` |
| **AIXL is not seen: the IDE runs as administrator...** | Your VFP runs as administrator, and Windows does not let an elevated program see an AIXL registered for your user (AIXL says `'HOST_ELEVATED'`) | Start VFP without *Run as administrator*, or run AIXL's `register-machine.cmd` once as administrator (the AIXL manual, § 3.3) |
| **AIXL did not start...** | Anything else AIXL says (`"DOTNET_RUNTIME_MISSING"`, `"HOST_IS_64BIT"`...), or a version older than 1.1.3 | The code AIXL gave, in quotes, is in the notice and in the log: FoxDock does not make up a diagnosis |

FoxDock does not start AIXL when the IDE opens: it reads the registry only, in about a millisecond. It starts it
the first time you use **AI** (about a third of a second, while the .NET runtime loads), and that is when a VFP
that runs as administrator is found out: the submenu turns into the bar that says so. `aixl.prg` is not compiled in the
folder of AIXL: FoxDock copies it to its code cache of each engine (`fxp\<engine>\aixl\` in its data folder), like
the code of the plugins, and loads it from there. So a VFP 9 and a VFPA open at the same time do not tread on each
other's `.fxp`, and the folder of AIXL may be read-only. If `aixl.prg` does not load or does not run, the bar is
**AIXL did not start...**, with the code `AIXL_LOAD_FAILED` and the error of VFP in the notice and the log, and the
tools answer the same.

With AIXL ready, the submenu is:

| Bar | What it does |
|---|---|
| **Classify column...** | One label per row of a text or memo column |
| **Extract from column...** | One column per key of a schema, from a text or memo column |
| **Anonymize column...** | A copy of a text or memo column without what you say (names, phones...) |
| **Filter rows...** | Marks in `aixl_keep` the rows that pass; nothing is deleted |
| **Ask about the table...** | One question about the whole table: the answer, not a column |
| **Provider: ...** | A submenu with the name of the one in use: your providers, with the mark on the one in use (one click and the operations go to another one, from that moment), and **Manage providers...**. FoxDock never switches by itself: if a provider runs out of credit, the operation fails with what the provider said, and you choose another one here |
| **Manage providers...** | The window of your providers: a list with **New**, **Save**, **Delete** (press it twice: there is no dialog) and **Use this one**. Each one has a name, the provider, the model (a list with the models of that provider, the first being the one AIXL uses by default; you can also write another), the key and the local server (only for an AI on your own machine, such as Ollama or LM Studio). **The key, in one of two ways**: saved encrypted with your Windows account (DPAPI: only your user, on this machine, can read it), or read from an environment variable each time it is used (the one you created, by its name: the window proposes none, and says whether it is found and how long it is). If you delete the one in use, none is in use: the operations are off until you choose another, and the notice says so. Below, **the AIXL licence**, one for every provider: the file of your licence, or its text pasted in the box (it starts with `eyJ`), which is saved as `aixl.lic` in the data folder of FoxDock. The key is never shown, nor written in clear in any file, nor sent to the log or to the agent |
| **Last run: ...** | Greyed out: the rows, the tokens and the seconds of the last operation |

**Without a provider, the five operations are greyed out**, and their bar says what to do: first add one in
**Manage providers...**. Their tools answer `NO_PROVIDER` without sending anything.

The AIXL session is one per IDE. What you do from the Command window (`AIXL_USE_MOCK()`,
`AIXL_CONFIGURE_FROM_FILE()`) is the same session the menu shows, and the menu reads it from AIXL, not from what
it asked for.

**The windows.** Each one has the table, in a list with the tables and cursors open in data session 1 (Classify,
Extract and Anonymize only list the ones with a text or memo column); it opens on the one selected, or on a `.dbf`
you choose when none is. And its
own fields. Classify, Extract and Anonymize ask for the column (text or memo) and the destination, with the names
it will add written underneath in grey; Classify also for the labels (a closed list, `high,medium,low`; empty, the
model chooses), Extract for the schema (`priority,department`; empty, the model chooses the keys) and Anonymize
for what to remove. Filter asks for the prompt (which rows pass), the columns the model sees (empty: the whole
row) and **Also a new cursor with the rows that pass**; Ask, for the question and the columns. All but Ask have
**Rows per block** (200; from 1 to 1000).

Under the fields, **the cost sentence**, written again just before **Run** from what the AIXL session has:
«This sends 300 rows of ventas.notas to deepseek (deepseek-chat) from your own account.», or «Mock mode: nothing
is sent and nothing is paid.». The rows are the ones you see: the filter and `SET DELETED` count. What is sent is
paid on your account with your provider (the AIXL manual, § 11, says how much).

**Run** goes block by block: the status bar and the window count the rows («AI: 150 of 500 rows (block
3/10)»). **Esc** stops at the end of the block that is running: what was done stays, and the new columns of the
rest are `.NULL.` («AI: stopped after block 3: 150 rows done, 350 left as NULL»). During a run the window does not
close with Esc. Ask is one question about the whole table: no blocks and no Esc.

**The copy.** AIXL adds its columns at the end of the cursor and fills them; it never rewrites a row nor moves
one. A read-only cursor (a `SELECT ... INTO CURSOR` without `READWRITE`) cannot take new columns, and FoxDock never
writes in a table of yours, also when you have it open `SHARED` and writable. In both cases the operation works on
a copy, `ai_<name>`, `READWRITE`, with the rows you see, in data session 1, and the window says so before Run. The
original stays as it was. Ask writes nothing and needs no copy.

| Operation | What it leaves |
|---|---|
| Classify | `<into>`, `<into>_con` and `<into>_rea` (the label, how sure, and why), at the end, cut to ten characters. The destination it proposes is `ai_<column>` cut to six, so that the three fit |
| Extract | `<into>` and `<into>_<key>` for each key, cut to ten; without a schema, the keys the model chooses. The destination it proposes is `ax_<column>` cut to six, not the one of Classify. Two keys that give the same name at ten characters are refused before Run. A key the text does not have comes back empty, and that is not an error |
| Anonymize | `<into>` (it proposes `ai_<column>`, up to ten) with the text without what you said |

If any of the columns it is going to leave is already in the table, the window says so under the destination, before **Run**: Run writes over it.
| Filter | `aixl_keep`, logical: `.T.` in the rows that pass. Nothing is deleted. With the box, also a cursor `ai_<name>_kept` with them |
| Ask | The answer, in the window and in the log; no column. The model reads only the first 4,000 characters of what is sent: the cost sentence says so, and when it did not read it all (AIXL's `INPUT_TRUNCATED`), the status bar says so too |

At the end there is a `BROWSE` of the cursor (of the copy, or of `ai_<name>_kept` when you asked for it), and the
status bar and the log say the rows, the failed ones, the tokens and the seconds («AI: classified ventas.notas
into ai_not: 500 rows ok, 0 failed, ...»). AIXL's warnings go to the log (`COLUMN_RENAMED`, `COLUMN_WIDENED`), and
when a row failed, a cursor `ai_errors` with them opens in a second `BROWSE`. **Last run** says the numbers. When
AIXL answers with no row done (`NO_DATA`, `LICENSE_*`, `PROVIDER_*`...), its code in quotes and its text go to the
notice, the window and the log.

**What it does not do.** It never writes the key of your provider in clear: either it is saved encrypted with your
Windows account, or it is read from its environment variable each time. It never changes provider by itself. It sends nothing that
is not in the cost sentence. It does not write in a table of yours. It does not see an AIXL registered for your
user from a VFP that runs as administrator (Windows does not let it). And it does not copy AIXL: without it,
there is only the bar that says what is missing.

The options go in `"options": { "data": { ... } }`:

| Option | Default | |
|---|---|---|
| `json.enabled` | `.T.` | `.F.` switches the JSON module off: no **Table to JSON**, no **JSON to cursor**, no `ide_data_to_json` and no `ide_data_from_json` |
| `script.enabled` | `.T.` | `.F.` switches the scripts off: no **Script table as**, no **Dialect** and no `ide_data_script` |
| `script.dialect` | `sqlserver` | `vfp`, `sqlserver`, `mysql`, `postgresql`, `sqlite` or `firebird`; **Dialect >** writes it |
| `script.utf8` | `.F.` | `.T.`: the `.sql` goes in UTF-8 with BOM (the one of Firebird, with no BOM) and opens with the application of Windows, never in the VFP editor; the `.prg` stays in CP1252. **Dialect >** does not change it |
| `connections.enabled` | `.T.` | `.F.` switches the connections off: no **Connections**, and none of the five `ide_data_db_*` |
| `connections.createViewUpdatable` | `.T.` | `.F.`: **Updatable** comes unmarked in **Create view...**, even when the table has a primary key. The window writes it when you mark or unmark the box |
| `ai.enabled` | `.T.` | `.F.` switches AI off: no **AI** and none of the six `ide_data_ai_*` |
| `ai.aixlDir` | empty | The folder of `aixl.prg`, when the registry does not lead to it |
| `ai.config` | empty | The path of an `aixl.config.json` (a relative one, from the data folder of FoxDock); empty, the one in the folder of `aixl.prg`. It only counts when none of your providers is in use |
| `ai.provider` | empty | The provider in use; **Manage providers...** and the **Provider** submenu write it. The list is in `ai-providers.json` in the data folder of FoxDock, without the keys |
| `ai.license` | empty | The path of the AIXL licence file; **Manage providers...** writes it |
| `ai.mock` | `.F.` | `.T.`: AIXL's double, which sends nothing and answers with made-up data. It is for the tests and has no bar. The environment variable `FOXDOCK_AI_MOCK=on` forces it |
| `ai.blockRows` | `200` | Rows per block, from 1 to 1000 |
| `ai.agentMaxRows` | `200` | The most rows the agent may send in one call (AGENT-TOOLS_EN.md § 8) |

For the agent there are the `ide_data_*` tools, the six `ide_data_ai_*` among them: AGENT-TOOLS_EN.md § 8.

## About this manual

This text is the section about `data` of the FoxDock plugin manual. The references to other sections (§) and to AGENT-TOOLS point to the documents FoxDock installs in its `docs` folder.

## License

MIT. See [LICENSE](LICENSE).
