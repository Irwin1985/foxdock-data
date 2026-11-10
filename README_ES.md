# foxdock-data

El plugin `data` de FoxDock, el sistema de plugins para el IDE de Visual FoxPro 9. Tablas, cursores y conexiones a bases de datos desde el IDE: JSON de ida y vuelta, exportar, scripts SQL y un explorador de servidores ODBC.

> También en inglés ([README.md](README.md)) y en alemán ([README_DE.md](README_DE.md)).

## Instalar

Hacen falta FoxDock y [FoxPack](https://irwinrodriguez.dev/products/foxpack).

- En FoxDock: **FoxDock > Plugins > Centro de plugins...**, **Disponibles**, elige `data` y pulsa **Instalar**.
- Desde una consola: `foxpack plugin add data`.

Si `data` vino con tu instalador de FoxDock, el centro de plugins enseña sus versiones nuevas en **Actualizaciones**.

## El paquete `data`

**FoxDock > Datos** (FoxDock > Data) trabaja sobre la tabla o el cursor seleccionado en la sesión de datos 1 (la de la
ventana de comandos). Si no hay ninguno, la barra te pide un `.dbf`. Un `.dbf` que se abre para esto va
`SHARED NOUPDATE` en un área nueva y se cierra al terminar: FoxDock no escribe nunca en tus tablas, y el
puntero, el área seleccionada, `SET DELETED` y `SET POINT` quedan como estaban. Las filas borradas no
salen; el filtro y el orden del área se respetan.

| Barra | Qué hace |
|---|---|
| **Tabla a JSON** (Table to JSON) | Todas las filas a `<tabla>.json` (UTF-8) en `%LOCALAPPDATA%\FoxDock\data\`, abierto con la aplicación que Windows tenga para `.json` (nunca en el editor de VFP: ver abajo); las 1000 primeras, además, al portapapeles |
| **JSON a cursor** (JSON to cursor) | Un cursor `json_1`, `json_2`... en la sesión de datos 1, con `BROWSE NOWAIT`: del portapapeles si tiene JSON (empieza por `[` o `{`), y si no, de un `.json` que eliges. Del documento de **Exportar...** salen sus filas, y con **Solo esquema** (Schema only), un cursor vacío con sus columnas. Un JSON que no se puede leer se dice en el aviso de arriba a la derecha de VFP, sin diálogo |
| **Script de la tabla como >** (Script table as) | `CREATE TABLE`, `INSERT` o `UPDATE`, como *Script Table as* de SQL Server Management Studio: `<tabla>-<tipo>.sql`, o `.prg` en el dialecto VFP, en la misma carpeta, en CP1252 y abierto en el editor de VFP |
| **Dialecto >** (Dialect) | VFP, SQL Server, MySQL / MariaDB, PostgreSQL, SQLite o Firebird; el de la marca es el que se usa |

Los ficheros se sobrescriben sin preguntar (es la carpeta de FoxDock), y el aviso de arriba a la derecha de VFP y el log dicen
dónde quedaron.

**Qué codificación, y por qué.** Lo que retocas en el editor de VFP va en CP1252, la página de códigos
de ese editor: el `.sql` y el `.prg` de **Script de la tabla como**, sin BOM. El editor de VFP guarda en CP1252, así
que un fichero UTF-8 retocado allí quedaría con dos codificaciones mezcladas. `sqlcmd` y SQL Server
Management Studio leen el `.sql` en CP1252 tal cual en un Windows occidental (en otro Windows,
`sqlcmd -f 1252`). Lo que va en UTF-8 no se abre en el editor de VFP: se abre con la aplicación que Windows
tenga para ese tipo de fichero, y si no tiene ninguna, el aviso de arriba a la derecha de VFP y el log dicen dónde está.

| Salida | Codificación | Se abre en |
|---|---|---|
| `.json` (**Tabla a JSON**) | UTF-8, sin BOM | la aplicación de Windows |
| `.sql` (**Script de la tabla como**) | CP1252, sin BOM | el editor de VFP |
| `.sql` con `script.utf8` | UTF-8 con BOM (el de Firebird, sin BOM) | la aplicación de Windows |
| `.prg` (dialecto VFP) | CP1252, sin BOM, siempre | el editor de VFP |

Qué cliente quiere qué: SQL Server (`sqlcmd`, SSMS) y VFP leen CP1252. MySQL y MariaDB lo leen con
`mysql --default-character-set=latin1` (lo que MySQL llama latin1 es CP1252), o toman `script.utf8`.
PostgreSQL lo lee con `PGCLIENTENCODING=WIN1252` antes de `psql`, o toma `script.utf8`. SQLite lee el texto
como UTF-8: para él, `script.utf8`. Firebird lo lee con `isql -ch WIN1252 -i`, en una base WIN1252 y en una UTF8;
con `script.utf8`, con `isql -ch UTF8 -i`, y su fichero va sin BOM porque isql no lo acepta. El script no lleva
`COMMIT`: isql confirma lo insertado al acabar, y un `QUIT;` añadido al final lo deshace.

Con una tabla grande el IDE no responde mientras escribe, y el aviso de arriba a la derecha de VFP cuenta las filas. Como
orientación, 100.000 filas con todos los tipos tardaron unos 16 s a JSON y 19 s a `INSERT` en la máquina
donde se midió.

Cómo sale cada valor:

- **`INSERT`**, una sentencia por fila. **`UPDATE`**, una por fila, por la clave primaria o candidata del
  CDX (una etiqueta sin filtro sobre un campo, o sobre varios unidos con `+`, cada uno tal cual o dentro de
  `STR()`, `ALLTRIM()`, `PADR()` o `DTOS()`: `a+STR(b)` es la clave `a, b`); si no hay, por todos los campos, y
  un comentario al principio del script lo dice. Si todas las columnas están en la clave no hay nada que
  poner en el `SET`: el script lo dice y no lleva ningún `UPDATE`.
- El texto sin los espacios del final; los Numeric y Float con los decimales de su campo; un Double con el
  valor que guarda, no con los decimales del campo (el decimal más corto que devuelve el mismo Double: `1/3`
  en un `B(2)` va como `0.3333333333333333`); las fechas y las fechas con hora en ISO 8601. `NULL` como `NULL`, y una fecha vacía también como `NULL` (en el dialecto VFP,
  `{}`: ahí es un valor propio). Un memo va como texto. Los campos General no salen, y un comentario y la
  aviso de arriba a la derecha de VFP dicen cuáles.
- Los nombres de tabla y de campo entrecomillados como quiere cada motor: `[nombre]` en SQL Server,
  `` `nombre` `` en MySQL, `"nombre"` en PostgreSQL y SQLite, `"NOMBRE"` en Firebird, y sin comillas en VFP. En
  Firebird van en mayúsculas para que la tabla se lea también sin comillas.
- En JSON: un objeto por fila, los nombres de campo en minúsculas, `null` para `NULL` y para una fecha
  vacía, `true` y `false`, y Varbinary y Blob en base64.
- **JSON a cursor** lee con JSONFox 13.2.0: lo que escribió **Tabla a JSON** vuelve con los mismos
  valores, y sacado otra vez a JSON da el mismo texto. Un Double vuelve bit a bit. Varbinary y Blob
  vuelven como texto con su base64: `STRCONV(campo, 14)` da los bytes.

### Los tipos, dialecto a dialecto

| VFP | SQL Server | MySQL / MariaDB | PostgreSQL | SQLite | Firebird | Dialecto VFP |
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
| `G` General | no sale | no sale | no sale | no sale | no sale | no sale |

De una tabla de una conexión (**Explorar...** > **Script como...**), el tipo es la letra de VFP con la que llega del servidor
(el `type` de `ide_data_db_describe`): `bigint`, `uniqueidentifier` y `time` de SQL Server llegan como texto, y `varbinary`
como memo, y así van. Un `varchar(max)` o `nvarchar(max)` llega como `C(0)` y va como memo. Una columna de la clave primaria va
`NOT NULL`, aunque el motor diga que admite nulos (SQLite). De Firebird, `BIGINT`, `INT128` y un `NUMERIC` de más de 18
cifras llegan como texto, `TIME` llega como fecha y hora del 30-12-1899, y un `BLOB` binario llega como General y se salta.

Lo que no tiene equivalente, y qué se hace con ello:

- Un campo Character pierde su ancho fijo: los espacios del final no son datos.
- En SQL Server el texto va como `N'…'` (Unicode). En MySQL las barras invertidas van dobladas, y
  `CREATE TABLE` acaba con `DEFAULT CHARSET=utf8mb4`. SQLite no tiene fechas: van como texto ISO 8601, que
  sus funciones de fecha leen.
- Una clave sobre un campo va como `PRIMARY KEY` en `CREATE TABLE`, y en el dialecto VFP como
  `INDEX ON … CANDIDATE` (una tabla libre no tiene clave primaria).
- En Firebird no va nada tras el tipo de una columna que admite nulos, y un `N` de más de 18 cifras de ancho sale
  como `NUMERIC(18,d)`. Un salto de línea de un texto va como `ASCII_CHAR(13) || ASCII_CHAR(10)`, porque isql deja
  en LF el de un literal. Un texto de más de 20.000 caracteres o un binario de más de 30.000 bytes va a trozos
  unidos con `||`, y en un memo o un Blob el primero va dentro de un `CAST`. Una sentencia de Firebird no pasa de
  10.485.760 bytes, así que un valor mayor no cabe.
- En el dialecto VFP una cadena va a trozos de 200 caracteres unidos con `+` (un literal no pasa de
  255), los caracteres de control como `CHR(n)`, y un valor de más de 1000 caracteres va vacío en la
  sentencia y se añade detrás a trozos (`REPLACE` tras un `INSERT`, `UPDATE` tras un `UPDATE`).

### Las conexiones

**FoxDock > Datos > Conexiones** (FoxDock > Data > Connections) guarda las conexiones a tus servidores de bases de datos (SQL Server,
MySQL, MariaDB, PostgreSQL, Firebird y SQLite) y las abre desde el IDE, por FoxRemote (una copia suya va
dentro del paquete, sin tocar). Cada conexión es una barra con su submenú:

| Barra | Qué hace |
|---|---|
| **Conectar...** (Connect...) | Conecta. Si la conexión tiene `user` y no hay contraseña guardada, una ventanita la pide; con **Recordarla** (Remember) se guarda, cifrada con tu cuenta de Windows |
| **Desconectar** (Disconnect) | Cierra la conexión |
| **Explorar...** (Explore...) | La ventana de la conexión: su base, sus tablas y vistas, y las columnas y las filas de cada una (abajo) |
| **Consulta...** (Query...) | Una ventana con un cuadro para un `SELECT`, las filas que lee como mucho (**Límite** (Limit): 100 de entrada, 0 sin límite; se recuerda) y **Ejecutar** (Run): las filas, en un `BROWSE`. **A objeto** (To object) deja el resultado en una variable para la ventana de comandos (abajo) |

Los espacios del final de una contraseña tecleada en **Conectar...** se pierden, porque el cuadro de VFP
rellena lo tecleado con espacios; los del principio se quedan.

**Explorar...** conecta antes si la conexión no está conectada (con la ventanita de la contraseña si hace
falta: entonces, **Explorar...** otra vez). Abre una ventana por conexión, **FoxDock - <nombre>**; pulsarlo
otra vez trae esa ventana delante. En ella:

- **Base de datos** (Database): la base en la que está la conexión, y una lista con las bases del servidor que puedes abrir
  (SQL Server, MySQL, MariaDB y PostgreSQL). Elegir otra lleva la conexión a esa, vuelve a cargar la lista
  de tablas y el log lo dice; desde entonces las tools del agente leen esa base. En SQLite y Firebird la
  base es el fichero, y la lista sale en gris. Cambiar de base abre una conexión nueva al servidor: con
  contraseña, FoxDock solo puede hacerlo si la contraseña está guardada (**Recordarla**); si no, la ventana lo
  dice y la conexión se queda donde estaba.
- **Filtro** (Filter): teclea parte de un nombre y la lista deja las tablas y vistas que lo contienen (sin distinguir
  mayúsculas); **Intro** te lleva a la lista, a su primera fila. Al lado, **Tablas y vistas** (Tables and views),
  **Tablas** (Tables) o **Vistas** (Views) (en gris si la base solo tiene de una clase; con las dos, empieza en
  **Tablas**), y debajo, cuántas pasan los dos, de las que deja el combo: **N de M tablas**, **N de M vistas** o
  **N de M tablas y vistas**.
- La lista: cada tabla o vista de la base, con `table` o `view` al lado.
- **Columnas** (Columns): las columnas de la elegida (nombre, tipo de VFP, ancho, decimales, nulos y si está en la
  clave primaria), en un `BROWSE`. Su título dice la clave.
- **Mostrar filas** (Browse): las **Límite** primeras filas de la elegida, en un `BROWSE`. **Límite** es el de **Consulta...**
  (100 de entrada, 0 sin límite; se recuerda), y el título dice cuándo se paró ahí. Con 0 y una tabla grande,
  el IDE espera hasta que llegan las filas (250.000 filas tardaron alrededor de un segundo).
- **A objeto**, con el cuadro **Variable** al lado: las filas de la elegida, en una variable para la ventana de
  comandos (abajo, después de los `BROWSE`).
- **Exportar...** (Export...): la elegida, a un fichero, en una ventanita:
  - **el formato**: `.dbf` (una tabla libre, con los tipos de VFP: `bigint` y `uuid` llegan como texto,
    `datetime2` pierde la fracción, y un nombre de columna de más de 10 letras se corta, porque una tabla libre no
    admite más), `.json` (UTF-8 sin BOM: un objeto con `table`, `connection`, `columns` y `rows`, las filas de
    **Tabla a JSON**; con **Solo esquema** (Schema only), sin `rows`; **JSON a cursor** lo vuelve a leer) o `.csv` (separador `;`, `,` o tabulador;
    CP1252 o UTF-8 con BOM; una fila de cabecera, comillas solo en un texto con el separador, comillas o un salto de
    línea, números con punto, fechas `2026-11-01` y `2026-11-01T10:20:30`, y un campo vacío para NULL);
  - **A un fichero** (To a file) o **Al portapapeles** (To the clipboard) (JSON y CSV; un `.dbf`, solo a fichero): con el
    portapapeles, la carpeta, el nombre, **Reemplazarlo**, **Abrirlo** y la codificación no cuentan, y el aviso dice
    cuántas filas y cuántos caracteres fueron;
  - **la carpeta y el nombre** (de entrada, `%LOCALAPPDATA%\FoxDock\data\` y `<tabla>.<ext>`);
  - **las filas**: todas, o las N primeras (el número solo se puede poner con **Las primeras**); arriba, cuántas tiene el servidor (`SELECT COUNT(*)`), y el aviso dice
    cuántas salieron;
  - un fichero que ya está no se pisa si no marcas **Reemplazarlo** (Replace it): lo dice la ventana, no VFP;
  - con **Abrirlo** (Open it) (marcada de entrada; desmárcala cuando maneje Exportar... un agente), el `.json` y el `.csv` en
    UTF-8 se abren con su aplicación de Windows, y el `.csv` en CP1252 en un editor de texto de VFP (CP1252 es la
    suya: los acentos se ven bien; en UTF-8 no se verían). El aviso dice con qué se abrió. El `.dbf` no se abre, y
    el aviso dice dónde quedó;
  - un fichero abierto en un editor de VFP, o que tiene otro programa (Excel guarda el `.csv` que tiene abierto), no
    se escribe: lo dice la ventana. Ciérralo antes.
- **Crear vista...** (Create view...): una vista remota de VFP de la elegida, en un `.dbc`:
  - **la base de datos**: la abierta en VFP, una de la carpeta del proyecto abierto, o una nueva con el nombre que
    teclees (sin proyecto, en `%LOCALAPPDATA%\FoxDock\data\`);
  - **el nombre** de la vista (no puede ser el de una tabla del `.dbc`; el de una vista suya, sí: ver **Reemplazar**
    abajo), **las columnas** en orden alfabético
    (todas marcadas de entrada; **Todas** (All), **Ninguna** (None) o **Ctrl+A** en la lista; la vista guarda el
    orden de la tabla) y un **WHERE** opcional (lo comprueba el servidor; lo que diga, lo dice la ventana);
  - **Actualizable** (Updatable), si la tabla tiene clave primaria: entonces `TABLEUPDATE()` manda tus cambios al servidor.
    Con clave viene marcada de entrada; sin clave, apagada. Si la desmarcas, la siguiente ventana se abre desmarcada: se
    guarda en `config.json`, en la opción `connections.createViewUpdatable` (abajo). En
    SQLite, las columnas `TEXT` quedan fuera (en VFP son memo, y una vista no las escribe), y el texto llega en el
    UTF-8 que guarda SQLite: `STRCONV(<campo>, 11)` devuelve los acentos;
  - **ninguna contraseña en el `.dbc`**: su conexión lleva la cadena sin la contraseña, también mientras se hace la
    vista. Mientras FoxDock la crea, la contraseña va en un fichero `.dsn` temporal en la carpeta temporal de tu
    usuario (`%TEMP%\foxdock-*.dsn`), que FoxDock borra al acabar, también si la vista falla. Y la conexión no
    pregunta nunca (`DispLogin` 3), así que crear no abre ninguna ventana. Hecha la vista, se queda con
    `DispLogin` 1. Sin contraseña (autenticación de Windows, SQLite), `OPEN DATABASE` y `USE <vista>` la abren.
    Con contraseña, `USE <vista>` tecleado a secas y Modificar en el diseñador de la base (`MODIFY DATABASE`, clic
    derecho en la vista) la piden en la ventana de login del driver, en vez de fallar con el error 1526
    («Connectivity error»); la ventana lo avisa al hacer la vista. Para abrirla sin que pregunte, se da al abrir la
    vista, como enseña la ventana:
    `USE <vista> CONNSTRING DBGETPROP("<conexión>", "Connection", "ConnectString") + "PWD=<la contraseña>"`.
  - **Si hiciste vistas con contraseña con una versión anterior** (hasta la 0.9.31) en un `.dbc` que ya existía, o
    una segunda vista en el mismo `.dbc`: esas versiones dejaban la cadena de conexión con la contraseña en bloques
    sueltos del fichero `.dct` del `.dbc`. La conexión en sí estaba limpia, pero la contraseña seguía en el fichero.
    `PACK DATABASE`, con el `.dbc` abierto en exclusiva y nada suyo abierto, la quita. La 0.9.32 ya no lo hace.
  - **El WHERE, probado antes**: con un **WHERE**, **Crear vista...** lo prueba primero con el motor, con un SELECT que no trae
    filas por la conexión de FoxDock. Una columna o una función que no existe no hace la vista, y la ventana dice el
    error del motor. No ve un tipo que no casa (`id = 'abc'`), que fallará al abrir la vista. Una vista con
    parámetros (`?x`) no se prueba. Un **WHERE** que acaba en un comentario (`-- …`) no se acepta: quita el comentario.
  - **Una vista que falla** deja la conexión del `.dbc` como la deja una buena, preguntando la contraseña en la
    ventana del driver (no con el error 1526), y deja en el log su línea con el motivo.
  - **Crear** (Create) hace la vista y se apaga en cuanto está hecha, así que un segundo clic no hace otra. Se vuelve
    a encender al cambiar algo de lo que haría otra vista: el nombre, la base, las columnas, el **WHERE** o la casilla
    **Actualizable**.
  - Con un nombre que el `.dbc` elegido ya tiene como vista, el botón dice **Reemplazar** (Replace), y la ventana lo
    explica antes de pulsarlo: «La vista X ya existe en Y.dbc: Reemplazar la vuelve a crear con lo de arriba.».
    **Reemplazar** borra la vista (`DROP VIEW`) y la hace de nuevo con lo que hay en la ventana. Se niega si esa
    vista está abierta en el IDE («USE IN <vista> la cierra»), porque VFP se quedaría con su cursor. Con el nombre
    de una tabla del `.dbc` no hay **Reemplazar**: se niega, como siempre, y la ventana lo dice.
  - **Abrir** (Open), al lado de **Crear**, lo hace por ti cuando la vista está hecha: abre el `.dbc` (o lo elige, si
    está abierto), abre la vista en un área libre de la sesión de datos del IDE (como si la hubieras tecleado), con el
    límite de filas de **Consulta...**, y la enseña en un `BROWSE`. La vista queda abierta al cerrar la ventana: es
    tuya, no un cursor de la ventana. Si se pulsa otra vez, la vuelve a leer en lugar de abrir otra copia. Con
    contraseña, usa la guardada con **Recordarla** en **Conectar...**, sin enseñarla, y la lleva en `CONNSTRING`, así
    que no pregunta; FoxDock no guarda una contraseña
    que solo se tecleó, así que entonces **Abrir** no abre nada, lo dice, y el camino son las líneas de arriba.
- **Script como...** (Script as...): el `CREATE TABLE`, `INSERT` o `UPDATE` de la elegida, sin abrirla, en una ventanita: el
  dialecto (de entrada, el del motor de la conexión, y el de MySQL para MariaDB; cambiarlo aquí vale solo para esta vez), las filas (todas, o las N primeras, cuyo número solo se puede poner con **Las primeras**; no
  para `CREATE TABLE`) y adónde va: **Al editor** (To the editor) (el fichero de **Script de la tabla como**,
  `<tabla>-<kind>.sql` o `.prg` en `%LOCALAPPDATA%\FoxDock\data\`, abierto como lo abre aquel) o **Al portapapeles** (To the
  clipboard). Las columnas y la clave primaria salen del servidor, no de las filas (abajo, debajo de la tabla de tipos);
  `UPDATE` va por las columnas de la clave, una o varias, y por todos los campos si no tiene, y un comentario del script lo
  dice. Los nombres van citados como los quiere el dialecto del script. Nada queda abierto en el IDE.

Los dos `BROWSE` son de solo lectura: no se puede cambiar, añadir ni borrar una fila. Sus cursores son
`c_<conexión>_<tabla>_columns` y `c_<conexión>_<tabla>`, y se cierran con la ventana salvo que marques
**Dejar los cursores abiertos al cerrar** (Keep the cursors open when it closes) (sin marcar de entrada; se
recuerda, y el aviso dice cuáles quedan abiertos). **Consulta...** tiene la misma casilla para su cursor.
**Desconectar**, **Recargar** (Reload) o apagar el paquete cierran la ventana y esos cursores con ella, con
casilla o sin ella.
Lo que la ventana tiene que decir va en su cuadro de abajo, en el aviso de arriba a la derecha de VFP y en el
log.

**A objeto, para la ventana de comandos.** **Consulta...** y **Explorar...** tienen un botón **A objeto** con un
cuadro **Variable** al lado. En **Consulta...** toma el resultado del último **Ejecutar**; en **Explorar...**, las filas
de la tabla o vista elegida, hasta el **Límite** de la ventana (el mismo de **Mostrar filas**). Hace una `Collection`
con un objeto por fila, con las columnas como propiedades, y la deja en una variable `PUBLIC`. Tiene que ser `PUBLIC`:
desde una ventana, `_VFP.SetVar` dejaría una variable privada que desaparece al volver, y solo una `PUBLIC` llega a
la ventana de comandos. Con el cuadro vacío, pone en él `lo` y el nombre de la tabla (`loOrders`, `loG10_cl`); en
**Consulta...**, el del cursor del resultado (`loC_shop_query`). Se niega con un nombre que no es de variable de VFP
y con una variable que ya existe: no pisa nada. Sin filas, no crea nada. La ventana dice cuántas filas, que la variable es `PUBLIC` y que `RELEASE loOrders` la quita, y cómo usarla en
la ventana de comandos: `? loOrders.Count`, `? loOrders.Item(1).<columna>`.

Al final del submenú, **Editar conexiones...** (Edit connections...) abre la ventana **FoxDock - Conexiones**: las
conexiones de los dos ficheros, con su id, su nombre, su motor, dónde están (el proyecto o el tuyo) y si están
conectadas. **Nueva...** (New...) y **Editar...** (Edit...) abren **FoxDock - Conexión**, con los campos del fichero
y ninguna contraseña (la pide Conectar...): dice lo que no vale (un id que ya está en uno de los dos ficheros, un
nombre vacío, una contraseña en un campo) y entonces no escribe nada. **Guardar** (Save) reescribe el fichero
entero con un solo formato, el del ejemplo, y conserva las claves que no conoce; con el fichero abierto en el
editor no guarda. **Borrar** (Delete) pregunta en la ventana, desconecta la conexión y olvida su contraseña
guardada. **Abrir el fichero...** (Open the file...) abre `connections.json` en el editor, como antes (el del
proyecto abierto, o el tuyo si no hay proyecto; con un ejemplo de dos conexiones, SQLite y SQL Server, si no
existía), y **Recargar** vuelve a leer los ficheros. Cada objeto del array es una conexión, y cada una es una
entrada del submenú **Conexiones**, con su **Conectar...**, **Desconectar**, **Explorar...** y
**Consulta...**: elegir una conexión es abrir su submenú. Nada abre un diálogo de VFP: lo que sale mal lo dicen el aviso de arriba a la derecha de VFP y el log. El motivo de un fallo sale en inglés y entre comillas, tal como lo dan las tools del agente.

**El estado, en el menú.** Una conexión conectada lo dice detrás de su nombre, **Shop (conectada)**, y solo se puede pulsar la
barra que tiene sentido, **Conectar...** o **Desconectar**. El menú cambia al conectar, al desconectar, al recargar y cuando una
conexión se pierde. **Una conexión que se pierde se dice**: cuando el servidor deja de contestar (la red, un reinicio del
servidor), lo primero que lee de ella se da cuenta, cierra su ventana **Explorar...** con sus cursores, y lo dicen el aviso y el
log. El aviso dice primero lo importante, «La conexión Shop se ha perdido. Vuelve a conectar desde FoxDock > Datos > Conexiones.»,
y después el motivo que dio el driver, recortado para que quepa; el log guarda el mensaje entero. **Recargar** conserva las
conexiones conectadas; una cuya definición cambió en el fichero (`server`, `port`, `database`, `user`, `driver` o `windowsAuth`)
se desconecta, y el aviso lo dice. **Recargar plugins** (FoxDock > Plugins) es otra cosa: descarga el paquete y cierra todas las
conexiones.

**Dos ficheros, y ninguna contraseña en ellos.** `connections.json` en la carpeta del proyecto abierto (va
con el proyecto, y se puede compartir) y `%LOCALAPPDATA%\FoxDock\connections.json` (el tuyo). Se leen los
dos: las del proyecto van primero y llevan `(project)` en el menú, y con el mismo `id` en los dos se queda
la del proyecto. Un fichero es un array JSON:

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

| Campo | Qué es |
|---|---|
| `id` | Letras, cifras, `_`, `-` y `.`; el agente nombra la conexión por él |
| `name` | Lo que enseña el menú |
| `engine` | `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird` o `sqlite` |
| `server`, `port`, `database` | Dónde está. `database` vacía (SQL Server, MySQL, MariaDB, PostgreSQL) es una conexión al servidor, en la base que dé él (**Explorar...** dice cuál, y la cambia); en SQL Server, **Consulta...** lee además otra base del mismo servidor con nombre de tres partes (`ventas.dbo.clientes`). Con SQLite y Firebird, `database` es el fichero y no puede faltar |
| `user` | Vacío con `windowsAuth`, y con SQLite |
| `driver` | El driver ODBC; vacío, el de la tabla de abajo |
| `windowsAuth` | `true`: la autenticación de Windows (SQL Server), y sin contraseña |
| `allowWrite` | `true`: el agente puede escribir por esta conexión con `ide_data_db_execute`, con rol de agente 10 o más. `false` si no está |
| `agentCanRead` | `true`: el agente puede leer por esta conexión. `false` si no está |

Un fichero con una contraseña dentro (una clave `password`, `pwd`, `passwd`, `secret` o `pass`, o `pwd=`
dentro de un valor) no se lee entero, y el log dice qué conexión y qué clave, nunca el valor. La contraseña
va aparte: **Recordarla** en **Conectar...** la guarda en `%LOCALAPPDATA%\FoxDock\secrets\<id>.cred`,
cifrada con tu cuenta de Windows (DPAPI), y solo tu usuario de Windows en esta máquina puede leerla. Para
olvidarla, borra ese fichero.

**`agentCanRead`, conexión a conexión.** Lo que lee el agente sale de tu máquina hacia el proveedor de la
IA. Con datos de clientes eso lo decides tú, así que está apagado hasta que pongas `"agentCanRead": true` en
esa conexión y pulses **Recargar**. Con eso nada más, el agente solo lee: un `SELECT`, 1000 filas como mucho
(AGENT-TOOLS_ES.md § 8). Esa comprobación para lo evidente, y una
función del servidor aún puede escribir desde dentro de un `SELECT`. Para una conexión que lea el
agente, usa un usuario del servidor que solo pueda leer.

**`allowWrite`, conexión a conexión.** El agente escribe en un servidor solo con `ide_data_db_execute`, y solo con
dos llaves puestas: `"allowWrite": true` en esa conexión (y después **Recargar**) y el rol de agente 10 o más
(FoxDock > FoxAgent > Rol del agente). Manda una sentencia cada vez (`INSERT`, `UPDATE`, `DELETE`, `CREATE`,
`ALTER`, `DROP` o `TRUNCATE`); un `UPDATE` o un `DELETE` sin `WHERE`, un `DROP` y un `TRUNCATE` piden además
`wholeTable`. Cada sentencia queda hecha al volver, y `foxdock.log` guarda todas, con sus filas y lo que
tardaron, y las negadas, con el motivo. Para una conexión en la que escriba el agente, usa un usuario del
servidor que solo pueda tocar lo que debe.

**Los drivers.** Visual FoxPro es un programa de 32 bits, así que necesita el **driver ODBC de 32 bits** de
cada motor, también en un Windows de 64 bits (VFP Advanced de 64 bits necesita el de 64). **Conectar...** sin
el driver dice cuál esperaba. Estos son con los que se prueba FoxRemote:

| Motor | `driver` |
|---|---|
| SQL Server | `ODBC Driver 18 for SQL Server` u `ODBC Driver 17 for SQL Server` |
| MySQL, MariaDB | `MariaDB ODBC 3.2 Driver` (el driver de MySQL de Oracle está roto para VFP desde la 8.0.35) |
| PostgreSQL | `PostgreSQL ANSI` (psqlODBC) |
| Firebird | `Firebird ODBC Driver` 3.0, y el `fbclient.dll` de 32 bits |
| SQLite | `SQLite3 ODBC Driver` |

### IA

**FoxDock > Datos > IA** pone AIXL a trabajar sobre la tabla o el cursor que tienes abierto en el IDE: una
etiqueta por fila (**Clasificar columna...**), una columna por clave (**Extraer de columna...**), una copia de una
columna sin nombres ni teléfonos (**Anonimizar columna...**), las filas que cumplen lo que pides (**Filtrar
filas...**) y una pregunta sobre la tabla entera (**Preguntar sobre la tabla...**). **AIXL es un producto aparte,
de pago: FoxDock no lo trae ni lo copia.** AIXL se instala desde su zip y se registra con `register.cmd` en su
carpeta; su licencia y las claves de tus proveedores van en **IA > Proveedor > Gestionar proveedores...** (abajo):
los que tengas, y pasas de uno a otro con un clic.

Sin AIXL, o con un AIXL que no arranca, **IA** tiene una sola barra que dice por qué. Al pulsarla, la frase
entera va al aviso de arriba a la derecha de VFP y al log, y se abre irwinrodriguez.dev en el navegador:

| Barra | Cuándo | Qué hacer |
|---|---|---|
| **AIXL no está instalado...** | `AIXL.Host` no está registrado en este equipo | Instalar AIXL 1.1.3 o posterior y el runtime de .NET 10 para x86, y ejecutar `register.cmd` en su carpeta |
| **AIXL está, pero no su aixl.prg...** | `AIXL.Host` está registrado, pero `aixl.prg` no está junto a su DLL (registrado desde otra carpeta, por ejemplo); la frase dice la ruta de la DLL | Ejecutar `register.cmd` en la carpeta del zip de AIXL, o poner en `ai.aixlDir` (abajo) la carpeta de `aixl.prg` |
| **No se ve AIXL: el IDE corre como administrador...** | Tu VFP corre como administrador, y Windows no deja que un programa elevado vea un AIXL registrado para tu usuario (AIXL dice `'HOST_ELEVATED'`) | Abrir VFP sin *Ejecutar como administrador*, o ejecutar una vez `register-machine.cmd` de AIXL como administrador (el manual de AIXL, § 3.3) |
| **AIXL no arrancó...** | Lo demás que diga AIXL (`"DOTNET_RUNTIME_MISSING"`, `"HOST_IS_64BIT"`...), o una versión anterior a la 1.1.3 | El código que dio AIXL, entre comillas, está en el aviso y en el log: FoxDock no inventa diagnósticos |

FoxDock no arranca AIXL al abrir el IDE: solo lee el registro, en un milisegundo. Lo arranca la primera vez que
usas **IA** (un tercio de segundo, lo que tarda en cargar el runtime de .NET), y entonces se descubre un VFP que
corre como administrador: el submenú pasa a la barra que lo dice. `aixl.prg` no se compila en la carpeta de AIXL:
FoxDock lo copia a su caché de código de cada motor (`fxp\<motor>\aixl\` en su carpeta de datos), como el código de
los plugins, y lo carga de allí. Así un VFP 9 y un VFPA abiertos a la vez no se pisan el `.fxp`, y la carpeta de AIXL
puede ser de solo lectura. Si `aixl.prg` no se carga o no corre, la barra es **AIXL no arrancó...**, con el código
`AIXL_LOAD_FAILED` y el error de VFP en el aviso y en el log, y las tools lo contestan igual.

Con AIXL listo, el submenú es:

| Barra | Qué hace |
|---|---|
| **Clasificar columna...** | Una etiqueta por fila de una columna de texto o memo |
| **Extraer de columna...** | Una columna por clave de un esquema, de una columna de texto o memo |
| **Anonimizar columna...** | Una copia de una columna de texto o memo sin lo que digas (nombres, teléfonos...) |
| **Filtrar filas...** | Marca en `aixl_keep` las filas que pasan; no se borra nada |
| **Preguntar sobre la tabla...** | Una pregunta sobre la tabla entera: la respuesta, no una columna |
| **Proveedor: ...** | Un submenú con el nombre del que está en uso: tus proveedores, con la marca en el que está en uso (un clic y las operaciones van a otro, desde ese momento), y **Gestionar proveedores...**. FoxDock nunca cambia solo: si un proveedor se queda sin crédito, la operación falla con lo que dijo el proveedor, y eres tú quien elige otro aquí |
| **Gestionar proveedores...** | La ventana de tus proveedores: una lista con **Nuevo**, **Guardar**, **Borrar** (se pulsa dos veces: no hay diálogo) y **Usar este**. Cada uno lleva un nombre, el proveedor, el modelo (una lista con los de ese proveedor, el primero el que AIXL usa por defecto; también se puede escribir otro), la clave y el servidor local (solo para una IA en tu propio equipo, como Ollama o LM Studio). **La clave, de dos maneras**: guardada cifrada con tu cuenta de Windows (DPAPI: solo tu usuario, en este equipo, puede leerla), o leída de una variable de entorno cada vez que se usa (la que tú creaste, con su nombre: la ventana no propone ninguno, y dice si la encuentra y cuánto mide). Si borras el que está en uso, no queda ninguno en uso: las operaciones se apagan hasta que eliges otro, y el aviso lo dice. Debajo, **la licencia de AIXL**, una para todos los proveedores: el fichero de tu licencia, o su texto pegado en el cuadro (empieza por `eyJ`), que se guarda como `aixl.lic` en la carpeta de datos de FoxDock. La clave no se enseña nunca, ni se escribe en claro en ningún fichero, ni va al log ni al agente |
| **Última ejecución: ...** | Deshabilitada: las filas, los tokens y los segundos de la última operación |

**Sin un proveedor, las cinco operaciones salen deshabilitadas**, y su barra dice qué hacer: primero añadir uno en
**Gestionar proveedores...**. Sus tools contestan `NO_PROVIDER` sin enviar nada.

La sesión de AIXL es una por IDE. Lo que hagas desde la ventana de comandos (`AIXL_USE_MOCK()`,
`AIXL_CONFIGURE_FROM_FILE()`) es la misma sesión que enseña el menú, y el menú la lee de AIXL, no de lo que pidió.

**Las ventanas.** Cada una tiene la tabla, en una lista con las tablas y los cursores abiertos en la sesión de datos 1
(Clasificar, Extraer y Anonimizar solo listan los que tienen una columna de texto o memo); se abre con la
seleccionada, o con un `.dbf` que eliges si no hay ninguna. Y sus
campos. Clasificar, Extraer y Anonimizar piden la columna (de texto o memo) y el destino, con los nombres que va a
añadir escritos debajo en gris; Clasificar pide además las etiquetas (una lista cerrada, `alto,medio,bajo`; vacía,
el modelo elige), Extraer el esquema (`prioridad,departamento`; vacío, el modelo elige las claves) y Anonimizar qué
se quita. Filtrar pide qué filas pasan, las columnas que ve el modelo (vacío: la fila entera) y **También un cursor
nuevo con las filas que pasan**; Preguntar, la pregunta y las columnas. Todas menos Preguntar tienen **Filas por
bloque** (200; de 1 a 1000).

Debajo de los campos, **la frase del coste**, que se vuelve a escribir justo antes de **Ejecutar** con lo que
tiene la sesión de AIXL: «Esto envía 300 filas de ventas.notas a deepseek (deepseek-chat) desde tu propia
cuenta.», o «Modo doble: no se envía nada y no se paga nada.». Las filas son las que ves: cuentan el filtro y
`SET DELETED`. Lo que se envía se paga en tu cuenta con tu proveedor (el manual de AIXL, § 11, dice cuánto).

**Ejecutar** va por bloques: la barra de estado y la ventana cuentan las filas («IA: 150 de 500 filas (bloque
3/10)»). **Esc** para al acabar el bloque que está en curso: lo hecho se queda, y las columnas nuevas del resto
quedan en `.NULL.` («IA: parada tras el bloque 3: 150 filas hechas, 350 quedan en NULL»). Mientras corre, la ventana
no se cierra con Esc. Preguntar es una pregunta sobre la tabla entera: sin bloques y sin Esc.

**La copia.** AIXL añade sus columnas al final del cursor y las rellena; nunca reescribe ni mueve una fila. Un
cursor de solo lectura (un `SELECT ... INTO CURSOR` sin `READWRITE`) no admite columnas nuevas, y FoxDock nunca
escribe en una tabla tuya, tampoco si la tienes abierta `SHARED` y escribible. En los dos casos la operación
trabaja sobre una copia, `ai_<nombre>`, `READWRITE`, con las filas que ves, en la sesión de datos 1, y la ventana lo
dice antes de Ejecutar. El original queda como estaba. Preguntar no escribe nada y no necesita copia.

| Operación | Lo que deja |
|---|---|
| Clasificar | `<destino>`, `<destino>_con` y `<destino>_rea` (la etiqueta, cuánta seguridad y por qué), al final, recortadas a diez caracteres. El destino que propone es `ai_<columna>` recortado a seis, para que quepan las tres |
| Extraer | `<destino>` y `<destino>_<clave>` por cada clave, recortadas a diez; sin esquema, las claves que elija el modelo. El destino que propone es `ax_<columna>` recortado a seis, otro que el de Clasificar. Dos claves que a diez caracteres dan el mismo nombre se rechazan antes de Ejecutar. Una clave que el texto no tiene vuelve vacía, y eso no es un error |
| Anonimizar | `<destino>` (propone `ai_<columna>`, hasta diez) con el texto sin lo que dijiste |

Si alguna de las columnas que va a dejar ya está en la tabla, la ventana lo dice debajo del destino, antes de **Ejecutar**: Ejecutar escribe encima.
| Filtrar | `aixl_keep`, lógica: `.T.` en las filas que pasan. No se borra nada. Con la casilla, además un cursor `ai_<nombre>_kept` con ellas |
| Preguntar | La respuesta, en la ventana y en el log; ninguna columna. El modelo solo lee los primeros 4.000 caracteres de lo que se envía: la frase del coste lo dice, y cuando no lo leyó todo (el `INPUT_TRUNCATED` de AIXL), la barra de estado también |

Al acabar sale un `BROWSE` del cursor (de la copia, o de `ai_<nombre>_kept` si lo pediste), y la barra de estado y
el log dicen las filas, las fallidas, los tokens y los segundos («IA: ventas.notas clasificada en ai_not: 500 filas
bien, 0 fallidas, ...»). Los avisos de AIXL van al log (`COLUMN_RENAMED`, `COLUMN_WIDENED`), y si falló alguna fila,
un cursor `ai_errors` con ellas se abre en un segundo `BROWSE`. **Última ejecución** dice las cifras. Cuando AIXL
contesta sin ninguna fila hecha (`NO_DATA`, `LICENSE_*`, `PROVIDER_*`...), su código entre comillas y su texto van al
aviso, a la ventana y al log.

**Lo que no hace.** No escribe nunca en claro la clave de tu proveedor: o se guarda cifrada con tu cuenta de
Windows, o se lee de su variable de entorno cada vez. No cambia nunca de proveedor por su cuenta. No envía nada
que no esté en la frase del coste. No escribe en una tabla tuya. No ve un AIXL registrado para tu usuario desde un
VFP que corre como administrador (Windows no se lo deja). Y no copia AIXL: sin él, solo está la barra que dice lo
que falta.

Las opciones van en `"options": { "data": { ... } }`:

| Opción | Por defecto | |
|---|---|---|
| `json.enabled` | `.T.` | `.F.` apaga el módulo JSON: ni **Tabla a JSON**, ni **JSON a cursor**, ni `ide_data_to_json` ni `ide_data_from_json` |
| `script.enabled` | `.T.` | `.F.` apaga los scripts: ni **Script de la tabla como**, ni **Dialecto**, ni `ide_data_script` |
| `script.dialect` | `sqlserver` | `vfp`, `sqlserver`, `mysql`, `postgresql`, `sqlite` o `firebird`; lo escribe **Dialecto >** |
| `script.utf8` | `.F.` | `.T.`: el `.sql` sale en UTF-8 con BOM (el de Firebird, sin BOM) y se abre con la aplicación de Windows, nunca en el editor de VFP; el `.prg` sigue en CP1252. **Dialecto >** no lo cambia |
| `connections.enabled` | `.T.` | `.F.` apaga las conexiones: ni **Conexiones** ni ninguna de las cinco `ide_data_db_*` |
| `connections.createViewUpdatable` | `.T.` | `.F.`: **Actualizable** sale desmarcada en **Crear vista...**, aunque la tabla tenga clave primaria. Lo escribe la ventana cuando marcas o desmarcas la casilla |
| `ai.enabled` | `.T.` | `.F.` apaga IA: ni **IA** ni ninguna de las seis `ide_data_ai_*` |
| `ai.aixlDir` | vacío | La carpeta de `aixl.prg`, cuando el registro no lleva a ella |
| `ai.config` | vacío | La ruta de un `aixl.config.json` (si es relativa, desde la carpeta de datos de FoxDock); vacío, el de la carpeta de `aixl.prg`. Solo cuenta cuando no hay ninguno de tus proveedores en uso |
| `ai.provider` | vacío | El proveedor en uso; lo escriben **Gestionar proveedores...** y el submenú **Proveedor**. La lista está en `ai-providers.json`, en la carpeta de datos de FoxDock, sin las claves |
| `ai.license` | vacío | La ruta del fichero de la licencia de AIXL; lo escribe **Gestionar proveedores...** |
| `ai.mock` | `.F.` | `.T.`: el doble de AIXL, que no envía nada y contesta con datos inventados. Es para las pruebas y no tiene barra. La variable de entorno `FOXDOCK_AI_MOCK=on` lo fuerza |
| `ai.blockRows` | `200` | Filas por bloque, de 1 a 1000 |
| `ai.agentMaxRows` | `200` | Las filas que el agente puede enviar como mucho en una llamada (AGENT-TOOLS_ES.md § 8) |

Para el agente están las tools `ide_data_*`, entre ellas las seis `ide_data_ai_*`: AGENT-TOOLS_ES.md § 8.

## Sobre este manual

Este texto es la sección sobre `data` del manual de plugins de FoxDock. Las referencias a otras secciones (§) y a AGENT-TOOLS apuntan a los documentos que FoxDock instala en su carpeta `docs`.

## Licencia

MIT. Está en [LICENSE](LICENSE).
