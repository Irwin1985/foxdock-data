*==================================================================
* DataScript.prg: el módulo «script» del paquete «data» de FoxDock.
*
*   Script table as >   CREATE TABLE, INSERT, UPDATE de la tabla de trabajo, como
*                       «Script Table as» de SQL Server Management Studio: a
*                       <tabla>-<kind>.sql o .prg (dialecto VFP) en
*                       %LOCALAPPDATA%\FoxDock\data\, en CP1252 sin BOM y abierto
*                       en el editor de VFP: es lo que el usuario retoca, y lo que
*                       leen el editor, SSMS y sqlcmd.
*                       Con options.data.script.utf8 (false), el .sql sale en
*                       UTF-8 con BOM (psql, mysql) y se abre con Windows, nunca en
*                       el editor de VFP; el .prg sigue en CP1252 y en el editor
*   Dialect >           VFP, SQL Server, MySQL / MariaDB, PostgreSQL, SQLite, con
*                       marca; en options.data.script.dialect (por defecto sqlserver)
*   tool                ide_data_script (cualquier rol)
*
* Cómo sale: INSERT, una sentencia por fila, y
* UPDATE por la clave primaria o candidata del CDX (una etiqueta cuya
* expresión es un solo campo) y, si no hay, por todos los campos, con un
* comentario que lo dice; memo como texto; General saltado y dicho; NULL como
* NULL; fecha vacía como NULL en los dialectos SQL (en el de VFP, {}: es su
* valor); fechas ISO 8601. La tabla de tipos por dialecto está en el manual
* (docs\PLUGINS_*.md, «The Data package») y en TypeOf, aquí abajo: si cambia
* una, cambia la otra.
*
* El dialecto VFP: un literal de cadena no pasa de 255 caracteres y una línea
* de órdenes de 8.192 (System Capacities, en la ayuda de VFP). Las cadenas van a trozos
* de 200 unidos con «+», los caracteres de control como CHR(n), y una cadena
* de más de 1000 caracteres de expresión no va en el INSERT o el UPDATE: va
* vacía y se añade detrás, a trozos (REPLACE tras un INSERT, UPDATE tras un
* UPDATE).
*==================================================================

#DEFINE CRLF CHR(13) + CHR(10)
#DEFINE DS_DIALECTS "vfp,sqlserver,mysql,postgresql,sqlite"
#DEFINE DS_PIECE 200
#DEFINE DS_LONG 1000

