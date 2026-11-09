*==================================================================
* DataJson.prg: el módulo «json» del paquete «data» de FoxDock.
*
*   Table to JSON     la tabla de trabajo entera a <tabla>.json (UTF-8), en
*                     %LOCALAPPDATA%\FoxDock\data\, abierta con la aplicación de
*                     Windows para .json, nunca en el editor de VFP (allí cada
*                     tilde sale como dos caracteres, y guardarlo lo estropea),
*                     y las 1000 primeras filas al portapapeles
*   JSON to cursor    del portapapeles si parece JSON (empieza por [ o {); si
*                     no, de un .json que se elige (GETFILE): un cursor
*                     json_<n> en la sesión 1, con BROWSE NOWAIT. Un JSON que no
*                     se lee se dice en la barra de estado y en el log, sin diálogo
*   tools             ide_data_to_json (cualquier rol), ide_data_from_json (10 o más)
*
* EL JSON LO ESCRIBE ESTE MÓDULO, y no CursorToJSON de JSONFox, por dos motivos:
* CursorToJSON escribe cada letra fuera del ASCII como \uXXXX, y el .json es
* para que una persona lo lea (Mu\u00F1oz no se lee); y aquí el fichero va
* fila a fila y las tools cortan en maxRows, cuando CursorToJSON hace la
* tabla entera en una cadena. Con los \uXXXX vueltos a CP1252, los dos
* escriben lo mismo, y DataJsonTests.TestCursorToJsonWritesWhatDataJsonWritesWithTheLettersEscaped
* lo comprueba. LEER lo hace JSONFox (JSONToCursor), y lo escrito aquí vuelve
* con el mismo texto.
*
* Cada valor:  C, V, M  texto sin el relleno del final, en CPCURRENT()
*              N, F     número con los decimales de la columna; I sin ellos; Y con 4
*              B        su valor guardado: el decimal más corto que vuelve al mismo
*                       Double (DataTable.DoubleText)
*              D, T     ISO 8601 ("AAAA-MM-DD", "AAAA-MM-DDThh:mm:ss"); vacía: null
*              L        true / false
*              Q, W     base64
*              G        no sale (se dice en «skipped» y en la barra de estado)
*              NULL     null
* El fichero va en UTF-8 sin BOM, convertido desde CPCURRENT() (VFP ya
* tradujo al leer); el portapapeles y las tools, en CPCURRENT().
*
* Fichero en CP1252, con los acentos escritos.
*==================================================================

#DEFINE CRLF CHR(13) + CHR(10)
#DEFINE DJ_MAX_ROWS 1000

DEFINE CLASS DataJson AS Custom
	cId = "json"
	oHost = .NULL.
	cLastFile = ""
	cLastCursor = ""
	cLastClip = ""    && lo último que puso en el portapapeles (lo lee la suite)
	cLastError = ""
	nLastRows = 0
	cCtl = ""         && los caracteres de control que van como \u00XX

	PROCEDURE Init
		LPARAMETERS toHost
		LOCAL lnI
		This.oHost = toHost
		FOR lnI = 0 TO 31
			IF !INLIST(lnI, 8, 9, 10, 12, 13)
				This.cCtl = This.cCtl + CHR(lnI)
			ENDIF
		ENDFOR
	ENDPROC

	*-- El paquete, por el host: el módulo no guarda una referencia a él (el
	*-- paquete guarda las suyas a los módulos, y una circular no se suelta).
	PROCEDURE Plugin
		RETURN This.oHost.PluginById("data")
	ENDPROC

	PROCEDURE FillMenu
		LPARAMETERS tcPopup, tnBar
		LOCAL loP
		loP = This.Plugin()
		*-- En el idioma de FoxDock (DataStrings.prg).
		tnBar = loP.DefineBar(tcPopup, tnBar + 1, This.oHost.Translate("data.json.toJson"), "TableToJson", "", ;
			This.oHost.Translate("data.json.toJson.message"))
		tnBar = loP.DefineBar(tcPopup, tnBar + 1, This.oHost.Translate("data.json.toCursor"), "JsonToCursor", "", ;
			This.oHost.Translate("data.json.toCursor.message"))
		RETURN tnBar
	ENDPROC

	PROCEDURE GetAgentTools
		LPARAMETERS toTools
		toTools.Add(CREATEOBJECT("IdeDataToJsonTool"))
		toTools.Add(CREATEOBJECT("IdeDataFromJsonTool"))
		RETURN 2
	ENDPROC

	*--------------------------------------------------------------
	* Las barras.
	*--------------------------------------------------------------
	PROCEDURE TableToJson
		LOCAL loT, loR, lcFile, loErr, llOk, lcSkipped, loP, llClip
		loT = CREATEOBJECT("DataTable")
		llOk = .F.
		lcFile = ""
		TRY
			IF loT.Open("", .T.)
				loP = This.Plugin()
				lcFile = loP.OutDir() + loT.cName + ".json"
				loR = This.Walk(loT, 0, lcFile, DJ_MAX_ROWS)
				This.cLastClip = "[" + CRLF + loR.cClip + IIF(EMPTY(loR.cClip), "", CRLF) + "]"
				llClip = This.oHost.ToClipboard(This.cLastClip, "Table to JSON of " + loT.cName)
				lcSkipped = loT.cSkipped
				llOk = .T.
			ELSE
				IF !EMPTY(loT.cError)
					This.oHost.NotifyQuoted("data.said", loT.cError)
				ENDIF
			ENDIF
		CATCH TO loErr
			This.oHost.LogFault("data.json: Table to JSON failed: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message)
			This.oHost.NotifyQuoted("data.json.failed", loErr.Message)
		FINALLY
			loT.Close()
		ENDTRY
		IF llOk
			This.cLastFile = lcFile
			loP = This.Plugin()
			=loP.OpenWithWindows(lcFile)
			IF !llClip
				*-- El fichero está escrito, pero otro programa tiene el portapapeles.
				This.oHost.Notify(This.oHost.Translate("data.json.doneNoClip", loT.cName, loT.RowsShown(This.oHost, loR.nRows), ;
					This.oHost.Translate("data.inFile", lcFile), IIF(EMPTY(lcSkipped), "", This.oHost.Translate("data.skippedGeneral", lcSkipped))), ;
					This.oHost.TranslateEn("data.json.doneNoClip", loT.cName, loT.Rows(loR.nRows), This.oHost.TranslateEn("data.inFile", lcFile), ;
					IIF(EMPTY(lcSkipped), "", This.oHost.TranslateEn("data.skippedGeneral", lcSkipped))))
				RETURN llOk
			ENDIF
			This.oHost.Notify(This.oHost.Translate("data.json.done", loT.cName, loT.RowsShown(This.oHost, loR.nRows), ;
				This.oHost.Translate("data.inFile", lcFile), ;
				IIF(loR.nRows > DJ_MAX_ROWS, This.oHost.Translate("data.json.clipFirst", DJ_MAX_ROWS), This.oHost.Translate("data.json.clipAll")), ;
				IIF(EMPTY(lcSkipped), "", This.oHost.Translate("data.skippedGeneral", lcSkipped))), ;
				This.oHost.TranslateEn("data.json.done", loT.cName, loT.Rows(loR.nRows), This.oHost.TranslateEn("data.inFile", lcFile), ;
				IIF(loR.nRows > DJ_MAX_ROWS, This.oHost.TranslateEn("data.json.clipFirst", DJ_MAX_ROWS), This.oHost.TranslateEn("data.json.clipAll")), ;
				IIF(EMPTY(lcSkipped), "", This.oHost.TranslateEn("data.skippedGeneral", lcSkipped))))
		ENDIF
		RETURN llOk
	ENDPROC

	*-- tcJson: el texto, para quien no quiera pasar por el portapapeles (la
	*-- suite: en una máquina en uso, otro proceso lo cambia entre el caso y la
	*-- barra). La barra no lo pasa y lee el portapapeles. Con texto, nunca
	*-- GETFILE: si no es JSON, lo dice.
	PROCEDURE JsonToCursor
		LPARAMETERS tcJson
		LOCAL lcClip, lcJson, lcFrom, lcFile, lcCursor, lnDs, llGiven
		llGiven = VARTYPE(tcJson) == "C" AND !EMPTY(tcJson)
		lcClip = IIF(llGiven, tcJson, _CLIPTEXT)
		IF llGiven OR INLIST(LEFT(ALLTRIM(lcClip, 1, " ", CHR(9), CHR(13), CHR(10)), 1), "[", "{")
			lcJson = lcClip
			lcFrom = IIF(llGiven, "data.json.fromText", "data.json.fromClipboard")
		ELSE
			lcFile = GETFILE("JSON", "JSON:", This.oHost.Translate("data.json.getfile.open"), 0, ;
				This.oHost.Translate("data.json.getfile.title"))
			IF EMPTY(lcFile)
				RETURN .F.
			ENDIF
			lcJson = This.ReadFile(lcFile)
			lcFrom = lcFile
		ENDIF
		*-- lcFrom es una clave (el portapapeles, el texto) o la ruta del fichero.
		lcCursor = This.FromJson(lcJson, "")
		IF EMPTY(lcCursor)
			This.oHost.Notify(This.oHost.Translate("data.json.notRead", This.FromShown(lcFrom, .F.), This.oHost.Quoted(This.cLastError)), ;
				This.oHost.TranslateEn("data.json.notRead", This.FromShown(lcFrom, .T.), This.cLastError))
			RETURN .F.
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		SELECT (lcCursor)
		IF _screen.Visible
			BROWSE NOWAIT
		ENDIF
		SET DATASESSION TO (lnDs)
		This.oHost.Notify(This.oHost.Translate("data.json.cursor", lcCursor, This.nLastRows, This.FromShown(lcFrom, .F.)), ;
			This.oHost.TranslateEn("data.json.cursor", lcCursor, This.nLastRows, This.FromShown(lcFrom, .T.)))
		RETURN .T.
	ENDPROC

	*-- De dónde vino el JSON, dicho (tlEn: en inglés, para el log).
	PROTECTED PROCEDURE FromShown
		LPARAMETERS tcFrom, tlEn
		IF LEFT(tcFrom, 10) == "data.json."
			RETURN IIF(tlEn, This.oHost.TranslateEn(tcFrom), This.oHost.Translate(tcFrom))
		ENDIF
		RETURN tcFrom
	ENDPROC

	*--------------------------------------------------------------
	* Lo que usan las barras y las tools.
	*--------------------------------------------------------------

	*-- Recorre la tabla de trabajo. Con tcFile, la escribe entera ahí (tnMax 0)
	*-- y guarda las tnClip primeras en cClip; sin él, junta hasta tnMax en
	*-- cClip. Devuelve un Empty con nRows (las que hay), nDone (las que se
	*-- recorrieron), lTruncated y cClip (los objetos separados por coma y CRLF).
	*-- Con toInto (un DataFile abierto), escribe ahí el array y no lo cierra:
	*-- Export... lo pone dentro de su documento.
	PROCEDURE Walk
		LPARAMETERS toT, tnMax, tcFile, tnClip, toInto
		LOCAL loR, loF, lcList, lcRow, lnN, lnTotal, llTrunc, lcClip, llShow, llInto
		LOCAL ARRAY laRow[1]
		lnTotal = toT.RowCount()
		llInto = VARTYPE(toInto) == "O"
		IF llInto
			tcFile = ""
			tnClip = 0
			loF = toInto
			loF.Write("[" + CRLF)
		ENDIF
		DO CASE
			CASE llInto
			CASE EMPTY(tcFile)
				tnClip = tnMax
			OTHERWISE
				loF = CREATEOBJECT("DataFile", tcFile, "utf8")
				loF.Write("[" + CRLF)
		ENDCASE
		llShow = _screen.Visible AND !EMPTY(tcFile) AND lnTotal > 20000
		lcList = toT.cFieldList
		lcClip = ""
		lnN = 0
		llTrunc = .F.
		SELECT (toT.cAlias)
		SCAN
			IF tnMax > 0 AND lnN >= tnMax
				llTrunc = .T.
				EXIT
			ENDIF
			SCATTER FIELDS &lcList MEMO TO laRow
			lcRow = This.RowJson(toT, @laRow)
			lnN = lnN + 1
			IF lnN <= tnClip
				lcClip = lcClip + IIF(lnN > 1, "," + CRLF, "") + lcRow
			ENDIF
			IF !EMPTY(tcFile) OR llInto
				loF.Write(IIF(lnN > 1, "," + CRLF, "") + lcRow)
				IF llShow AND lnN % 10000 = 0
					WAIT WINDOW "Data: " + toT.cName + " to JSON, " + TRANSFORM(lnN) + " of " + TRANSFORM(lnTotal) + " rows..." NOWAIT
				ENDIF
			ENDIF
		ENDSCAN
		DO CASE
			CASE llInto
				loF.Write(IIF(lnN > 0, CRLF, "") + "]")
			CASE !EMPTY(tcFile)
				loF.Write(IIF(lnN > 0, CRLF, "") + "]" + CRLF)
				loF.Flush()
		ENDCASE
		loR = CREATEOBJECT("Empty")
		ADDPROPERTY(loR, "nRows", lnTotal)
		ADDPROPERTY(loR, "nDone", lnN)
		ADDPROPERTY(loR, "lTruncated", llTrunc)
		ADDPROPERTY(loR, "cClip", lcClip)
		RETURN loR
	ENDPROC

	*-- Una fila (laRow, de SCATTER con las columnas de aCols) como objeto JSON.
	PROCEDURE RowJson
		LPARAMETERS toT, taRow
		LOCAL lnI, lcOut
		lcOut = "{"
		FOR lnI = 1 TO toT.nCols
			lcOut = lcOut + IIF(lnI > 1, ",", "") + ["] + toT.aCols[lnI, 1] + [":] + This.ValueJson(toT, lnI, taRow[lnI])
		ENDFOR
		RETURN lcOut + "}"
	ENDPROC

	PROCEDURE ValueJson
		LPARAMETERS toT, tnCol, tvValue
		LOCAL lcS
		IF ISNULL(tvValue)
			RETURN "null"
		ENDIF
		DO CASE
			CASE INLIST(toT.aCols[tnCol, 2], "C", "V", "M")
				RETURN This.Quote(toT.Text(tnCol, tvValue))
			CASE INLIST(toT.aCols[tnCol, 2], "N", "F", "I", "B", "Y")
				RETURN toT.Num(tnCol, tvValue)
			CASE toT.aCols[tnCol, 2] == "D"
				lcS = toT.IsoDate(tvValue)
				RETURN IIF(EMPTY(lcS), "null", ["] + lcS + ["])
			CASE toT.aCols[tnCol, 2] == "T"
				lcS = toT.IsoTime(tvValue)
				RETURN IIF(EMPTY(lcS), "null", ["] + lcS + ["])
			CASE toT.aCols[tnCol, 2] == "L"
				RETURN IIF(tvValue, "true", "false")
			CASE INLIST(toT.aCols[tnCol, 2], "Q", "W")
				RETURN ["] + STRCONV(tvValue, 13) + ["]
		ENDCASE
		RETURN "null"
	ENDPROC

	*-- Una cadena JSON (RFC 8259): las comillas, la barra y los de control.
	PROCEDURE Quote
		LPARAMETERS tcS
		LOCAL lnI, lcC, lcOut
		tcS = STRTRAN(tcS, "\", "\\")
		tcS = STRTRAN(tcS, ["], [\"])
		tcS = STRTRAN(tcS, CHR(13), "\r")
		tcS = STRTRAN(tcS, CHR(10), "\n")
		tcS = STRTRAN(tcS, CHR(9), "\t")
		tcS = STRTRAN(tcS, CHR(8), "\b")
		tcS = STRTRAN(tcS, CHR(12), "\f")
		IF LEN(CHRTRAN(tcS, This.cCtl, "")) < LEN(tcS)
			lcOut = ""
			FOR lnI = 1 TO LEN(tcS)
				lcC = SUBSTR(tcS, lnI, 1)
				lcOut = lcOut + IIF(lcC $ This.cCtl, "\u" + RIGHT(TRANSFORM(ASC(lcC), "@0"), 4), lcC)
			ENDFOR
			tcS = lcOut
		ENDIF
		RETURN ["] + tcS + ["]
	ENDPROC

	*-- Un .json del disco en CPCURRENT(): en UTF-8 (con o sin BOM) si lo es; si
	*-- no se deja leer como UTF-8 (un byte suelto de 1252), tal cual.
	PROCEDURE ReadFile
		LPARAMETERS tcFile
		LOCAL lcRaw, lcAnsi
		lcRaw = FILETOSTR(tcFile)
		IF LEFT(lcRaw, 3) == CHR(0xEF) + CHR(0xBB) + CHR(0xBF)
			lcRaw = SUBSTR(lcRaw, 4)
		ENDIF
		lcAnsi = STRCONV(lcRaw, 11, CPCURRENT(), 1)
		IF STRCONV(lcAnsi, 9, CPCURRENT(), 1) == lcRaw
			RETURN lcAnsi
		ENDIF
		RETURN lcRaw
	ENDPROC

	*-- Un cursor en la sesión de datos 1 desde un texto JSON (un array de
	*-- objetos, o un objeto suelto: una fila). tcCursor vacío: json_<n>, el
	*-- primero libre. Devuelve su nombre, o "" con el motivo en cLastError.
	*-- También lee el documento de Export... de Explore... (un objeto con
	*-- table, connection, columns y, si van, rows): sus filas; y sin rows, un
	*-- cursor vacío con las columnas del esquema (SchemaCursor).
	PROCEDURE FromJson
		LPARAMETERS tcJson, tcCursor
		LOCAL lcText, lcCursor, lnDs, loJ, loErr, lnI, loP, lcRows, lcSchema
		This.cLastError = ""
		This.cLastCursor = ""
		This.nLastRows = 0
		lcText = ALLTRIM(IIF(VARTYPE(tcJson) $ "CM", tcJson, ""), 1, " ", CHR(9), CHR(13), CHR(10))
		lcSchema = ""
		DO CASE
			CASE LEFT(lcText, 1) == "{"
				lcRows = This.TopArray(lcText, "rows")
				lcSchema = IIF(EMPTY(lcRows), This.TopArray(lcText, "columns"), "")
				DO CASE
					CASE !EMPTY(lcRows)
						lcText = lcRows
					CASE !EMPTY(lcSchema) AND ["name"] $ lcSchema AND ["type"] $ lcSchema
					OTHERWISE
						lcSchema = ""
						lcText = "[" + lcText + "]"
				ENDCASE
			CASE !(LEFT(lcText, 1) == "[")
				This.cLastError = "it is not JSON: it does not start with [ or {."
				RETURN ""
		ENDCASE
		lcCursor = ALLTRIM(IIF(VARTYPE(tcCursor) == "C", tcCursor, ""))
		IF !EMPTY(lcCursor) AND !This.IsName(lcCursor)
			This.cLastError = "'" + lcCursor + "' is not a valid cursor name (a letter or _ first, then letters, digits " + ;
				"or _, up to 128)."
			RETURN ""
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			DO CASE
				CASE EMPTY(lcCursor)
					FOR lnI = 1 TO 9999
						IF !USED("json_" + TRANSFORM(lnI))
							lcCursor = "json_" + TRANSFORM(lnI)
							EXIT
						ENDIF
					ENDFOR
				CASE USED(lcCursor)
					This.cLastError = "'" + lcCursor + "' is already in use in data session 1 of the IDE: give another " + ;
						"name, or leave 'cursor' out for json_<n>."
					lcCursor = ""
			ENDCASE
			DO CASE
				CASE EMPTY(lcCursor)
				CASE !EMPTY(lcSchema)
					IF This.SchemaCursor(lcSchema, lcCursor)
						This.cLastCursor = lcCursor
					ENDIF
				OTHERWISE
					loP = This.Plugin()
					loJ = loP.JsonFox()
					loJ.JSONToCursor(lcText, lcCursor, 1)
					DO CASE
						CASE loJ.lError
							This.cLastError = loJ.cLastError
						CASE !USED(lcCursor)
							This.cLastError = "JSONFox made no cursor from it."
						OTHERWISE
							This.nLastRows = RECCOUNT(lcCursor)
							This.cLastCursor = lcCursor
					ENDCASE
			ENDCASE
		CATCH TO loErr
			This.cLastError = loErr.Message
		FINALLY
			IF EMPTY(This.cLastCursor) AND !EMPTY(lcCursor) AND USED(lcCursor)
				USE IN (lcCursor)
			ENDIF
			SET DATASESSION TO (lnDs)
		ENDTRY
		RETURN This.cLastCursor
	ENDPROC

	*-- El array (con sus corchetes) de la clave tcKey del objeto de arriba
	*-- de tcText, o "" si no está o no es un array. Recorre el texto contando
	*-- llaves y corchetes fuera de las cadenas: un «"rows": [» dentro de un valor o
	*-- de un objeto de dentro no cuenta.
	PROCEDURE TopArray
		LPARAMETERS tcText, tcKey
		LOCAL lnI, lnLen, lcC, lnDepth, llIn, lnStart, lcKey, lnJ, lnK
		lnLen = LEN(tcText)
		lnDepth = 0
		llIn = .F.
		lnStart = 0
		lcKey = ["] + tcKey + ["]
		FOR lnI = 1 TO lnLen
			lcC = SUBSTR(tcText, lnI, 1)
			DO CASE
				CASE llIn
					DO CASE
						CASE lcC == "\"
							lnI = lnI + 1
						CASE lcC == ["]
							llIn = .F.
					ENDCASE
				CASE lcC == ["]
					*-- Una clave del objeto de arriba, seguida de : y de [.
					IF lnDepth = 1 AND lnStart = 0 AND SUBSTR(tcText, lnI, LEN(lcKey)) == lcKey
						lnJ = lnI + LEN(lcKey)
						lnJ = lnJ + LEN(SUBSTR(tcText, lnJ)) - LEN(LTRIM(SUBSTR(tcText, lnJ), 1, " ", CHR(9), CHR(13), CHR(10)))
						IF SUBSTR(tcText, lnJ, 1) == ":"
							lnK = lnJ + 1
							lnK = lnK + LEN(SUBSTR(tcText, lnK)) - LEN(LTRIM(SUBSTR(tcText, lnK), 1, " ", CHR(9), CHR(13), CHR(10)))
							IF SUBSTR(tcText, lnK, 1) == "["
								lnStart = lnK
								lnI = lnK - 1
								LOOP
							ENDIF
						ENDIF
					ENDIF
					llIn = .T.
				CASE INLIST(lcC, "{", "[")
					lnDepth = lnDepth + 1
				CASE INLIST(lcC, "}", "]")
					lnDepth = lnDepth - 1
					IF lnStart > 0 AND lnDepth = 1
						RETURN SUBSTR(tcText, lnStart, lnI - lnStart + 1)
					ENDIF
			ENDCASE
		ENDFOR
		RETURN ""
	ENDPROC

	*-- Un cursor vacío (sesión de datos 1) con las columnas del esquema
	*-- de Export... (name, type, width, decimals, nullable, como
	*-- ide_data_db_describe). .T. si lo hizo, o el motivo en cLastError. Los
	*-- anchos se acotan a lo que VFP admite (C(255) da el error 1713, vfpdocs).
	PROTECTED PROCEDURE SchemaCursor
		LPARAMETERS tcColumns, tcCursor
		LOCAL loP, loJ, lcTmp, lcFields, lcName, lcType, lnW, lnD, llNull, loErr, llOk
		llOk = .F.
		lcTmp = "FDS" + SYS(2015)
		loP = This.Plugin()
		loJ = loP.JsonFox()
		loJ.JSONToCursor(tcColumns, lcTmp, 1)
		IF loJ.lError OR !USED(lcTmp)
			This.cLastError = "the columns could not be read: " + IIF(loJ.lError, loJ.cLastError, "JSONFox made no cursor from them.")
			RETURN .F.
		ENDIF
		lcFields = ""
		SELECT (lcTmp)
		SCAN
			lcName = ALLTRIM(TRANSFORM(EVALUATE(lcTmp + ".name")))
			lcType = UPPER(LEFT(ALLTRIM(TRANSFORM(EVALUATE(lcTmp + ".type"))), 1))
			lnW = IIF(TYPE(lcTmp + ".width") == "N", INT(EVALUATE(lcTmp + ".width")), 0)
			lnD = IIF(TYPE(lcTmp + ".decimals") == "N", INT(EVALUATE(lcTmp + ".decimals")), 0)
			llNull = TYPE(lcTmp + ".nullable") == "L" AND EVALUATE(lcTmp + ".nullable")
			IF !This.IsName(lcName) OR !(lcType $ "CVQNFBIYDTLMWG")
				This.cLastError = "the column [" + lcName + "] of type [" + lcType + "] cannot go in a VFP cursor."
				USE IN (lcTmp)
				RETURN .F.
			ENDIF
			DO CASE
				CASE lcType $ "CVQ"
					lcType = lcType + "(" + TRANSFORM(MIN(MAX(lnW, 1), 254)) + ")"
				CASE lcType $ "NF"
					lnW = MIN(MAX(lnW, 1), 20)
					lcType = lcType + "(" + TRANSFORM(lnW) + "," + TRANSFORM(MIN(MAX(lnD, 0), MAX(lnW - 2, 0))) + ")"
				CASE lcType == "B"
					lcType = "B(" + TRANSFORM(MIN(MAX(lnD, 0), 18)) + ")"
			ENDCASE
			lcFields = lcFields + IIF(EMPTY(lcFields), "", ", ") + lcName + " " + lcType + IIF(llNull, " NULL", " NOT NULL")
		ENDSCAN
		USE IN (lcTmp)
		IF EMPTY(lcFields)
			This.cLastError = "the schema has no columns."
			RETURN .F.
		ENDIF
		TRY
			CREATE CURSOR (tcCursor) (&lcFields)
			llOk = .T.
		CATCH TO loErr
			This.cLastError = "the columns could not make a cursor: " + loErr.Message
		ENDTRY
		RETURN llOk
	ENDPROC

	PROCEDURE IsName
		LPARAMETERS tcName
		RETURN LEN(tcName) <= 128 AND (ISALPHA(tcName) OR LEFT(tcName, 1) == "_") AND ;
			LEN(CHRTRAN(UPPER(tcName), "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", "")) = 0
	ENDPROC

	*-- Lo que devuelve ide_data_to_json, o "" con el motivo en cLastError.
	PROCEDURE ToolJson
		LPARAMETERS tcTable, tnMax
		LOCAL loT, loR, loJ, loD, loSk, lcMeta, lcOut, lnI, loErr
		LOCAL ARRAY laSk[1]
		This.cLastError = ""
		lcOut = ""
		loT = CREATEOBJECT("DataTable")
		TRY
			IF loT.Open(tcTable, .F.)
				loR = This.Walk(loT, tnMax, "", 0)
				loJ = This.oHost.oJson
				loD = loJ.MakeObject()
				loJ.Put(loD, "table", loT.cName)
				loJ.Put(loD, "source", loT.cSource)
				loJ.Put(loD, "rowCount", loR.nRows)
				loJ.Put(loD, "returned", loR.nDone)
				loJ.Put(loD, "truncated", loR.lTruncated)
				loSk = loJ.MakeArray()
				FOR lnI = 1 TO ALINES(laSk, loT.cSkipped, 1 + 4, ",")
					loSk.Add(laSk[lnI])
				ENDFOR
				loJ.Put(loD, "skipped", loSk)
				lcMeta = loJ.Stringify(loD)
				lcOut = LEFT(lcMeta, LEN(lcMeta) - 1) + [,"rows":[] + STRTRAN(loR.cClip, "," + CRLF, ",") + "]}"
			ELSE
				This.cLastError = loT.cError
			ENDIF
		CATCH TO loErr
			This.cLastError = "Reading the table failed: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
			lcOut = ""
		FINALLY
			loT.Close()
		ENDTRY
		RETURN lcOut
	ENDPROC
ENDDEFINE
