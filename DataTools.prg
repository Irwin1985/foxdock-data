*==================================================================
* DataTools.prg: las tools del paquete «data» para el agente.
*
* Heredan de IdeTool (plugins\foxagent\IdeTools.prg): el host, J(), Done(),
* los parámetros y los roles: las que leen corren con cualquier rol; las que
* actúan piden rol 10 o más.
*
*   ide_data_to_json     la tabla o el alias en JSON (lee: cualquier rol)       módulo json
*   ide_data_script      CREATE TABLE, INSERT o UPDATE en un dialecto (lee)     módulo script
*   ide_data_from_json   un cursor en la sesión 1 desde JSON (actúa: rol 10)    módulo json
*   ide_data_db_connections   las conexiones, sin secretos (lee)                módulo connections
*   ide_data_db_tables        las tablas de una conexión (lee; agentCanRead)    módulo connections
*   ide_data_db_describe      las columnas de una tabla (lee; agentCanRead)     módulo connections
*   ide_data_db_query         un SELECT con tope de filas (lee; agentCanRead)   módulo connections
*   ide_data_ai_status        si hay AIXL y cómo, sin la clave (lee)            módulo ai
*   ide_data_ai_classify      una etiqueta por fila con AIXL (actúa: rol 10)    módulo ai
*   ide_data_ai_extract       una columna por clave con AIXL (actúa: rol 10)    módulo ai
*   ide_data_ai_anonymize     una copia anonimizada de una columna (rol 10)     módulo ai
*   ide_data_ai_filter        marca aixl_keep y devuelve las que pasan (rol 10) módulo ai
*   ide_data_ai_ask           una pregunta sobre la tabla entera (rol 10)       módulo ai
*
* Una tool de un módulo apagado no existe (el módulo no la añade). Las filas
* que vuelven son 1000 como mucho (maxRows), y la respuesta dice si se cortó.
*
* Superficie pública en inglés. Fichero en CP1252.
*==================================================================

#DEFINE DT_NO_HOST "FoxDock is not mounted (after CLEAR ALL it sleeps until a FoxDock menu bar or key is pressed)"
#DEFINE DT_MAX_ROWS 1000
#DEFINE DT_TABLE_HELP "The table: the alias of a table or cursor open in data session 1 of the IDE, or the path of a .dbf (opened SHARED NOUPDATE and closed again; never written). Left out: the one selected in data session 1."

DEFINE CLASS IdeDataTool AS IdeTool
	PROCEDURE Module
		LPARAMETERS tcModule
		LOCAL loP
		IF ISNULL(THIS.Host())
			RETURN .NULL.
		ENDIF
		loP = _screen.oFoxDock.PluginById("data")
		IF ISNULL(loP)
			RETURN .NULL.
		ENDIF
		RETURN loP.Module(tcModule)
	ENDPROC

	PROCEDURE NotThere
		LPARAMETERS tcModule
		IF ISNULL(THIS.Host())
			RETURN THIS.Err(DT_NO_HOST)
		ENDIF
		RETURN THIS.Err("The data package, or its module '" + tcModule + "', is not loaded in this IDE (FoxDock > Plugins, " + ;
			"and options.data." + tcModule + ".enabled in config.json).")
	ENDPROC

	*-- maxRows: de 1 a 1000; sin él, o más, 1000.
	PROCEDURE MaxRows
		LPARAMETERS toContext
		LOCAL lnMax
		lnMax = INT(THIS.PNum(toContext, "maxRows"))
		RETURN IIF(lnMax <= 0 OR lnMax > DT_MAX_ROWS, DT_MAX_ROWS, lnMax)
	ENDPROC
ENDDEFINE