DEFINE CLASS DataScript AS Custom
	cId = "script"
	oHost = .NULL.
	cLastFile = ""
	cLastError = ""
	cKeyIdx = ""      && las columnas de la clave, sus números separados por comas, una o varias ("": sin clave usable)
	cKeyExpr = ""     && la expresión del INDEX ON del dialecto VFP (la de la etiqueta, o la que se arma)
	cKeyNote = ""     && la línea de comentario que dice por qué UPDATE va como va
	cKeyTag = ""
	cLastCode = ""    && el cLastCode de las conexiones («not_connected») si RemoteScript falla por eso
	*-- La precisión de los campos N de una tabla remota: la del catálogo del
	*-- servidor, y no el ancho del campo de VFP.
	lRemoteNum = .F.  && las columnas son de una conexión (RemoteScript)
	cServerNum = ""   && «,nombre:precisión:escala,» de SQLCOLUMNS NATIVE (decimal y numeric)
	cVfpNum = ""      && «nombre:tipo de VFP;...»: las columnas N de las que el servidor no dio la precisión

	PROCEDURE Init
		LPARAMETERS toHost
		This.oHost = toHost
	ENDPROC

	PROCEDURE DialectName
		LPARAMETERS tcId
		RETURN ICASE(tcId == "vfp", "Visual FoxPro", tcId == "sqlserver", "SQL Server", tcId == "mysql", "MySQL / MariaDB", ;
			tcId == "postgresql", "PostgreSQL", tcId == "sqlite", "SQLite", "")
	ENDPROC

	*-- Los ids de los dialectos, para la ventanita de Script as...
	PROCEDURE Dialects
		RETURN DS_DIALECTS
	ENDPROC

	PROCEDURE IsDialect
		LPARAMETERS tcId
		RETURN VARTYPE(tcId) == "C" AND !EMPTY(tcId) AND "," + LOWER(ALLTRIM(tcId)) + "," $ "," + DS_DIALECTS + ","
	ENDPROC

	*-- El dialecto de config.json; uno que no se conoce, el de por defecto (y se dice).
	PROCEDURE Dialect
		LOCAL lcD
		lcD = LOWER(ALLTRIM(TRANSFORM(This.oHost.Options.Get("data", "script.dialect", "sqlserver"))))
		IF !This.IsDialect(lcD)
			This.oHost.LogWarn("data.script: options.data.script.dialect is '" + lcD + "', not one of " + DS_DIALECTS + ;
				"; sqlserver is used")
			lcD = "sqlserver"
		ENDIF
		RETURN lcD
	ENDPROC

	*-- El paquete, por el host: el módulo no guarda una referencia a él (el
	*-- paquete guarda las suyas a los módulos, y una circular no se suelta).
	PROCEDURE Plugin
		RETURN This.oHost.PluginById("data")
	ENDPROC

	PROCEDURE FillMenu
		LPARAMETERS tcPopup, tnBar
		LOCAL lcS, lcD, lnI, lcCur, lcCmd, loP
		loP = This.Plugin()
		LOCAL ARRAY laD[1]
		lcS = tcPopup + "S"
		lcD = tcPopup + "D"
		*-- En el idioma de FoxDock (DataStrings.prg); CREATE TABLE,
		*-- INSERT, UPDATE y los nombres de los motores no se traducen.
		tnBar = loP.DefineSubmenu(tcPopup, tnBar + 1, This.oHost.Translate("data.script.menu"), lcS)
		loP.DefineBar(lcS, 1, "\<CREATE TABLE", "ScriptAs", "create", This.oHost.Translate("data.script.create.message"))
		loP.DefineBar(lcS, 2, "\<INSERT", "ScriptAs", "insert", This.oHost.Translate("data.script.insert.message"))
		loP.DefineBar(lcS, 3, "\<UPDATE", "ScriptAs", "update", This.oHost.Translate("data.script.update.message"))
		tnBar = loP.DefineSubmenu(tcPopup, tnBar + 1, This.oHost.Translate("data.script.dialect"), lcD)
		lcCur = This.Dialect()
		FOR lnI = 1 TO ALINES(laD, DS_DIALECTS, 1, ",")
			loP.DefineBar(lcD, lnI, This.Hotkey(laD[lnI]), "SetDialect", laD[lnI], ;
				This.oHost.Translate("data.script.dialect.message", This.DialectName(laD[lnI])))
			lcCmd = "SET MARK OF BAR " + TRANSFORM(lnI) + " OF " + lcD + " TO " + IIF(laD[lnI] == lcCur, ".T.", ".F.")
			&lcCmd
		ENDFOR
		RETURN tnBar
	ENDPROC

	PROTECTED PROCEDURE Hotkey
		LPARAMETERS tcId
		RETURN ICASE(tcId == "vfp", "\<VFP", tcId == "sqlserver", "SQL \<Server", tcId == "mysql", "\<MySQL / MariaDB", ;
			tcId == "postgresql", "\<PostgreSQL", "SQL\<ite")
	ENDPROC

	PROCEDURE GetAgentTools
		LPARAMETERS toTools
		toTools.Add(CREATEOBJECT("IdeDataScriptTool"))
		RETURN 1
	ENDPROC

	*--------------------------------------------------------------
	* Las barras.
	*--------------------------------------------------------------
	PROCEDURE SetDialect
		LPARAMETERS tcDialect
		tcDialect = LOWER(ALLTRIM(TRANSFORM(tcDialect)))
		IF !This.IsDialect(tcDialect)
			This.oHost.LogWarn("data.script: '" + tcDialect + "' is not a dialect (" + DS_DIALECTS + ")")
			RETURN .F.
		ENDIF
		This.oHost.Options.Set("data", "script.dialect", tcDialect)
		This.oHost.RefreshMenu()
		This.oHost.NotifyKey("data.script.inDialect", This.DialectName(tcDialect))
		RETURN .T.
	ENDPROC

	PROCEDURE ScriptAs
		LPARAMETERS tcKind
		LOCAL loT, loR, lcFile, lcDialect, loErr, llOk, lcSkipped, loP
		tcKind = LOWER(ALLTRIM(TRANSFORM(tcKind)))
		IF !INLIST(tcKind, "create", "insert", "update")
			This.oHost.LogWarn("data.script: '" + tcKind + "' is not create, insert or update")
			RETURN .F.
		ENDIF
		lcDialect = This.Dialect()
		loT = CREATEOBJECT("DataTable")
		llOk = .F.
		TRY
			IF loT.Open("", .T.)
				loP = This.Plugin()
				lcFile = loP.OutDir() + loT.cName + "-" + tcKind + IIF(lcDialect == "vfp", ".prg", ".sql")
				loR = This.Script(loT, tcKind, lcDialect, 0, lcFile)
				lcSkipped = loT.cSkipped
				llOk = .T.
			ELSE
				IF !EMPTY(loT.cError)
					This.oHost.NotifyQuoted("data.said", loT.cError)
				ENDIF
			ENDIF
		CATCH TO loErr
			This.oHost.LogFault("data.script: Script table as " + UPPER(tcKind) + " failed: " + TRANSFORM(loErr.ErrorNo) + ;
				" " + loErr.Message)
			This.oHost.Notify(This.oHost.Translate("data.script.failed", UPPER(tcKind), This.oHost.Quoted(loErr.Message)), ;
				This.oHost.TranslateEn("data.script.failed", UPPER(tcKind), loErr.Message))
		FINALLY
			loT.Close()
		ENDTRY
		IF llOk
			This.cLastFile = lcFile
			IF This.Utf8File(lcDialect)
				=loP.OpenWithWindows(lcFile)
			ELSE
				=This.oHost.Editor.Open(lcFile)
			ENDIF
			This.oHost.Notify(This.oHost.Translate("data.script.done", loT.cName, This.KindName(tcKind), This.DialectName(lcDialect), ;
				IIF(tcKind == "create", "", ", " + loT.RowsShown(This.oHost, loR.nRows)), This.oHost.Translate("data.inFile", lcFile), ;
				IIF(EMPTY(lcSkipped), "", This.oHost.Translate("data.skippedGeneral", lcSkipped))), ;
				This.oHost.TranslateEn("data.script.done", loT.cName, This.KindName(tcKind), This.DialectName(lcDialect), ;
				IIF(tcKind == "create", "", ", " + loT.Rows(loR.nRows)), This.oHost.TranslateEn("data.inFile", lcFile), ;
				IIF(EMPTY(lcSkipped), "", This.oHost.TranslateEn("data.skippedGeneral", lcSkipped))))
		ENDIF
		RETURN llOk
	ENDPROC

	*-- El .sql en UTF-8 con BOM: solo con options.data.script.utf8 y nunca el
	*-- .prg del dialecto VFP.
	PROCEDURE Utf8File
		LPARAMETERS tcDialect
		LOCAL luV
		luV = This.oHost.Options.Get("data", "script.utf8", .F.)
		RETURN !(tcDialect == "vfp") AND VARTYPE(luV) == "L" AND luV
	ENDPROC

	PROCEDURE KindName
		LPARAMETERS tcKind
		RETURN ICASE(tcKind == "create", "CREATE TABLE", tcKind == "insert", "INSERT", "UPDATE")
	ENDPROC

	*--------------------------------------------------------------
	* El script.
	*--------------------------------------------------------------

	*-- El script de la tabla de trabajo. Con tcFile, entero a ese fichero
	*-- (tnMax 0); sin él, hasta tnMax filas en cText. Devuelve un Empty con
	*-- nRows, nDone, lTruncated y cText.
	*-- tlKeySet: la clave ya está puesta (RemoteKey); tnTotal, las filas
	*-- que tiene la tabla cuando el cursor solo trae las primeras (las del
	*-- servidor): las que falten salen como truncado.
	PROCEDURE Script
		LPARAMETERS toT, tcKind, tcDialect, tnMax, tcFile, tlKeySet, tnTotal
		LOCAL loF, loR, lcC, lnTotal, lnN, llTrunc, lcList, llVfp, llShow, llAllKey, lcCreate
		LOCAL ARRAY laRow[1]
		llVfp = tcDialect == "vfp"
		loF = CREATEOBJECT("DataFile", tcFile, IIF(This.Utf8File(tcDialect), "utf8bom", "ansi"))
		lcC = IIF(llVfp, "* ", "-- ")
		IF !tlKeySet
			This.FindKey(toT)
		ENDIF
		lnTotal = IIF(tcKind == "create", 0, IIF(VARTYPE(tnTotal) == "N" AND tnTotal >= 0, tnTotal, toT.RowCount()))
		loF.Write(lcC + toT.cName + ": " + This.KindName(tcKind) + " for " + This.DialectName(tcDialect) + ;
			IIF(tcKind == "create", "", ", " + toT.Rows(lnTotal)) + ", from FoxDock" + CRLF)
		IF !EMPTY(toT.cSkipped)
			loF.Write(lcC + "skipped: " + toT.cSkipped + " (General: its contents are not scripted)" + CRLF)
		ENDIF
		IF tcKind == "update"
			loF.Write(lcC + This.cKeyNote + CRLF)
		ENDIF
		lnN = 0
		llTrunc = .F.
		IF tcKind == "create"
			This.cVfpNum = ""
			lcCreate = IIF(llVfp, This.CreateVfp(toT), This.CreateSql(toT, tcDialect))
			*-- Las columnas N cuya precisión no dio el servidor, dichas.
			FOR lnN = 1 TO GETWORDCOUNT(This.cVfpNum, ";")
				lcList = GETWORDNUM(This.cVfpNum, lnN, ";")
				loF.Write(lcC + GETWORDNUM(lcList, 1, ":") + ": precision from the VFP field (" + GETWORDNUM(lcList, 2, ":") + ;
					"): the server may differ" + CRLF)
			ENDFOR
			lnN = 0
			loF.Write(lcCreate)
		ELSE
			*-- Con todas las columnas en la clave no hay nada que poner
			*-- en el SET: el comentario lo dice, y ningún UPDATE.
			llAllKey = tcKind == "update" AND This.KeyCount() > 1 AND This.KeyCount() = toT.nCols
			IF llAllKey
				loF.Write(lcC + toT.cName + ": every column is in the key (" + This.KeyNames(toT) + ;
					"), so there is nothing to SET: no UPDATE is written" + CRLF)
			ENDIF
			llShow = _screen.Visible AND !EMPTY(tcFile) AND lnTotal > 20000
			lcList = toT.cFieldList
			SELECT (toT.cAlias)
			SCAN FOR !llAllKey
				IF tnMax > 0 AND lnN >= tnMax
					llTrunc = .T.
					EXIT
				ENDIF
				SCATTER FIELDS &lcList MEMO TO laRow
				loF.Write(IIF(tcKind == "insert", This.InsertRow(toT, tcDialect, @laRow), This.UpdateRow(toT, tcDialect, @laRow)))
				lnN = lnN + 1
				IF llShow AND lnN % 10000 = 0
					WAIT WINDOW "Data: " + toT.cName + " as " + This.KindName(tcKind) + ", " + TRANSFORM(lnN) + " of " + ;
						TRANSFORM(lnTotal) + " rows..." NOWAIT
				ENDIF
			ENDSCAN
			llTrunc = llTrunc OR (lnN < lnTotal AND !llAllKey)
			IF llTrunc
				loF.Write(lcC + "truncated: the first " + TRANSFORM(lnN) + " of " + toT.Rows(lnTotal) + CRLF)
			ENDIF
		ENDIF
		loF.Flush()
		loR = CREATEOBJECT("Empty")
		ADDPROPERTY(loR, "nRows", lnTotal)
		ADDPROPERTY(loR, "nDone", lnN)
		ADDPROPERTY(loR, "lTruncated", llTrunc)
		ADDPROPERTY(loR, "cText", IIF(EMPTY(tcFile), loF.cBuffer, ""))
		RETURN loR
	ENDPROC

	*-- El script de la tabla tcTable de la
	*-- conexión tcId, sin abrirla en la sesión del usuario. Las columnas y la clave
	*-- salen de la conexión (GetColumns, GetPrimaryKey: lo que el cursor de un
	*-- SELECT * remoto no trae); las filas de INSERT y UPDATE, de
	*-- TableSelect a un cursor que se cierra siempre. Devuelve lo de Script con
	*-- cName, cSource, cKey y cSkipped, o .NULL. con el motivo en cLastError (y
	*-- en cLastCode el de las conexiones: «not_connected» si es eso).
	PROCEDURE RemoteScript
		LPARAMETERS tcId, tcTable, tcKind, tcDialect, tnMax, tcFile
		LOCAL loP, loM, loC, loDb, lcName, lcCols, lcTmp, lcKey, loT, loR, lnDs, loErr, llOk, lnTotal, lcErr
		This.cLastError = ""
		This.cLastCode = ""
		loP = This.Plugin()
		loM = loP.Module("connections")
		IF ISNULL(loM)
			This.cLastError = "The connections module of the data package is not loaded (options.data.connections.enabled)."
			RETURN .NULL.
		ENDIF
		lcName = loM.ObjectName(tcId, tcTable)
		IF EMPTY(lcName)
			This.cLastError = loM.cLastError
			This.cLastCode = loM.cLastCode
			RETURN .NULL.
		ENDIF
		loC = loM.Find(tcId)
		loDb = loM.Live(loC.cId)
		lcCols = "FDK" + SYS(2015)
		lcTmp = "FDX" + SYS(2015)
		lcKey = ""
		lcErr = ""
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		This.lRemoteNum = .T.
		This.cServerNum = ""
		TRY
			llOk = loDb.GetColumns(lcName, lcCols)
			IF llOk
				lcKey = LOWER(STRTRAN(loDb.GetPrimaryKey(lcName), " ", ""))
				This.cServerNum = This.ServerNumbers(loDb.nHandle, lcName)
			ENDIF
		CATCH TO loErr
			llOk = .F.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		SET DATASESSION TO (lnDs)
		IF !llOk
			IF loM.CheckLost(loC.cId, EVL(lcErr, loDb.cLastError))
				This.cLastError = loM.cLastError
				This.cLastCode = loM.cLastCode
			ELSE
				This.cLastError = "The columns of '" + lcName + "' could not be read: " + EVL(lcErr, loDb.cLastError)
			ENDIF
			This.CloseCursor(lcCols)
			RETURN .NULL.
		ENDIF
		loR = .NULL.
		loT = CREATEOBJECT("DataTable")
		TRY
			llOk = .T.
			IF tcKind == "create"
				This.ColumnsFrom(loT, lcCols, lcKey)
				lnTotal = 0
			ELSE
				lnTotal = loM.ServerCount(loC.cId, lcName)
				llOk = loM.TableSelect(loC.cId, lcName, tnMax, lcTmp)
				IF llOk
					llOk = loT.Open(lcTmp, .F.)
					This.cLastError = loT.cError
				ELSE
					This.cLastError = loM.cLastError
					This.cLastCode = loM.cLastCode
				ENDIF
			ENDIF
			IF llOk
				loT.cName = LOWER(lcName)
				loT.cSource = loC.cId + ":" + lcName
				This.RemoteKey(loT, lcKey, loC.cName)
				loR = This.Script(loT, tcKind, tcDialect, 0, tcFile, .T., lnTotal)
				ADDPROPERTY(loR, "cName", loT.cName)
				ADDPROPERTY(loR, "cSource", loT.cSource)
				ADDPROPERTY(loR, "cKey", This.KeyNames(loT))
				ADDPROPERTY(loR, "cSkipped", loT.cSkipped)
			ENDIF
		CATCH TO loErr
			loR = .NULL.
			This.cLastError = "Scripting " + lcName + " failed: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		FINALLY
			This.lRemoteNum = .F.
			This.cServerNum = ""
			loT.Close()
			This.CloseCursor(lcTmp)
			This.CloseCursor(lcCols)
		ENDTRY
		RETURN loR
	ENDPROC

	*-- La precisión y la escala de las columnas decimal y
	*-- numeric de tcTable, del catálogo ODBC del servidor (SQLCOLUMNS NATIVE:
	*-- column_size y decimal_digits; SQL Server da 10 y 2 para un decimal(10,2),
	*-- donde VFP da N(12,2)). SQLite da otro catálogo (el de ODBC 2), y sus
	*-- DECIMAL no llegan a VFP como N: ahí no hay nada que tomar. «,nombre:p:s,».
	PROCEDURE ServerNumbers
		LPARAMETERS tnHandle, tcTable
		LOCAL lnDs, lcOut, lcCur, loErr
		lcOut = ""
		lcCur = "FDN" + SYS(2015)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			IF SQLCOLUMNS(tnHandle, tcTable, "NATIVE", lcCur) > 0 AND USED(lcCur) AND ;
					TYPE(lcCur + ".column_size") == "N" AND TYPE(lcCur + ".decimal_digits") == "N"
				SELECT (lcCur)
				SCAN FOR INLIST(data_type, 2, 3) AND !ISNULL(column_size) AND !ISNULL(decimal_digits)
					lcOut = lcOut + "," + LOWER(ALLTRIM(column_name)) + ":" + TRANSFORM(column_size) + ":" + TRANSFORM(decimal_digits)
				ENDSCAN
			ENDIF
		CATCH TO loErr
			lcOut = ""
		ENDTRY
		IF USED(lcCur)
			USE IN (lcCur)
		ENDIF
		SET DATASESSION TO (lnDs)
		RETURN IIF(EMPTY(lcOut), "", lcOut + ",")
	ENDPROC

	PROTECTED PROCEDURE CloseCursor
		LPARAMETERS tcAlias
		LOCAL lnDs
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		IF USED(tcAlias)
			USE IN (tcAlias)
		ENDIF
		SET DATASESSION TO (lnDs)
	ENDPROC

	*-- Las columnas de CREATE TABLE para una tabla remota, de lo que da
	*-- GetColumns (las letras de tipo de VFP con las que llegan). Una
	*-- columna de la clave es NOT NULL aunque el motor la dé como nullable
	*-- (SQLite), y un varchar(max) de SQL Server llega como C(0): va como memo.
	PROTECTED PROCEDURE ColumnsFrom
		LPARAMETERS toT, tcCols, tcKey
		LOCAL lnDs, lcName, lcType
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		toT.nCols = 0
		toT.cFieldList = ""
		SELECT (tcCols)
		SCAN
			lcName = LOWER(ALLTRIM(name))
			lcType = ALLTRIM(type)
			toT.nCols = toT.nCols + 1
			DIMENSION toT.aCols[toT.nCols, 6]
			toT.aCols[toT.nCols, 1] = lcName
			toT.aCols[toT.nCols, 2] = IIF(INLIST(lcType, "C", "V") AND width = 0, "M", lcType)
			toT.aCols[toT.nCols, 3] = width
			toT.aCols[toT.nCols, 4] = decimals
			toT.aCols[toT.nCols, 5] = nullable AND !primary_key AND !("," + lcName + "," $ "," + tcKey + ",")
			toT.aCols[toT.nCols, 6] = .F.
			toT.cFieldList = toT.cFieldList + IIF(EMPTY(toT.cFieldList), "", ",") + lcName
		ENDSCAN
		SET DATASESSION TO (lnDs)
	ENDPROC

	*-- La clave de UPDATE y de CREATE TABLE para una tabla remota, la de
	*-- GetPrimaryKey (tcKey: sus columnas separadas por comas). Con una o varias
	*-- columnas, por ellas, en su orden; si no hay, o una no
	*-- está entre las columnas, por todos los campos, con su comentario.
	PROCEDURE RemoteKey
		LPARAMETERS toT, tcKey, tcConnName
		LOCAL lnI, lnCol, lcIdx, lcExpr, lcName, lcT
		STORE "" TO This.cKeyIdx, This.cKeyTag, This.cKeyExpr, lcIdx, lcExpr
		FOR lnI = 1 TO GETWORDCOUNT(tcKey, ",")
			lcName = ALLTRIM(GETWORDNUM(tcKey, lnI, ","))
			lnCol = This.ColumnOf(toT, lcName)
			IF lnCol = 0
				lcIdx = ""
				EXIT
			ENDIF
			lcIdx = lcIdx + IIF(EMPTY(lcIdx), "", ",") + TRANSFORM(lnCol)
			*-- El INDEX ON del dialecto VFP: cada columna como texto, para unirlas con +.
			lcT = toT.aCols[lnCol, 2]
			lcExpr = lcExpr + IIF(EMPTY(lcExpr), "", "+") + ICASE(INLIST(lcT, "C", "V"), lcName, INLIST(lcT, "N", "F", "I", "B", "Y"), ;
				"STR(" + lcName + ")", lcT == "D", "DTOS(" + lcName + ")", lcT == "T", "TTOC(" + lcName + ", 1)", "?")
		ENDFOR
		IF EMPTY(lcIdx)
			This.cKeyNote = toT.cName + " has no primary key in " + tcConnName + ": each UPDATE finds its row by all its fields"
			RETURN
		ENDIF
		This.cKeyIdx = lcIdx
		*-- Una columna: su nombre. Varias: la expresión, si se puede armar.
		This.cKeyExpr = IIF(This.KeyCount() = 1, ALLTRIM(tcKey), IIF("?" $ lcExpr, "", lcExpr))
		*-- Un TAG de VFP no pasa de 10 caracteres.
		This.cKeyTag = LEFT(CHRTRAN(tcKey, ",", "_"), 10)
		This.cKeyNote = "key: " + This.KeyNames(toT) + " (the primary key of " + toT.cName + " in " + tcConnName + ")"
	ENDPROC

	*-- Cuántas columnas tiene la clave, si una lo es, y sus
	*-- nombres separados por «, » ("" sin clave).
	PROCEDURE KeyCount
		RETURN GETWORDCOUNT(This.cKeyIdx, ",")
	ENDPROC

	PROCEDURE IsKey
		LPARAMETERS tnCol
		RETURN "," + TRANSFORM(tnCol) + "," $ "," + This.cKeyIdx + ","
	ENDPROC

	PROCEDURE KeyNames
		LPARAMETERS toT
		LOCAL lnI, lcOut
		lcOut = ""
		FOR lnI = 1 TO This.KeyCount()
			lcOut = lcOut + IIF(lnI > 1, ", ", "") + toT.aCols[VAL(GETWORDNUM(This.cKeyIdx, lnI, ",")), 1]
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- Las columnas de una expresión de índice (la de ATAGINFO,
	*-- en minúsculas y sin espacios): trozos unidos con +, cada uno un
	*-- campo, a secas o dentro de STR(), ALLTRIM(), PADR() o DTOS(). Sus números,
	*-- separados por comas, o "" si algún trozo es otra cosa.
	PROCEDURE KeyColumns
		LPARAMETERS toT, tcExpr
		LOCAL lnI, lnDepth, lcC, lcPiece, lcOut, lnCol
		STORE "" TO lcOut, lcPiece
		lnDepth = 0
		FOR lnI = 1 TO LEN(tcExpr) + 1
			lcC = IIF(lnI > LEN(tcExpr), "+", SUBSTR(tcExpr, lnI, 1))
			DO CASE
				CASE lcC == "+" AND lnDepth = 0
					lnCol = This.PieceColumn(toT, ALLTRIM(lcPiece))
					IF lnCol = 0
						RETURN ""
					ENDIF
					IF !("," + TRANSFORM(lnCol) + "," $ "," + lcOut + ",")
						lcOut = lcOut + IIF(EMPTY(lcOut), "", ",") + TRANSFORM(lnCol)
					ENDIF
					lcPiece = ""
				CASE lcC == "("
					lnDepth = lnDepth + 1
					lcPiece = lcPiece + lcC
				CASE lcC == ")"
					lnDepth = lnDepth - 1
					lcPiece = lcPiece + lcC
				OTHERWISE
					lcPiece = lcPiece + lcC
			ENDCASE
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- Un trozo de la expresión: el número de su campo, o 0.
	PROTECTED PROCEDURE PieceColumn
		LPARAMETERS toT, tcPiece
		LOCAL lnP, lcFunc, lcArg
		lnP = AT("(", tcPiece)
		IF lnP = 0
			RETURN This.ColumnOf(toT, tcPiece)
		ENDIF
		lcFunc = LEFT(tcPiece, lnP - 1)
		IF !INLIST(lcFunc, "str", "alltrim", "padr", "dtos") OR !(RIGHT(tcPiece, 1) == ")")
			RETURN 0
		ENDIF
		lcArg = ALLTRIM(GETWORDNUM(SUBSTR(tcPiece, lnP + 1, LEN(tcPiece) - lnP - 1), 1, ","))
		RETURN IIF("(" $ lcArg, 0, This.ColumnOf(toT, lcArg))
	ENDPROC

	*-- La clave de UPDATE: la primera etiqueta PRIMARY y, si no, la primera
	*-- CANDIDATE, si su expresión es un campo de la tabla y no tiene filtro.
	*-- O varios campos unidos con + (KeyColumns).
	PROCEDURE FindKey
		LPARAMETERS toT
		LOCAL lnN, lnI, lnJ, lcExpr, lcFound, lcCols
		LOCAL ARRAY laT[1]
		STORE "" TO This.cKeyIdx, This.cKeyTag, This.cKeyExpr
		lcFound = ""
		lnN = 0
		IF USED(toT.cAlias)
			lnN = ATAGINFO(laT, "", toT.cAlias)
		ENDIF
		FOR lnJ = 1 TO 2
			FOR lnI = 1 TO lnN
				IF !(UPPER(laT[lnI, 2]) == IIF(lnJ = 1, "PRIMARY", "CANDIDATE"))
					LOOP
				ENDIF
				lcExpr = LOWER(ALLTRIM(laT[lnI, 3]))
				lcCols = This.KeyColumns(toT, lcExpr)
				IF !EMPTY(lcCols) AND EMPTY(laT[lnI, 4])
					This.cKeyIdx = lcCols
					This.cKeyExpr = lcExpr
					This.cKeyTag = LOWER(laT[lnI, 1])
					This.cKeyNote = "key: " + IIF(This.KeyCount() = 1, lcExpr, This.KeyNames(toT)) + " (" + LOWER(laT[lnI, 2]) + ;
						" index tag " + This.cKeyTag + IIF(This.KeyCount() = 1, "", " on " + lcExpr) + ")"
					RETURN This.KeyCount()
				ENDIF
				IF EMPTY(lcFound)
					lcFound = LOWER(laT[lnI, 2]) + " index tag " + LOWER(laT[lnI, 1]) + IIF(EMPTY(laT[lnI, 4]), ;
						" is on " + lcExpr + ", not on fields of the table", " has a filter (FOR " + LOWER(laT[lnI, 4]) + ")")
				ENDIF
			ENDFOR
		ENDFOR
		This.cKeyNote = toT.cName + IIF(EMPTY(lcFound), " has no primary or candidate key in its CDX", ;
			"'s " + lcFound) + ": each UPDATE finds its row by all its fields"
		RETURN 0
	ENDPROC

	PROCEDURE ColumnOf
		LPARAMETERS toT, tcName
		LOCAL lnI
		FOR lnI = 1 TO toT.nCols
			IF toT.aCols[lnI, 1] == tcName
				RETURN lnI
			ENDIF
		ENDFOR
		RETURN 0
	ENDPROC

	*-- El nombre de una tabla o un campo, entrecomillado como manda el motor.
	PROCEDURE Q
		LPARAMETERS tcName, tcDialect
		RETURN ICASE(tcDialect == "sqlserver", "[" + tcName + "]", tcDialect == "mysql", "`" + tcName + "`", ;
			tcDialect == "vfp", tcName, ["] + tcName + ["])
	ENDPROC

	*-- El tipo de una columna en un dialecto: la tabla del manual.
	PROCEDURE TypeOf
		LPARAMETERS toT, tnCol, tcDialect
		LOCAL lcT, lnW, lnD, lcWD, lcNum
		lcT = toT.aCols[tnCol, 2]
		lnW = toT.aCols[tnCol, 3]
		lnD = toT.aCols[tnCol, 4]
		lcWD = "(" + TRANSFORM(lnW) + "," + TRANSFORM(lnD) + ")"
		*-- Un campo N de una conexión lleva la precisión del servidor; si el
		*-- servidor no la dio, la del campo de VFP, y el script lo dice (cVfpNum).
		IF This.lRemoteNum AND INLIST(lcT, "N", "F") AND !(tcDialect == "vfp")
			lcNum = STREXTRACT(This.cServerNum, "," + LOWER(toT.aCols[tnCol, 1]) + ":", ",")
			IF EMPTY(lcNum)
				This.cVfpNum = This.cVfpNum + IIF(EMPTY(This.cVfpNum), "", ";") + LOWER(toT.aCols[tnCol, 1]) + ":" + ;
					This.TypeOf(toT, tnCol, "vfp")
			ELSE
				lcWD = "(" + CHRTRAN(lcNum, ":", ",") + ")"
			ENDIF
		ENDIF
		DO CASE
			CASE tcDialect == "vfp"
				RETURN ICASE(INLIST(lcT, "C", "V", "Q"), lcT + "(" + TRANSFORM(lnW) + ")", ;
					INLIST(lcT, "N", "F"), lcT + IIF(lnD = 0, "(" + TRANSFORM(lnW) + ")", lcWD), ;
					lcT == "B", "B(" + TRANSFORM(lnD) + ")", lcT)
			CASE tcDialect == "sqlserver"
				RETURN ICASE(INLIST(lcT, "C", "V"), "NVARCHAR(" + TRANSFORM(lnW) + ")", lcT == "M", "NVARCHAR(MAX)", ;
					INLIST(lcT, "N", "F"), "DECIMAL" + lcWD, lcT == "I", "INT", lcT == "B", "FLOAT", lcT == "Y", "MONEY", ;
					lcT == "D", "DATE", lcT == "T", "DATETIME2(0)", lcT == "L", "BIT", ;
					lcT == "Q", "VARBINARY(" + TRANSFORM(lnW) + ")", "VARBINARY(MAX)")
			CASE tcDialect == "mysql"
				RETURN ICASE(INLIST(lcT, "C", "V"), "VARCHAR(" + TRANSFORM(lnW) + ")", lcT == "M", "LONGTEXT", ;
					INLIST(lcT, "N", "F"), "DECIMAL" + lcWD, lcT == "I", "INT", lcT == "B", "DOUBLE", lcT == "Y", "DECIMAL(19,4)", ;
					lcT == "D", "DATE", lcT == "T", "DATETIME", lcT == "L", "BOOLEAN", ;
					lcT == "Q", "VARBINARY(" + TRANSFORM(lnW) + ")", "LONGBLOB")
			CASE tcDialect == "postgresql"
				RETURN ICASE(INLIST(lcT, "C", "V"), "VARCHAR(" + TRANSFORM(lnW) + ")", lcT == "M", "TEXT", ;
					INLIST(lcT, "N", "F"), "NUMERIC" + lcWD, lcT == "I", "INTEGER", lcT == "B", "DOUBLE PRECISION", ;
					lcT == "Y", "NUMERIC(19,4)", lcT == "D", "DATE", lcT == "T", "TIMESTAMP", lcT == "L", "BOOLEAN", "BYTEA")
		ENDCASE
		RETURN ICASE(INLIST(lcT, "C", "V", "M", "D", "T"), "TEXT", INLIST(lcT, "N", "F", "Y"), "NUMERIC", ;
			INLIST(lcT, "I", "L"), "INTEGER", lcT == "B", "REAL", "BLOB")
	ENDPROC

	PROCEDURE CreateSql
		LPARAMETERS toT, tcDialect
		LOCAL lcOut, lnI
		lcOut = "CREATE TABLE " + This.Q(toT.cName, tcDialect) + " (" + CRLF
		FOR lnI = 1 TO toT.nCols
			lcOut = lcOut + "    " + This.Q(toT.aCols[lnI, 1], tcDialect) + " " + This.TypeOf(toT, lnI, tcDialect) + ;
				IIF(toT.aCols[lnI, 5], " NULL", " NOT NULL") + IIF(lnI < toT.nCols OR This.KeyCount() > 0, ",", "") + CRLF
		ENDFOR
		IF This.KeyCount() > 0
			lcOut = lcOut + "    PRIMARY KEY (" + This.KeyList(toT, tcDialect) + ")" + CRLF
		ENDIF
		RETURN lcOut + ")" + IIF(tcDialect == "mysql", " DEFAULT CHARSET=utf8mb4", "") + ";" + CRLF
	ENDPROC

	PROCEDURE CreateVfp
		LPARAMETERS toT
		LOCAL lcOut, lnI
		lcOut = "CREATE TABLE " + toT.cName + " FREE ( ;" + CRLF
		FOR lnI = 1 TO toT.nCols
			lcOut = lcOut + CHR(9) + toT.aCols[lnI, 1] + " " + This.TypeOf(toT, lnI, "vfp") + ;
				IIF(toT.aCols[lnI, 5], " NULL", " NOT NULL") + IIF(toT.aCols[lnI, 6], " NOCPTRANS", "") + ;
				IIF(lnI < toT.nCols, ", ;", ")") + CRLF
		ENDFOR
		IF This.KeyCount() > 0 AND !EMPTY(This.cKeyExpr)
			lcOut = lcOut + "INDEX ON " + This.cKeyExpr + " TAG " + This.cKeyTag + " CANDIDATE" + CRLF
		ENDIF
		RETURN lcOut
	ENDPROC

	*-- Las columnas de la clave, citadas como manda el dialecto, separadas por «, ».
	PROCEDURE KeyList
		LPARAMETERS toT, tcDialect
		LOCAL lnI, lcOut
		lcOut = ""
		FOR lnI = 1 TO This.KeyCount()
			lcOut = lcOut + IIF(lnI > 1, ", ", "") + This.Q(toT.aCols[VAL(GETWORDNUM(This.cKeyIdx, lnI, ",")), 1], tcDialect)
		ENDFOR
		RETURN lcOut
	ENDPROC

	PROCEDURE ColumnList
		LPARAMETERS toT, tcDialect
		LOCAL lcOut, lnI
		lcOut = ""
		FOR lnI = 1 TO toT.nCols
			lcOut = lcOut + IIF(lnI > 1, ", ", "") + This.Q(toT.aCols[lnI, 1], tcDialect)
		ENDFOR
		RETURN lcOut
	ENDPROC

	PROCEDURE InsertRow
		LPARAMETERS toT, tcDialect, taRow
		LOCAL lcVals, lcTail, lnI, lcV, loP, loGroups
		lcVals = ""
		lcTail = ""
		FOR lnI = 1 TO toT.nCols
			lcV = This.Literal(toT, lnI, taRow[lnI], tcDialect)
			IF tcDialect == "vfp" AND LEN(lcV) > DS_LONG
				*-- Largo: vacío en el INSERT y a trozos detrás (el puntero está en la fila nueva).
				loGroups = This.Groups(toT.Text(lnI, taRow[lnI]))
				FOR EACH loP IN loGroups
					lcTail = lcTail + "REPLACE " + toT.aCols[lnI, 1] + " WITH " + toT.aCols[lnI, 1] + " + " + loP + CRLF
				ENDFOR
				lcV = ["]+["]
			ENDIF
			lcVals = lcVals + IIF(lnI > 1, ", ", "") + lcV
		ENDFOR
		RETURN "INSERT INTO " + This.Q(toT.cName, tcDialect) + " (" + This.ColumnList(toT, tcDialect) + ") VALUES (" + ;
			lcVals + ")" + IIF(tcDialect == "vfp", "", ";") + CRLF + lcTail
	ENDPROC

	PROCEDURE UpdateRow
		LPARAMETERS toT, tcDialect, taRow
		LOCAL lcSet, lcWhere, lcTail, lnI, lcV, loP, llVfp, llLong, loGroups, lnCol
		LOCAL ARRAY laLong[1]
		llVfp = tcDialect == "vfp"
		lcSet = ""
		lcWhere = ""
		lcTail = ""
		FOR lnI = 1 TO toT.nCols
			lcV = This.Literal(toT, lnI, taRow[lnI], tcDialect)
			llLong = llVfp AND LEN(lcV) > DS_LONG
			IF This.KeyCount() = 0 OR This.IsKey(lnI)
				IF !llLong
					lcWhere = lcWhere + IIF(EMPTY(lcWhere), "", " AND ") + This.Equals(toT, lnI, lcV, tcDialect)
				ENDIF
			ENDIF
			IF !This.IsKey(lnI) OR toT.nCols = 1
				IF llLong
					lcTail = lcTail + "," + TRANSFORM(lnI)
					lcV = ["]+["]
				ENDIF
				lcSet = lcSet + IIF(EMPTY(lcSet), "", ", ") + This.Q(toT.aCols[lnI, 1], tcDialect) + " = " + lcV
			ENDIF
		ENDFOR
		lcV = "UPDATE " + This.Q(toT.cName, tcDialect) + " SET " + lcSet + " WHERE " + lcWhere + IIF(llVfp, "", ";") + CRLF
		FOR lnI = 1 TO ALINES(laLong, lcTail, 1 + 4, ",")
			lnCol = VAL(laLong[lnI])
			loGroups = This.Groups(toT.Text(lnCol, taRow[lnCol]))
			FOR EACH loP IN loGroups
				lcV = lcV + "UPDATE " + toT.cName + " SET " + toT.aCols[lnCol, 1] + " = " + toT.aCols[lnCol, 1] + " + " + ;
					loP + " WHERE " + lcWhere + CRLF
			ENDFOR
		ENDFOR
		RETURN lcV
	ENDPROC

	*-- Una condición de WHERE: NULL con IS NULL (ISNULL() en VFP); en VFP, el
	*-- texto con == (con SET ANSI OFF, «=» da por buena una cadena que empieza
	*-- igual) y un Character sin su relleno.
	PROCEDURE Equals
		LPARAMETERS toT, tnCol, tcLit, tcDialect
		LOCAL lcCol, lcT
		lcCol = This.Q(toT.aCols[tnCol, 1], tcDialect)
		lcT = toT.aCols[tnCol, 2]
		DO CASE
			CASE tcDialect == "vfp" AND tcLit == ".NULL."
				RETURN "ISNULL(" + lcCol + ")"
			CASE tcLit == "NULL"
				RETURN lcCol + " IS NULL"
			CASE tcDialect == "vfp" AND lcT == "C"
				RETURN "RTRIM(" + lcCol + ") == " + tcLit
			CASE tcDialect == "vfp" AND INLIST(lcT, "V", "M", "Q", "W")
				RETURN lcCol + " == " + tcLit
		ENDCASE
		RETURN lcCol + " = " + tcLit
	ENDPROC

	*-- Un valor como literal del dialecto.
	PROCEDURE Literal
		LPARAMETERS toT, tnCol, tvValue, tcDialect
		LOCAL lcT, lcS, llVfp
		llVfp = tcDialect == "vfp"
		IF ISNULL(tvValue)
			RETURN IIF(llVfp, ".NULL.", "NULL")
		ENDIF
		lcT = toT.aCols[tnCol, 2]
		DO CASE
			CASE INLIST(lcT, "C", "V", "M")
				lcS = toT.Text(tnCol, tvValue)
				IF llVfp
					RETURN This.VfpString(lcS)
				ENDIF
				lcS = STRTRAN(lcS, "'", "''")
				IF tcDialect == "mysql"
					lcS = STRTRAN(lcS, "\", "\\")
				ENDIF
				RETURN IIF(tcDialect == "sqlserver", "N", "") + "'" + lcS + "'"
			CASE lcT == "Y"
				RETURN IIF(llVfp, "NTOM(" + toT.Num(tnCol, tvValue) + ")", toT.Num(tnCol, tvValue))
			CASE INLIST(lcT, "N", "F", "I", "B")
				RETURN toT.Num(tnCol, tvValue)
			CASE lcT == "D"
				lcS = toT.IsoDate(tvValue)
				RETURN ICASE(EMPTY(lcS), IIF(llVfp, "{}", "NULL"), llVfp, "{^" + lcS + "}", "'" + lcS + "'")
			CASE lcT == "T"
				lcS = toT.IsoTime(tvValue)
				RETURN ICASE(EMPTY(lcS), IIF(llVfp, "{/:}", "NULL"), llVfp, "{^" + STRTRAN(lcS, "T", " ") + "}", ;
					tcDialect == "sqlserver", "'" + lcS + "'", "'" + STRTRAN(lcS, "T", " ") + "'")
			CASE lcT == "L"
				RETURN ICASE(llVfp, IIF(tvValue, ".T.", ".F."), INLIST(tcDialect, "mysql", "postgresql"), ;
					IIF(tvValue, "TRUE", "FALSE"), IIF(tvValue, "1", "0"))
			CASE INLIST(lcT, "Q", "W")
				lcS = STRCONV(tvValue, 15)
				RETURN ICASE(llVfp, "0h" + lcS, tcDialect == "sqlserver", "0x" + lcS, tcDialect == "postgresql", ;
					"'\x" + lcS + "'", "X'" + lcS + "'")
		ENDCASE
		RETURN IIF(llVfp, ".NULL.", "NULL")
	ENDPROC

	*-- Una cadena como expresión de VFP: trozos de DS_PIECE caracteres entre
	*-- el delimitador que no lleven dentro, y los de control como CHR(n).
	PROCEDURE VfpString
		LPARAMETERS tcS
		LOCAL loP, lcOut, loPieces
		lcOut = ""
		loPieces = This.Pieces(tcS)
		FOR EACH loP IN loPieces
			lcOut = lcOut + IIF(EMPTY(lcOut), "", " + ") + loP
		ENDFOR
		RETURN IIF(EMPTY(lcOut), ["]+["], lcOut)
	ENDPROC

	PROCEDURE Pieces
		LPARAMETERS tcS
		LOCAL loOut, lnI, lcC, lcRun
		loOut = CREATEOBJECT("Collection")
		lcRun = ""
		FOR lnI = 1 TO LEN(tcS)
			lcC = SUBSTR(tcS, lnI, 1)
			IF ASC(lcC) < 32
				IF !EMPTY(lcRun)
					loOut.Add(This.Delimit(lcRun))
					lcRun = ""
				ENDIF
				loOut.Add("CHR(" + TRANSFORM(ASC(lcC)) + ")")
				LOOP
			ENDIF
			lcRun = lcRun + lcC
			IF LEN(lcRun) >= DS_PIECE
				loOut.Add(This.Delimit(lcRun))
				lcRun = ""
			ENDIF
		ENDFOR
		IF LEN(lcRun) > 0
			loOut.Add(This.Delimit(lcRun))
		ENDIF
		RETURN loOut
	ENDPROC

	PROTECTED PROCEDURE Delimit
		LPARAMETERS tcRun
		DO CASE
			CASE !(["] $ tcRun)
				RETURN ["] + tcRun + ["]
			CASE !("'" $ tcRun)
				RETURN "'" + tcRun + "'"
			CASE !("[" $ tcRun) AND !("]" $ tcRun)
				RETURN "[" + tcRun + "]"
		ENDCASE
		RETURN ["] + STRTRAN(tcRun, ["], [" + CHR(34) + "]) + ["]
	ENDPROC

	*-- Los trozos de una cadena larga, juntos de DS_LONG en DS_LONG caracteres
	*-- de expresión: uno por REPLACE o por UPDATE.
	PROCEDURE Groups
		LPARAMETERS tcS
		LOCAL loOut, loP, lcG, loPieces
		loOut = CREATEOBJECT("Collection")
		lcG = ""
		loPieces = This.Pieces(tcS)
		FOR EACH loP IN loPieces
			IF !EMPTY(lcG) AND LEN(lcG) + 3 + LEN(loP) > DS_LONG
				loOut.Add(lcG)
				lcG = ""
			ENDIF
			lcG = lcG + IIF(EMPTY(lcG), "", " + ") + loP
		ENDFOR
		IF !EMPTY(lcG)
			loOut.Add(lcG)
		ENDIF
		RETURN loOut
	ENDPROC

	*-- Lo que devuelve ide_data_script, o "" con el motivo en cLastError.
	*-- Con tcConn, tcTable es una tabla de esa conexión (RemoteScript).
	PROCEDURE ToolScript
		LPARAMETERS tcTable, tcKind, tcDialect, tnMax, tcConn
		LOCAL loT, loR, loJ, loD, loSk, lcOut, lnI, loErr
		LOCAL ARRAY laSk[1]
		This.cLastError = ""
		This.cLastCode = ""
		lcOut = ""
		tcKind = LOWER(ALLTRIM(tcKind))
		tcDialect = LOWER(ALLTRIM(tcDialect))
		DO CASE
			CASE !INLIST(tcKind, "create", "insert", "update")
				This.cLastError = "'kind' is '" + tcKind + "': it has to be create, insert or update."
				RETURN ""
			CASE EMPTY(tcDialect)
				tcDialect = This.Dialect()
			CASE !This.IsDialect(tcDialect)
				This.cLastError = "'dialect' is '" + tcDialect + "': it has to be one of " + DS_DIALECTS + ;
					" (or left out for the one in FoxDock > Data > Dialect)."
				RETURN ""
		ENDCASE
		IF !EMPTY(tcConn)
			IF EMPTY(tcTable)
				This.cLastError = "'table' is needed with 'connection': the table of that connection to script."
				RETURN ""
			ENDIF
			loR = This.RemoteScript(tcConn, tcTable, tcKind, tcDialect, IIF(tcKind == "create", 0, tnMax), "")
			IF ISNULL(loR)
				RETURN ""
			ENDIF
			loJ = This.oHost.oJson
			loD = loJ.MakeObject()
			loJ.Put(loD, "table", loR.cName)
			loJ.Put(loD, "source", loR.cSource)
			loJ.Put(loD, "kind", tcKind)
			loJ.Put(loD, "dialect", tcDialect)
			loJ.Put(loD, "rowCount", loR.nRows)
			loJ.Put(loD, "returned", loR.nDone)
			loJ.Put(loD, "truncated", loR.lTruncated)
			loJ.Put(loD, "key", IIF(EMPTY(loR.cKey), .NULL., loR.cKey))
			loSk = loJ.MakeArray()
			FOR lnI = 1 TO ALINES(laSk, loR.cSkipped, 1 + 4, ",")
				loSk.Add(laSk[lnI])
			ENDFOR
			loJ.Put(loD, "skipped", loSk)
			loJ.Put(loD, "script", loR.cText)
			RETURN loJ.Stringify(loD)
		ENDIF
		loT = CREATEOBJECT("DataTable")
		TRY
			IF loT.Open(tcTable, .F.)
				loR = This.Script(loT, tcKind, tcDialect, tnMax, "")
				loJ = This.oHost.oJson
				loD = loJ.MakeObject()
				loJ.Put(loD, "table", loT.cName)
				loJ.Put(loD, "source", loT.cSource)
				loJ.Put(loD, "kind", tcKind)
				loJ.Put(loD, "dialect", tcDialect)
				loJ.Put(loD, "rowCount", loR.nRows)
				loJ.Put(loD, "returned", loR.nDone)
				loJ.Put(loD, "truncated", loR.lTruncated)
				loJ.Put(loD, "key", IIF(This.KeyCount() > 0, This.KeyNames(loT), .NULL.))
				loSk = loJ.MakeArray()
				FOR lnI = 1 TO ALINES(laSk, loT.cSkipped, 1 + 4, ",")
					loSk.Add(laSk[lnI])
				ENDFOR
				loJ.Put(loD, "skipped", loSk)
				loJ.Put(loD, "script", loR.cText)
				lcOut = loJ.Stringify(loD)
			ELSE
				This.cLastError = loT.cError
			ENDIF
		CATCH TO loErr
			This.cLastError = "Scripting the table failed: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
			lcOut = ""
		FINALLY
			loT.Close()
		ENDTRY
		RETURN lcOut
	ENDPROC
ENDDEFINE