DEFINE CLASS IdeDataToJsonTool AS IdeDataTool
	ToolName = "ide_data_to_json"
	ToolDescription = "A table or cursor of this Visual FoxPro IDE as JSON rows, as FoxDock > Data > Table to JSON makes them: " + ;
		"one object per row with the fields in lower case; text without its trailing padding; numbers with the decimals of " + ;
		"the field, and a Double with the value it holds (the shortest decimal that gives it back); dates and datetimes in ISO 8601 (an empty one is null); Varbinary and Blob in base64; General fields left " + ;
		"out and named in 'skipped'; deleted rows left out. Returns table, source, rowCount (the rows there are), returned, " + ;
		"truncated (more rows than maxRows) and rows. It reads only: the record pointer and the settings of the IDE stay as they were."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("maxRows", "number", "How many rows at most, from 1 to 1000; 1000 if left out.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, lcOut
		loM = THIS.Module("json")
		IF ISNULL(loM)
			RETURN THIS.NotThere("json")
		ENDIF
		lcOut = loM.ToolJson(THIS.PText(toContext, "table"), THIS.MaxRows(toContext))
		IF EMPTY(lcOut)
			RETURN THIS.Err(loM.cLastError)
		ENDIF
		RETURN THIS.Ok(lcOut)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataScriptTool AS IdeDataTool
	ToolName = "ide_data_script"
	ToolDescription = "A table or cursor of this Visual FoxPro IDE as a script, as FoxDock > Data > Script table as makes it: " + ;
		"kind 'create' (CREATE TABLE, with PRIMARY KEY when the CDX has a primary or candidate key on one field), 'insert' " + ;
		"(one INSERT per row) or 'update' (one UPDATE per row by that key, or by all the fields when there is none: a comment " + ;
		"in the script says which). Dialects: vfp, sqlserver, mysql, postgresql, sqlite; left out, the one chosen in FoxDock > " + ;
		"Data > Dialect. General fields are left out and named in 'skipped'. With 'connection', 'table' is a table of that " + ;
		"database connection of FoxDock instead (as in Explore... > Script as...): its columns and its primary key come from " + ;
		"the server, its rows are read without opening anything in the IDE, and only for a connection with agentCanRead true; " + ;
		"source is then connection:table. Returns table, source, kind, dialect, rowCount, returned, truncated, key and script. " + ;
		"It reads only, and runs nothing: the script is text."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("kind", "string", "create, insert or update.", .T.)
		THIS.AddParam("dialect", "string", "vfp, sqlserver, mysql, postgresql or sqlite; left out, the one in FoxDock > Data > Dialect.", .F.)
		THIS.AddParam("maxRows", "number", "For insert and update, how many rows at most, from 1 to 1000; 1000 if left out.", .F.)
		THIS.AddParam("connection", "string", "The id of a database connection (ide_data_db_connections lists them): 'table' is " + ;
			"then a table of it. Left out: a table or cursor of the IDE.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, loC, lcOut, lcConn, lcWhy
		loM = THIS.Module("script")
		IF ISNULL(loM)
			RETURN THIS.NotThere("script")
		ENDIF
		*-- Con connection, una tabla de esa conexión, con agentCanRead como las ide_data_db_*.
		lcConn = THIS.PText(toContext, "connection")
		IF !EMPTY(lcConn)
			loC = THIS.Module("connections")
			IF ISNULL(loC)
				RETURN THIS.NotThere("connections")
			ENDIF
			lcWhy = loC.AgentRefusal(lcConn)
			IF !EMPTY(lcWhy)
				RETURN THIS.Err(lcWhy)
			ENDIF
		ENDIF
		lcOut = loM.ToolScript(THIS.PText(toContext, "table"), THIS.PText(toContext, "kind"), ;
			THIS.PText(toContext, "dialect"), THIS.MaxRows(toContext), lcConn)
		IF EMPTY(lcOut)
			IF loM.cLastCode == "not_connected"
				RETURN THIS.ErrCode("not_connected", loM.cLastError)
			ENDIF
			RETURN THIS.Err(loM.cLastError)
		ENDIF
		RETURN THIS.Ok(lcOut)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataFromJsonTool AS IdeDataTool
	ToolName = "ide_data_from_json"
	lActsOnIde = .T.
	ToolDescription = "Makes a cursor in data session 1 of this Visual FoxPro IDE from JSON, as FoxDock > Data > JSON to cursor " + ;
		"does: an array of objects (or one object, one row), one field per key, with the types JSONFox reads (text, numbers, " + ;
		"logical, and dates and datetimes written in ISO 8601). Returns the cursor's name, its rows and its fields. It writes " + ;
		"no table: the cursor lives until it is closed."

	FUNCTION DefineParameters()
		THIS.AddParam("json", "string", "The JSON text.", .T.)
		THIS.AddParam("cursor", "string", "The cursor's name; left out, json_<n> (the first free one). One already in use is refused.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, lcCursor, loJ, loD, loF, lnI, lnN, lnDs, loAi
		LOCAL ARRAY laF[1]
		loM = THIS.Module("json")
		IF ISNULL(loM)
			RETURN THIS.NotThere("json")
		ENDIF
		*-- Mientras AIXL trabaja sobre un alias, no se escribe en él (AI_BUSY).
		loAi = THIS.Module("ai")
		IF !ISNULL(loAi) AND loAi.lBusy AND LOWER(ALLTRIM(THIS.PText(toContext, "cursor"))) == loAi.cBusyAlias
			RETURN THIS.ErrCode("AI_BUSY", loAi.BusyText())
		ENDIF
		lcCursor = loM.FromJson(THIS.PText(toContext, "json"), THIS.PText(toContext, "cursor"))
		IF EMPTY(lcCursor)
			RETURN THIS.Err("The JSON could not be made into a cursor: " + loM.cLastError)
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lnN = AFIELDS(laF, lcCursor)
		SET DATASESSION TO (lnDs)
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "cursor", lcCursor)
		loJ.Put(loD, "rows", loM.nLastRows)
		loF = loJ.MakeArray()
		FOR lnI = 1 TO lnN
			loF.Add(LOWER(laF[lnI, 1]) + " " + laF[lnI, 2] + "(" + TRANSFORM(laF[lnI, 3]) + IIF(laF[lnI, 4] > 0, "," + ;
				TRANSFORM(laF[lnI, 4]), "") + ")")
		ENDFOR
		loJ.Put(loD, "fields", loF)
		_screen.oFoxDock.AgentDid("made the cursor " + lcCursor + " (" + TRANSFORM(loM.nLastRows) + " rows) from JSON")
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


*------------------------------------------------------------------
* Connections: leen, con cualquier rol; las tres que tocan el servidor,
* solo en una conexión con agentCanRead. Ninguna pregunta nada: si falta la
* contraseña, lo dicen.
*------------------------------------------------------------------
DEFINE CLASS IdeDataDbTool AS IdeDataTool
	*-- El módulo, o .NULL. con la respuesta de error ya hecha en oRefusal.
	oRefusal = .NULL.

	PROCEDURE Conn
		LPARAMETERS toContext, tlNoGate
		LOCAL loM, lcWhy
		loM = THIS.Module("connections")
		IF ISNULL(loM)
			THIS.oRefusal = THIS.NotThere("connections")
			RETURN .NULL.
		ENDIF
		IF !tlNoGate
			lcWhy = loM.AgentRefusal(THIS.PText(toContext, "connection"))
			IF !EMPTY(lcWhy)
				THIS.oRefusal = THIS.Err(lcWhy)
				RETURN .NULL.
			ENDIF
		ENDIF
		RETURN loM
	ENDPROC

	*-- El motivo del módulo; si es que la conexión no está (perdida, o sin
	*-- la contraseña para conectarla sola), con el código NOT_CONNECTED.
	PROCEDURE Refused
		LPARAMETERS toM
		IF toM.cLastCode == "not_connected"
			RETURN THIS.ErrCode("not_connected", toM.cLastError)
		ENDIF
		RETURN THIS.Err(toM.cLastError)
	ENDPROC
ENDDEFINE


DEFINE CLASS IdeDataDbConnectionsTool AS IdeDataDbTool
	ToolName = "ide_data_db_connections"
	ToolDescription = "The database connections FoxDock knows in this Visual FoxPro IDE (FoxDock > Data > Connections): " + ;
		"those of connections.json in the folder of the open project first, then the user's. For each: id, name, " + ;
		"origin (project or user), engine, server, port, database (empty: a connection to the server, in the database " + ;
		"the server gives; ide_data_db_tables says which), user, driver, windowsAuth, allowWrite (whether " + ;
		"ide_data_db_execute may write through it), agentCanRead (whether the agent may read through it), connected (checked with a ping: a " + ;
		"connection that does not answer is dropped and the programmer is told), and passwordKept. Never a " + ;
		"password. Only the connections with agentCanRead true can be read with ide_data_db_tables, " + ;
		"ide_data_db_describe and ide_data_db_query."

	FUNCTION Run(toContext)
		LOCAL loM, loJ, loD, loA, loO, loC
		loM = THIS.Conn(toContext, .T.)
		IF ISNULL(loM)
			RETURN THIS.oRefusal
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loA = loJ.MakeArray()
		*-- connected se comprueba: la que no contesta a un ping se da por perdida.
		FOR EACH loC IN loM.oList FOXOBJECT
			IF loM.IsConnected(loC.cId)
				=loM.CheckLost(loC.cId, "")
			ENDIF
		ENDFOR
		FOR EACH loC IN loM.oList FOXOBJECT
			loO = loJ.MakeObject()
			loJ.Put(loO, "id", loC.cId)
			loJ.Put(loO, "name", loC.cName)
			loJ.Put(loO, "origin", loC.cOrigin)
			loJ.Put(loO, "file", loC.cFile)
			loJ.Put(loO, "engine", loC.cEngine)
			loJ.Put(loO, "server", loC.cServer)
			loJ.Put(loO, "port", loC.nPort)
			loJ.Put(loO, "database", loC.cDatabase)
			loJ.Put(loO, "user", loC.cUser)
			loJ.Put(loO, "driver", loC.cDriver)
			loJ.Put(loO, "windowsAuth", loC.lWindowsAuth)
			loJ.Put(loO, "allowWrite", loC.lAllowWrite)
			loJ.Put(loO, "agentCanRead", loC.lAgentCanRead)
			loJ.Put(loO, "connected", loM.IsConnected(loC.cId))
			loJ.Put(loO, "passwordKept", loM.HasSavedSecret(loC.cId))
			loA.Add(loO)
		ENDFOR
		loJ.Put(loD, "count", loA.Count)
		loJ.Put(loD, "connections", loA)
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataDbTablesTool AS IdeDataDbTool
	ToolName = "ide_data_db_tables"
	ToolDescription = "The tables of a database connection of FoxDock (ide_data_db_connections lists them), read through " + ;
		"FoxRemote: their names, and the database they are in (database; with an empty database in the connection, the " + ;
		"one the server gives). Only for a connection with agentCanRead true. It connects if it can without asking " + ;
		"anything (Windows authentication, no user, or a password kept with Remember); if not, it says that Connect... " + ;
		"has to be pressed once in the IDE. Reads only."

	FUNCTION DefineParameters()
		THIS.AddParam("connection", "string", "The id of the connection.", .T.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, lcId, lcCur, lnN, loJ, loD, loA, lnDs
		loM = THIS.Conn(toContext)
		IF ISNULL(loM)
			RETURN THIS.oRefusal
		ENDIF
		lcId = THIS.PText(toContext, "connection")
		lcCur = "FDT" + SYS(2015)
		lnN = loM.Tables(lcId, lcCur)
		IF lnN < 0
			RETURN THIS.Refused(loM)
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loA = loJ.MakeArray()
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		SELECT (lcCur)
		SCAN
			loA.Add(ALLTRIM(name))
		ENDSCAN
		USE IN (lcCur)
		SET DATASESSION TO (lnDs)
		loJ.Put(loD, "connection", LOWER(lcId))
		loJ.Put(loD, "database", loM.CurrentDatabase(lcId))
		loJ.Put(loD, "count", loA.Count)
		loJ.Put(loD, "tables", loA)
		_screen.oFoxDock.AgentDid("read the tables of connection '" + LOWER(lcId) + "' (" + TRANSFORM(loA.Count) + ")")
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataDbDescribeTool AS IdeDataDbTool
	ToolName = "ide_data_db_describe"
	ToolDescription = "The columns of a table of a database connection of FoxDock: name (as the server's catalog has it), " + ;
		"type (the Visual FoxPro type letter it arrives as), width, decimals, nullable and primaryKey; and key, the " + ;
		"primary key's columns. Only for a connection with agentCanRead true. Reads only."

	FUNCTION DefineParameters()
		THIS.AddParam("connection", "string", "The id of the connection.", .T.)
		THIS.AddParam("table", "string", "The table, as ide_data_db_tables gives it (case does not matter).", .T.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, lcId, lcCur, lcName, loJ, loD, loA, loO, lnDs, lcKey
		loM = THIS.Conn(toContext)
		IF ISNULL(loM)
			RETURN THIS.oRefusal
		ENDIF
		lcId = THIS.PText(toContext, "connection")
		lcCur = "FDC" + SYS(2015)
		lcName = loM.Columns(lcId, THIS.PText(toContext, "table"), lcCur)
		IF EMPTY(lcName)
			RETURN THIS.Refused(loM)
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loA = loJ.MakeArray()
		lcKey = ""
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		SELECT (lcCur)
		SCAN
			loO = loJ.MakeObject()
			loJ.Put(loO, "name", ALLTRIM(name))
			loJ.Put(loO, "type", ALLTRIM(type))
			loJ.Put(loO, "width", width)
			loJ.Put(loO, "decimals", decimals)
			loJ.Put(loO, "nullable", nullable)
			loJ.Put(loO, "primaryKey", primary_key)
			loA.Add(loO)
			IF primary_key
				lcKey = lcKey + IIF(EMPTY(lcKey), "", ",") + ALLTRIM(name)
			ENDIF
		ENDSCAN
		USE IN (lcCur)
		SET DATASESSION TO (lnDs)
		loJ.Put(loD, "connection", LOWER(lcId))
		loJ.Put(loD, "table", lcName)
		loJ.Put(loD, "key", lcKey)
		loJ.Put(loD, "columns", loA)
		_screen.oFoxDock.AgentDid("read the columns of " + lcName + " in connection '" + LOWER(lcId) + "'")
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


*-- Lo que escribe el agente. Actúa (rol 10 o más, RoleRefusal de la base) y
*-- solo en una conexión con allowWrite (el módulo, Execute).
DEFINE CLASS IdeDataDbExecuteTool AS IdeDataDbTool
	ToolName = "ide_data_db_execute"
	ToolDescription = "Runs ONE statement that writes on a database connection of FoxDock (ide_data_db_connections lists " + ;
		"them): INSERT, UPDATE, DELETE, CREATE, ALTER, DROP or TRUNCATE, in the dialect of the server. It needs two things " + ;
		"the programmer gives: allowWrite true in that connection (connections.json, FoxDock > Data > Connections > Edit " + ;
		"connections...) and agent role 10 or higher (FoxDock > FoxAgent > Agent role), besides agentCanRead; without them " + ;
		"it refuses and says which. One statement per call: a ';' with something after it is refused, and a SELECT goes to " + ;
		"ide_data_db_query. An UPDATE or a DELETE without WHERE, a DROP and a TRUNCATE touch the whole table: they run only " + ;
		"with wholeTable true. Each statement is committed when it returns, and the programmer's log keeps it. To make a " + ;
		"table and load it from another one, ide_data_script with 'connection' gives its CREATE TABLE and its INSERT, to " + ;
		"send here one statement at a time. Returns connection, statement (the word it starts with), rowsAffected and ms."
	lActsOnIde = .T.

	FUNCTION DefineParameters()
		THIS.AddParam("connection", "string", "The id of the connection.", .T.)
		THIS.AddParam("sql", "string", "One INSERT, UPDATE, DELETE, CREATE, ALTER, DROP or TRUNCATE in the dialect of the server.", .T.)
		THIS.AddParam("wholeTable", "boolean", "true: an UPDATE or a DELETE without WHERE, a DROP or a TRUNCATE may run.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, lcId, loJ, loD
		loM = THIS.Conn(toContext)
		IF ISNULL(loM)
			RETURN THIS.oRefusal
		ENDIF
		lcId = THIS.PText(toContext, "connection")
		IF !loM.Execute(lcId, THIS.PText(toContext, "sql"), THIS.PBool(toContext, "wholeTable"))
			RETURN THIS.Refused(loM)
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "connection", LOWER(lcId))
		loJ.Put(loD, "statement", loM.cLastStatement)
		loJ.Put(loD, "rowsAffected", loM.nLastAffected)
		loJ.Put(loD, "ms", loM.nLastMs)
		_screen.oFoxDock.AgentDid("wrote on connection '" + LOWER(lcId) + "': " + loM.cLastStatement + " (" + ;
			TRANSFORM(loM.nLastAffected) + " row(s))")
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataDbQueryTool AS IdeDataDbTool
	ToolName = "ide_data_db_query"
	ToolDescription = "Runs ONE read statement on a database connection of FoxDock and returns its rows as JSON, as " + ;
		"ide_data_to_json does (fields in lower case, text without its padding, dates in ISO 8601, null). Only a statement " + ;
		"that starts with SELECT or WITH, without a ';' and something after it, and without words that write (INSERT, " + ;
		"UPDATE, DELETE, DROP, INTO, ...): anything else is refused before it reaches the server. On SQL Server, a table " + ;
		"of another database of the same server is read with its three-part name (database.schema.table). Writing goes through " + ;
		"ide_data_db_execute. Only for a connection with agentCanRead true. Returns connection, returned, truncated (there " + ;
		"were more rows than maxRows) and rows."

	FUNCTION DefineParameters()
		THIS.AddParam("connection", "string", "The id of the connection.", .T.)
		THIS.AddParam("sql", "string", "One SELECT (or WITH ... SELECT) in the dialect of the server.", .T.)
		THIS.AddParam("maxRows", "number", "How many rows at most, from 1 to 1000; 1000 if left out.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loM, lcId, lcCur, lnMax, lcRows, loJ, loD, lcMeta, lnDs
		loM = THIS.Conn(toContext)
		IF ISNULL(loM)
			RETURN THIS.oRefusal
		ENDIF
		lcId = THIS.PText(toContext, "connection")
		lnMax = THIS.MaxRows(toContext)
		lcCur = "FDQ" + SYS(2015)
		IF !loM.Query(lcId, THIS.PText(toContext, "sql"), lnMax, lcCur)
			RETURN THIS.Refused(loM)
		ENDIF
		lcRows = loM.RowsJson(lcCur, lnMax)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		IF USED(lcCur)
			USE IN (lcCur)
		ENDIF
		SET DATASESSION TO (lnDs)
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "connection", LOWER(lcId))
		loJ.Put(loD, "returned", loM.nLastRows)
		loJ.Put(loD, "truncated", loM.lLastTruncated)
		lcMeta = loJ.Stringify(loD)
		_screen.oFoxDock.AgentDid("read " + TRANSFORM(loM.nLastRows) + " row(s) from connection '" + LOWER(lcId) + "'" + ;
			IIF(loM.lLastTruncated, " (there were more)", ""))
		RETURN THIS.Ok(LEFT(lcMeta, LEN(lcMeta) - 1) + [,"rows":] + lcRows + "}")
	ENDFUNC
ENDDEFINE
*------------------------------------------------------------------
* El módulo ai. Lee, con cualquier rol.
*------------------------------------------------------------------
DEFINE CLASS IdeDataAiStatusTool AS IdeDataTool
	ToolName = "ide_data_ai_status"
	ToolDescription = "Whether AIXL (AI over the cursors of the IDE; a product sold apart, not part of FoxDock) is there for " + ;
		"FoxDock > Data > AI in this Visual FoxPro IDE, and how. Returns installed, state ('ready', or why not: " + ;
		"'not_installed', 'no_library' (registered, but its aixl.prg was not found), 'elevated' (the IDE runs as " + ;
		"administrator and does not see an AIXL registered for the user) or 'failed', with code and detail), aixlDir, " + ;
		"foundBy, version, mock (the double of AIXL: nothing is sent and nothing is paid), provider and model (from the " + ;
		"AIXL session, or from its aixl.config.json), configFile (its path only), configNote and lastRun. It never returns " + ;
		"the API key or the licence. The first call creates the AIXL object (the .NET runtime loads: about a third of a " + ;
		"second). The AIXL session is one per IDE: the programmer's command window shares it. Reads only."

	FUNCTION Run(toContext)
		LOCAL loM, loD
		loM = THIS.Module("ai")
		IF ISNULL(loM)
			RETURN THIS.NotThere("ai")
		ENDIF
		loD = loM.ToolStatus()
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE
*------------------------------------------------------------------
* Las operaciones de AIXL para el agente. Actúan (rol 10): escriben
* en un cursor del IDE y gastan dinero del usuario. Solo existen con AIXL listo.
* La base hace lo común (AI_BUSY, los parámetros, TOO_MANY_ROWS por el
* módulo, la respuesta); cada una dice su operación (cKind) y sus parámetros.
*------------------------------------------------------------------
DEFINE CLASS IdeDataAiOpTool AS IdeDataTool
	lActsOnIde = .T.
	cKind = ""

	*-- Los parámetros que la operación no tiene llegan vacíos.
	FUNCTION Op(toContext)
		LOCAL loM, loP, loR
		loM = THIS.Module("ai")
		IF ISNULL(loM)
			RETURN THIS.NotThere("ai")
		ENDIF
		IF loM.lBusy
			RETURN THIS.ErrCode("AI_BUSY", loM.BusyText())
		ENDIF
		loP = CREATEOBJECT("Empty")
		ADDPROPERTY(loP, "cKind", THIS.cKind)
		ADDPROPERTY(loP, "cTable", THIS.PText(toContext, "table"))
		ADDPROPERTY(loP, "cColumn", THIS.PText(toContext, "column"))
		ADDPROPERTY(loP, "cInto", THIS.PText(toContext, "into"))
		ADDPROPERTY(loP, "cInstruction", ICASE(THIS.cKind == "filter", THIS.PText(toContext, "prompt"), ;
			THIS.cKind == "ask", THIS.PText(toContext, "question"), THIS.PText(toContext, "instruction")))
		ADDPROPERTY(loP, "cLabels", ICASE(THIS.cKind == "extract", THIS.PText(toContext, "schema"), ;
			THIS.cKind == "classify", THIS.PText(toContext, "labels"), ""))
		ADDPROPERTY(loP, "cColumns", IIF(INLIST(THIS.cKind, "filter", "ask"), THIS.PText(toContext, "columns"), ""))
		ADDPROPERTY(loP, "lNewCursor", .F.)
		ADDPROPERTY(loP, "nBlock", INT(THIS.PNum(toContext, "blockRows")))
		ADDPROPERTY(loP, "lAgent", .T.)
		*-- maxRows topa lo que se manda; en filter, lo que se devuelve (lo que se manda, agentMaxRows).
		ADDPROPERTY(loP, "nLimit", IIF(THIS.cKind == "filter", loM.AgentMaxRows(), MIN(THIS.MaxRows(toContext), loM.AgentMaxRows())))
		loR = loM.RunOp(loP)
		IF loR.lRefused OR (!loR.lOk AND loR.nRows = 0 AND !loR.lCancelled)
			RETURN THIS.ErrCode(loR.cCode, loR.cMessage)
		ENDIF
		RETURN loR
	ENDFUNC

	*-- Lo común de la respuesta: ok, code, message, las cifras, copy, warnings.
	FUNCTION Common(toR, toJ, toD)
		LOCAL loA, lnI
		toJ.Put(toD, "ok", toR.lOk)
		toJ.Put(toD, "code", IIF(EMPTY(toR.cCode), .NULL., toR.cCode))
		toJ.Put(toD, "message", IIF(EMPTY(toR.cMessage), .NULL., toR.cMessage))
		toJ.Put(toD, "tokensIn", toR.nTokensIn)
		toJ.Put(toD, "tokensOut", toR.nTokensOut)
		toJ.Put(toD, "seconds", toR.nSeconds)
		toJ.Put(toD, "copy", IIF(EMPTY(toR.cCopy), .NULL., toR.cCopy))
		loA = toJ.MakeArray()
		FOR lnI = 1 TO GETWORDCOUNT(toR.cWarnings, CHR(10))
			loA.Add(GETWORDNUM(toR.cWarnings, lnI, CHR(10)))
		ENDFOR
		toJ.Put(toD, "warnings", loA)
	ENDFUNC

	*-- Las operaciones por fila (classify, extract, anonymize): rows, failed y columns.
	FUNCTION RowsAnswer(toR)
		LOCAL loJ, loD, loA, lnI, lcW
		loJ = THIS.J()
		loD = loJ.MakeObject()
		THIS.Common(toR, loJ, loD)
		loJ.Put(loD, "rows", toR.nRows)
		loJ.Put(loD, "failed", toR.nFailed)
		loA = loJ.MakeArray()
		FOR lnI = 1 TO GETWORDCOUNT(toR.cColumns, ",")
			IF !(GETWORDNUM(toR.cColumns, lnI, ",") == "*")
				loA.Add(GETWORDNUM(toR.cColumns, lnI, ","))
			ENDIF
		ENDFOR
		loJ.Put(loD, "columns", loA)
		_screen.oFoxDock.AgentDid(ICASE(THIS.cKind == "extract", "extracted from ", THIS.cKind == "anonymize", "anonymized ", ;
			"classified ") + TRANSFORM(toR.nRows) + " row(s) of " + toR.cWork + " with AIXL" + IIF(EMPTY(toR.cCopy), "", " (a copy)"))
		lcW = loJ.Stringify(loD)
		RETURN THIS.Ok(LEFT(lcW, LEN(lcW) - 1) + [,"errors":] + toR.cErrorsJson + "}")
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loR
		loR = THIS.Op(toContext)
		IF VARTYPE(loR) # "O" OR !PEMSTATUS(loR, "cKind", 5)
			RETURN loR
		ENDIF
		RETURN THIS.RowsAnswer(loR)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataAiClassifyTool AS IdeDataAiOpTool
	ToolName = "ide_data_ai_classify"
	cKind = "classify"
	ToolDescription = "One label per row of a text or memo column of a table or cursor of this Visual FoxPro IDE, by AIXL " + ;
		"(FoxDock > Data > AI > Classify column...; ide_data_ai_status says whether AIXL is there and which provider the " + ;
		"session has: with Mock mode nothing is sent and nothing is paid; otherwise it sends the visible rows to the " + ;
		"programmer's provider and account). It adds three columns at the end, cut to ten characters: <into>, " + ;
		"<into>_con and <into>_rea (confidence and reason); it never rewrites a row nor moves one. A read-only cursor or a " + ;
		".dbf is never written: it works on a copy ai_<name> READWRITE of its visible rows in data session 1, and says so " + ;
		"in 'copy'. It refuses with TOO_MANY_ROWS above the rows the programmer lets the agent send in one call " + ;
		"(options.data.ai.agentMaxRows, 200 by default), and with AI_BUSY while another run is going. Returns rows, " + ;
		"failed, tokensIn, tokensOut, seconds, columns, copy, warnings and errors (the first 20 rows of AIXL_ERRORS)."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("column", "string", "The text or memo column to classify.", .T.)
		THIS.AddParam("into", "string", "The new column; left out, ai_<column> cut to six (so that its _con and _rea fit in ten).", .F.)
		THIS.AddParam("instruction", "string", "What the labels mean, in the programmer's words; may be left out.", .F.)
		THIS.AddParam("labels", "string", "A closed list of labels, comma-separated (high,medium,low); left out, the model chooses.", .F.)
		THIS.AddParam("blockRows", "number", "Rows per block, from 1 to 1000; left out, options.data.ai.blockRows (200).", .F.)
		THIS.AddParam("maxRows", "number", "The most rows this call may send, from 1 to 1000; 1000 if left out. options.data.ai.agentMaxRows caps it.", .F.)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataAiExtractTool AS IdeDataAiOpTool
	ToolName = "ide_data_ai_extract"
	cKind = "extract"
	ToolDescription = "One column per key of a schema, read from a text or memo column of a table or cursor of this Visual " + ;
		"FoxPro IDE, by AIXL (FoxDock > Data > AI > Extract from column...; Mock mode and the provider as ide_data_ai_status " + ;
		"says). It adds <into> and <into>_<key> for each key, cut to ten characters; two keys that give the same name are " + ;
		"refused before anything is sent (SCHEMA_CLASH). A key the text does not have comes back empty, and that is not an " + ;
		"error. Without a schema the model chooses the keys. A read-only cursor or a .dbf goes to a copy ai_<name>, as in " + ;
		"ide_data_ai_classify; TOO_MANY_ROWS and AI_BUSY as there. Returns rows, failed, tokensIn, tokensOut, seconds, " + ;
		"columns, copy, warnings and errors."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("column", "string", "The text or memo column to read.", .T.)
		THIS.AddParam("into", "string", "The prefix of the new columns; left out, ai_<column> cut to six.", .F.)
		THIS.AddParam("instruction", "string", "What to look for, in the programmer's words; may be left out.", .F.)
		THIS.AddParam("schema", "string", "The keys, comma-separated (priority,department); left out, the model chooses.", .F.)
		THIS.AddParam("blockRows", "number", "Rows per block, from 1 to 1000; left out, options.data.ai.blockRows (200).", .F.)
		THIS.AddParam("maxRows", "number", "The most rows this call may send, from 1 to 1000; 1000 if left out. options.data.ai.agentMaxRows caps it.", .F.)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataAiAnonymizeTool AS IdeDataAiOpTool
	ToolName = "ide_data_ai_anonymize"
	cKind = "anonymize"
	ToolDescription = "A copy of a text or memo column of a table or cursor of this Visual FoxPro IDE without what the " + ;
		"instruction says (names, phones, addresses...), by AIXL (FoxDock > Data > AI > Anonymize column...; Mock mode and " + ;
		"the provider as ide_data_ai_status says). It adds one column <into> at the end; the original column is not " + ;
		"touched. A read-only cursor or a .dbf goes to a copy ai_<name>; TOO_MANY_ROWS and AI_BUSY as in " + ;
		"ide_data_ai_classify. Returns rows, failed, tokensIn, tokensOut, seconds, columns, copy, warnings and errors."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("column", "string", "The text or memo column to anonymize.", .T.)
		THIS.AddParam("into", "string", "The new column; left out, ai_<column> cut to ten.", .F.)
		THIS.AddParam("instruction", "string", "What to remove, in the programmer's words; may be left out.", .F.)
		THIS.AddParam("blockRows", "number", "Rows per block, from 1 to 1000; left out, options.data.ai.blockRows (200).", .F.)
		THIS.AddParam("maxRows", "number", "The most rows this call may send, from 1 to 1000; 1000 if left out. options.data.ai.agentMaxRows caps it.", .F.)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataAiFilterTool AS IdeDataAiOpTool
	ToolName = "ide_data_ai_filter"
	cKind = "filter"
	ToolDescription = "Marks the rows of a table or cursor of this Visual FoxPro IDE that pass a prompt, by AIXL (FoxDock > " + ;
		"Data > AI > Filter rows...; Mock mode and the provider as ide_data_ai_status says; the double lets every row pass): " + ;
		"it adds the logical column aixl_keep and deletes nothing. 'columns' are the ones the model sees (left out, the " + ;
		"whole row, which costs more). Returns the rows that pass, as ide_data_to_json gives them (with maxRows), and " + ;
		"kept, dropped, tokensIn, tokensOut, seconds, copy, warnings and errors. A read-only cursor or a .dbf goes to a copy " + ;
		"ai_<name>; TOO_MANY_ROWS and AI_BUSY as in ide_data_ai_classify."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("prompt", "string", "Which rows pass, in the programmer's words (the ones that complain about the delay).", .T.)
		THIS.AddParam("columns", "string", "The columns the model sees, comma-separated; left out, the whole row.", .F.)
		THIS.AddParam("blockRows", "number", "Rows per block, from 1 to 1000; left out, options.data.ai.blockRows (200).", .F.)
		THIS.AddParam("maxRows", "number", "The most rows that pass it returns, from 1 to 1000; 1000 if left out. What it may send is options.data.ai.agentMaxRows.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loR, loJ, loD, lcRows, loM, lcKept, lcW, lnDs, lnSel
		loR = THIS.Op(toContext)
		IF VARTYPE(loR) # "O" OR !PEMSTATUS(loR, "cKind", 5)
			RETURN loR
		ENDIF
		*-- Las que pasan, con la forma de ide_data_to_json: un cursor de paso en la sesión 1.
		*-- El área seleccionada de la sesión 1 se repone después: sin eso, la
		*-- siguiente tool sin «table» ya no encontraría la tabla del usuario.
		lcKept = "FDK" + SYS(2015)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lnSel = SELECT(0)
		SELECT * FROM (loR.cWork) WHERE NVL(aixl_keep, .F.) INTO CURSOR (lcKept)
		SELECT (lnSel)
		SET DATASESSION TO (lnDs)
		loM = THIS.Module("json")
		lcRows = IIF(ISNULL(loM), "{}", loM.ToolJson(lcKept, THIS.MaxRows(toContext)))
		*-- passing dice la tabla de trabajo, no el cursor de paso.
		lcRows = STRTRAN(STRTRAN(lcRows, '"table":"' + LOWER(lcKept) + '"', '"table":"' + loR.cWork + '"'), ;
			'"source":"' + UPPER(lcKept) + '"', '"source":"' + UPPER(loR.cWork) + '"')
		SET DATASESSION TO 1
		USE IN (lcKept)
		SELECT (lnSel)
		SET DATASESSION TO (lnDs)
		loJ = THIS.J()
		loD = loJ.MakeObject()
		THIS.Common(loR, loJ, loD)
		loJ.Put(loD, "kept", loR.nKept)
		loJ.Put(loD, "dropped", loR.nRows + loR.nFailed - loR.nKept)
		_screen.oFoxDock.AgentDid("filtered " + loR.cWork + " with AIXL: " + TRANSFORM(loR.nKept) + " row(s) pass" + ;
			IIF(EMPTY(loR.cCopy), "", " (a copy)"))
		lcW = loJ.Stringify(loD)
		RETURN THIS.Ok(LEFT(lcW, LEN(lcW) - 1) + [,"errors":] + loR.cErrorsJson + [,"passing":] + EVL(lcRows, "{}") + "}")
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeDataAiAskTool AS IdeDataAiOpTool
	ToolName = "ide_data_ai_ask"
	cKind = "ask"
	ToolDescription = "One question about a whole table or cursor of this Visual FoxPro IDE, by AIXL (FoxDock > Data > AI > " + ;
		"Ask about the table...; Mock mode and the provider as ide_data_ai_status says): the answer as text, not a column. " + ;
		"It sends the visible rows (or only 'columns'), and the model reads only the first 4,000 characters of them: " + ;
		"'truncated' says when it did not read them all. To count or add over a big table, classify and count in VFP " + ;
		"instead. It writes nothing; TOO_MANY_ROWS and AI_BUSY as in ide_data_ai_classify. Returns answer, truncated, " + ;
		"rows, tokensIn, tokensOut, seconds and warnings."

	FUNCTION DefineParameters()
		THIS.AddParam("table", "string", DT_TABLE_HELP, .F.)
		THIS.AddParam("question", "string", "The question, in the language you want the answer in.", .T.)
		THIS.AddParam("columns", "string", "The columns the model sees, comma-separated; left out, the whole row.", .F.)
		THIS.AddParam("maxRows", "number", "The most rows this call may send, from 1 to 1000; 1000 if left out. options.data.ai.agentMaxRows caps it.", .F.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loR, loJ, loD
		loR = THIS.Op(toContext)
		IF VARTYPE(loR) # "O" OR !PEMSTATUS(loR, "cKind", 5)
			RETURN loR
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "answer", loR.cAnswer)
		loJ.Put(loD, "truncated", loR.lTruncated)
		loJ.Put(loD, "rows", loR.nRows + loR.nFailed)
		THIS.Common(loR, loJ, loD)
		_screen.oFoxDock.AgentDid("asked AIXL about " + loR.cWork + IIF(loR.lTruncated, " (the model read the first 4,000 characters)", ""))
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE
