*==================================================================
* DataPlugin.prg: el paquete «data» de FoxDock.
*
* Sigue el molde de «editor» (EditorPlugin.prg): un módulo
* por .prg con el prefijo del paquete, que se apaga en config.json y apagado
* no existe, ni sus barras ni sus tools:
*   "options": { "data": { "json": { "enabled": false } } }
*
* Los módulos (ModuleList):
*   json     Table to JSON, JSON to cursor; tools ide_data_to_json y ide_data_from_json
*   script   Script table as > (CREATE TABLE, INSERT, UPDATE), Dialect >; tool ide_data_script
*   connections  Connections > (una barra por conexión con Connect..., Disconnect, Explore... y
*            Query...; Edit connections..., Reload), por
*            FoxRemote (lib\foxremote\, que el plugin pide con requires); tools ide_data_db_connections,
*            ide_data_db_tables, ide_data_db_describe e ide_data_db_query
*   ai       AI > (DataAi.prg): AIXL, si está instalado, sin copiar nada de él.
*            Las cinco operaciones, el submenú del proveedor y Last run, o una
*            sola barra que dice qué falta; tools ide_data_ai_*
*
* EL MENÚ LO RELLENA EL PAQUETE (FillWith), no AddBar: «Script table as» y
* «Dialect» son submenús dentro del submenú Data, y el menú del host tiene
* tres niveles y no más (FoxDockMenu.prg). Cada módulo pone sus barras en su
* FillMenu(cPopup, nBar). Cada barra llama a FoxDock.APP por su ruta, como
* las del host: DO "<app>" WITH "bar", "data", "<acción>" [, "<parámetro>"].
*
* LA TABLA DE TRABAJO (DataTable, abajo): el ALIAS() de la sesión de datos 1;
* si no hay ninguno, desde una barra, GETFILE("DBF") (lo abre quien pulsa);
* desde una tool sin alias y sin «table», un error que lo dice. Un .dbf que se
* abre para esto va SHARED NOUPDATE en un área nueva y se cierra al terminar:
* nunca se escribe en una tabla del usuario. El puntero, SET DELETED, SET
* POINT y el área seleccionada quedan como estaban.
*
* Los ficheros salen a %LOCALAPPDATA%\FoxDock\data\ (OutDir), se sobrescriben
* sin preguntar (es la carpeta de FoxDock), y la barra de estado y el log dicen
* la ruta. LAS CODIFICACIONES: lo que el usuario retoca en el
* editor de VFP va en CP1252 y se abre ahí (oHost.Editor.Open); lo que va en
* UTF-8 (el .json, y el .sql con options.data.script.utf8) NO se abre en el
* editor de VFP, que lo guardaría mezclado: se abre con la aplicación que
* Windows tenga para ese tipo (OpenWithWindows).
*==================================================================

#DEFINE CRLF CHR(13) + CHR(10)

DEFINE CLASS DataPlugin AS PluginBase
	cId = "data"
	cTitle = "Data"
	nOrder = 920
	cVersion = "0.10.0"
	lWantsIdle = .T.
	oModules = .NULL.
	*-- .F.: OpenWithWindows no llama a ShellExecute (para las pruebas:
	*-- FOXDOCK_SHELL_OPEN=off). El log dice lo mismo, con la nota.
	lShellOpen = .T.

	PROCEDURE Init
		LPARAMETERS toHost
		DODEFAULT(toHost)
		This.lShellOpen = !(LOWER(GETENV("FOXDOCK_SHELL_OPEN")) == "off")
	ENDPROC

	*-- Los módulos del paquete, uno por línea: id, clase y .prg.
	PROCEDURE ModuleList
		RETURN "json,DataJson,DataJson.prg" + CRLF + "script,DataScript,DataScript.prg" + CRLF + ;
			"connections,DataConnections,DataConnections.prg" + CRLF + "ai,DataAi,DataAi.prg"
	ENDPROC

	*-- Los módulos encendidos (una Collection por id), como en EditorPlugin.
	PROCEDURE Modules
		LOCAL lnI
		LOCAL ARRAY laM[1], laP[1]
		IF ISNULL(This.oModules)
			This.oModules = CREATEOBJECT("Collection")
			FOR lnI = 1 TO ALINES(laM, This.ModuleList(), 1 + 4)
				IF ALINES(laP, laM[lnI], 1, ",") = 3
					This.LoadModule(LOWER(laP[1]), laP[2], laP[3])
				ENDIF
			ENDFOR
		ENDIF
		RETURN This.oModules
	ENDPROC

	PROCEDURE Module
		LPARAMETERS tcId
		LOCAL loMods
		loMods = This.Modules()
		IF loMods.GetKey(LOWER(tcId)) > 0
			RETURN loMods.Item(LOWER(tcId))
		ENDIF
		RETURN .NULL.
	ENDPROC

	PROTECTED PROCEDURE LoadModule
		LPARAMETERS tcId, tcClass, tcPrg
		LOCAL loM, loErr
		IF !This.oHost.Options.Get(This.cId, tcId + ".enabled", .T.)
			This.oHost.Log(This.cId + ": module " + tcId + " is off in config.json (options." + This.cId + "." + ;
				tcId + ".enabled): its bars and tools are not there")
			RETURN
		ENDIF
		TRY
			SET PROCEDURE TO (This.CodeFile(tcPrg)) ADDITIVE
			loM = CREATEOBJECT(tcClass, This.oHost)
			This.oModules.Add(loM, tcId)
			This.oHost.Log(This.cId + ": module " + tcId + " loaded")
		CATCH TO loErr
			This.oHost.LogFault(This.cId + ": module " + tcId + " failed to load: " + TRANSFORM(loErr.ErrorNo) + ;
				" " + loErr.Message)
		ENDTRY
	ENDPROC

	*-- Con algún módulo encendido, el submenú es del paquete (FillWith).
	PROCEDURE BuildMenu
		LPARAMETERS toMenu
		LOCAL loMods, loM
		*-- El título y los textos del paquete, en el idioma de
		*-- FoxDock (DataStrings.prg). Lo que viene de la lógica que comparten las
		*-- ventanas y las tools ide_data_* (cLastError, cError) sigue en inglés.
		This.cTitle = This.oHost.Translate("data.title")
		loMods = This.Modules()
		IF loMods.Count > 0
			toMenu.FillWith("FillMenu")
		ENDIF
		*-- El host vuelve a llamar a BuildMenu al cambiar de idioma, y
		*-- las ventanas abiertas vuelven a poner sus textos.
		FOR EACH loM IN loMods
			IF PEMSTATUS(loM, "Retext", 5)
				loM.Retext()
			ENDIF
		ENDFOR
	ENDPROC

	PROCEDURE FillMenu
		LPARAMETERS tcPopup
		LOCAL loMods, loM, lnBar
		lnBar = 0
		loMods = This.Modules()
		FOR EACH loM IN loMods
			lnBar = loM.FillMenu(tcPopup, lnBar)
		ENDFOR
	ENDPROC

	*-- Una barra del submenú que llama al .APP; tcParam, el parámetro de la
	*-- acción («insert», «mysql»). Acción vacía: separador.
	*-- tlDisabled: la barra no se puede pulsar (SET SKIP OF, porque con SKIP FOR
	*-- SKPBAR no lo ve). El menú se rehace cuando cambia lo que la habilita.
	PROCEDURE DefineBar
		LPARAMETERS tcPopup, tnBar, tcCaption, tcAction, tcParam, tcMessage, tlDisabled
		LOCAL lcCmd
		IF EMPTY(tcAction)
			lcCmd = "DEFINE BAR " + TRANSFORM(tnBar) + " OF " + tcPopup + " PROMPT [\-]"
			&lcCmd
			RETURN tnBar
		ENDIF
		lcCmd = "DEFINE BAR " + TRANSFORM(tnBar) + " OF " + tcPopup + " PROMPT [" + tcCaption + "]" + ;
			IIF(EMPTY(tcMessage), "", " MESSAGE [" + CHRTRAN(tcMessage, "[]", "()") + "]")
		&lcCmd
		IF tlDisabled
			lcCmd = "SET SKIP OF BAR " + TRANSFORM(tnBar) + " OF " + tcPopup + " .T."
			&lcCmd
		ENDIF
		lcCmd = [ON SELECTION BAR ] + TRANSFORM(tnBar) + [ OF ] + tcPopup + [ DO "] + This.oHost.cAppPath + ;
			[" WITH "bar", "] + This.cId + [", "] + tcAction + ["] + IIF(EMPTY(tcParam), "", [, "] + tcParam + ["])
		&lcCmd
		This.oHost.oMenu.Remember(lcCmd)
		RETURN tnBar
	ENDPROC

	*-- Una barra que abre un submenú nuevo, tcSub, dentro de tcPopup.
	PROCEDURE DefineSubmenu
		LPARAMETERS tcPopup, tnBar, tcCaption, tcSub
		LOCAL lcCmd
		lcCmd = "DEFINE BAR " + TRANSFORM(tnBar) + " OF " + tcPopup + " PROMPT [" + tcCaption + "]"
		&lcCmd
		lcCmd = "ON BAR " + TRANSFORM(tnBar) + " OF " + tcPopup + " ACTIVATE POPUP " + tcSub
		&lcCmd
		This.oHost.oMenu.Remember(lcCmd)
		lcCmd = "DEFINE POPUP " + tcSub + " MARGIN RELATIVE"
		&lcCmd
		RETURN tnBar
	ENDPROC

	PROCEDURE GetAgentTools
		LPARAMETERS toTools
		LOCAL loMods, loM, lnN
		IF !("\IDETOOLS." $ UPPER(SET("PROCEDURE")))
			RETURN 0
		ENDIF
		This.EnsureProcedures()
		lnN = 0
		loMods = This.Modules()
		FOR EACH loM IN loMods
			lnN = lnN + loM.GetAgentTools(toTools)
		ENDFOR
		RETURN lnN
	ENDPROC

	*-- Las clases de las tools tienen que seguir visibles: el Bridge crea una
	*-- por llamada, por su nombre (y CLOSE ALL vacía SET PROCEDURE).
	PROCEDURE OnIdle
		This.EnsureProcedures()
	ENDPROC

	PROCEDURE EnsureProcedures
		LOCAL lcTools, loErr, loAi
		*-- El aixl.prg del AIXL instalado, una vez usado, también (CLOSE ALL lo quita).
		loAi = This.Module("ai")
		IF !ISNULL(loAi) AND loAi.lEnsured
			loAi.EnsureProcedure()
		ENDIF
		lcTools = This.CodeFile("DataTools.prg")
		IF !EMPTY(This.cHome) AND !("\DATATOOLS." $ UPPER(SET("PROCEDURE"))) AND ;
				"\IDETOOLS." $ UPPER(SET("PROCEDURE")) AND FILE(lcTools)
			TRY
				SET PROCEDURE TO (lcTools) ADDITIVE
			CATCH TO loErr
				This.oHost.LogWarn("data: " + lcTools + " not loaded: " + loErr.Message)
			ENDTRY
		ENDIF
	ENDPROC

	*-- La carpeta de los ficheros del paquete: %LOCALAPPDATA%\FoxDock\data\.
	PROCEDURE OutDir
		LOCAL lcDir
		lcDir = This.oHost.DataDir + "data\"
		IF !DIRECTORY(lcDir, 1)
			MKDIR (lcDir)
		ENDIF
		RETURN lcDir
	ENDPROC

	*-- Un fichero en UTF-8, con la aplicación que Windows tiene para su tipo
	*-- (ShellExecute «open»), nunca en el editor de VFP, que lo guardaría
	*-- mezclado. Sin aplicación asociada, la ruta en la barra de estado y el log.
	*-- Devuelve si se abrió.
	PROCEDURE OpenWithWindows
		LPARAMETERS tcFile
		LOCAL lnRc
		IF !This.lShellOpen
			This.oHost.Log("data: " + tcFile + " opened with Windows (not really: FOXDOCK_SHELL_OPEN is off, as in the tests)")
			RETURN .T.
		ENDIF
		DECLARE INTEGER ShellExecute IN shell32 AS FdDataShellExecute INTEGER hWnd, STRING cOperation, STRING cFile, ;
			STRING cParameters, STRING cDirectory, INTEGER nShowCmd
		lnRc = FdDataShellExecute(_screen.HWnd, "open", tcFile, "", JUSTPATH(tcFile), 1)
		IF lnRc > 32
			This.oHost.Log("data: " + tcFile + " opened with Windows")
			RETURN .T.
		ENDIF
		This.oHost.LogWarn("data: " + tcFile + " was not opened: " + ;
			IIF(lnRc = 31, "Windows has no application for ." + LOWER(JUSTEXT(tcFile)) + " files", ;
			"ShellExecute answered " + TRANSFORM(lnRc)) + "; it is in " + JUSTPATH(tcFile))
		RETURN .F.
	ENDPROC

	*-- JSONFox, el del .APP (FoxDockJsonFox.prg): por NEWOBJECT con la ruta
	*-- del .APP; con los fuentes sueltos (FoxDockMain.prg), el .prg de al lado.
	PROCEDURE JsonFox
		LOCAL lcApp
		lcApp = This.oHost.cAppPath
		IF UPPER(JUSTEXT(lcApp)) == "APP"
			RETURN NEWOBJECT("JSONFox", "FoxDockJsonFox.prg", lcApp)
		ENDIF
		RETURN NEWOBJECT("JSONFox", ADDBS(JUSTPATH(lcApp)) + "FoxDockJsonFox.prg")
	ENDPROC

	*-- Las acciones de las barras. Con el módulo apagado no hay barra que las
	*-- llame; si llega una (una barra vieja), se dice y no pasa nada.
	PROCEDURE TableToJson
		LOCAL loM
		loM = This.Module("json")
		RETURN IIF(ISNULL(loM), This.Off("json"), loM.TableToJson())
	ENDPROC

	PROCEDURE JsonToCursor
		LOCAL loM
		loM = This.Module("json")
		RETURN IIF(ISNULL(loM), This.Off("json"), loM.JsonToCursor())
	ENDPROC

	PROCEDURE ScriptAs
		LPARAMETERS tcKind
		LOCAL loM
		loM = This.Module("script")
		RETURN IIF(ISNULL(loM), This.Off("script"), loM.ScriptAs(tcKind))
	ENDPROC

	PROCEDURE SetDialect
		LPARAMETERS tcDialect
		LOCAL loM
		loM = This.Module("script")
		RETURN IIF(ISNULL(loM), This.Off("script"), loM.SetDialect(tcDialect))
	ENDPROC

	*-- Connections: el parámetro es el id de la conexión.
	PROCEDURE DbConnect
		LPARAMETERS tcConn
		LOCAL loM
		loM = This.Module("connections")
		RETURN IIF(ISNULL(loM), This.Off("connections"), loM.ConnectBar(tcConn))
	ENDPROC

	PROCEDURE DbDisconnect
		LPARAMETERS tcConn
		LOCAL loM
		loM = This.Module("connections")
		RETURN IIF(ISNULL(loM), This.Off("connections"), loM.DisconnectBar(tcConn))
	ENDPROC

	*-- Explore...: la ventana de la conexión, con sus tablas.
	PROCEDURE DbExplore
		LPARAMETERS tcConn
		LOCAL loM
		loM = This.Module("connections")
		RETURN IIF(ISNULL(loM), This.Off("connections"), !ISNULL(loM.ExploreBar(tcConn)))
	ENDPROC

	PROCEDURE DbQuery
		LPARAMETERS tcConn
		LOCAL loM
		loM = This.Module("connections")
		RETURN IIF(ISNULL(loM), This.Off("connections"), loM.QueryBar(tcConn))
	ENDPROC

	PROCEDURE DbEdit
		LOCAL loM
		loM = This.Module("connections")
		RETURN IIF(ISNULL(loM), This.Off("connections"), loM.EditBar())
	ENDPROC

	PROCEDURE DbReload
		LOCAL loM
		loM = This.Module("connections")
		RETURN IIF(ISNULL(loM), This.Off("connections"), loM.ReloadBar())
	ENDPROC

	*-- AI: Manage providers... y una barra por proveedor del submenú (AiUse).
	*-- AiHelp, la barra apagada (lo que falta y la ficha de AIXL); AiStatus, la
	*-- acción de las barras deshabilitadas (Last run).
	PROCEDURE AiProviders
		LOCAL loM
		loM = This.Module("ai")
		RETURN IIF(ISNULL(loM), This.Off("ai"), !ISNULL(loM.OpenProviders()))
	ENDPROC

	PROCEDURE AiUse
		LPARAMETERS tcId
		LOCAL loM
		loM = This.Module("ai")
		RETURN IIF(ISNULL(loM), This.Off("ai"), EMPTY(loM.UseProvider(tcId)))
	ENDPROC

	PROCEDURE AiHelp
		LOCAL loM
		loM = This.Module("ai")
		RETURN IIF(ISNULL(loM), This.Off("ai"), loM.Help())
	ENDPROC

	*-- Classify column...
	PROCEDURE AiClassify
		LOCAL loM
		loM = This.Module("ai")
		RETURN IIF(ISNULL(loM), This.Off("ai"), !ISNULL(loM.OpenClassify()))
	ENDPROC

	*-- Las cinco operaciones por su nombre (classify, extract, anonymize, filter, ask).
	PROCEDURE AiOp
		LPARAMETERS tcKind
		LOCAL loM
		loM = This.Module("ai")
		RETURN IIF(ISNULL(loM), This.Off("ai"), !ISNULL(loM.OpenOp(tcKind)))
	ENDPROC

	PROCEDURE AiStatus
		LOCAL loM
		loM = This.Module("ai")
		RETURN IIF(ISNULL(loM), This.Off("ai"), .T.)
	ENDPROC

	*-- Las conexiones del proyecto van con el proyecto abierto: al abrir o
	*-- cerrar uno, se vuelven a leer y el menú se rehace.
	PROCEDURE OnProjectOpen
		LPARAMETERS toProject
		This.ProjectChanged("")
	ENDPROC

	PROCEDURE OnProjectClose
		LPARAMETERS tcProjectName
		This.ProjectChanged(TRANSFORM(tcProjectName))
	ENDPROC

	PROTECTED PROCEDURE ProjectChanged
		LPARAMETERS tcClosing
		LOCAL loM
		loM = This.Module("connections")
		IF !ISNULL(loM)
			loM.cClosing = tcClosing
			loM.Load()
			loM.cClosing = ""
			This.oHost.RefreshMenu()
		ENDIF
	ENDPROC

	*-- Al desmontar o cerrar el IDE: las conexiones se cierran y los
	*-- formularios se sueltan.
	PROCEDURE OnShutdown
		LOCAL loM
		loM = This.Module("connections")
		IF !ISNULL(loM)
			loM.CloseAll()
		ENDIF
		loM = This.Module("ai")
		IF !ISNULL(loM)
			loM.CloseAll()
		ENDIF
	ENDPROC

	PROTECTED PROCEDURE Off
		LPARAMETERS tcId
		This.oHost.LogWarn(This.cId + ": module " + tcId + " is off or did not load")
		RETURN .F.
	ENDPROC
ENDDEFINE


*------------------------------------------------------------------
* La tabla de trabajo de una barra o de una tool, en la sesión de datos 1.
*
*   loT = CREATEOBJECT("DataTable")
*   IF loT.Open(cTable, lAsk)     && cTable: un alias de la sesión 1, un .dbf o ""
*       ... loT.cAlias, loT.cName, loT.nCols, loT.aCols[n, 6], loT.cSkipped ...
*   ENDIF
*   loT.Close()                   && SIEMPRE (en un FINALLY): deja todo como estaba
*
* aCols, una fila por columna que se exporta (todas menos las General):
*   1 nombre en minúsculas, 2 tipo, 3 ancho, 4 decimales, 5 admite NULL,
*   6 NOCPTRANS.
* Lo que VFP traduce solo: un campo de una tabla marcada con otra
* página de códigos llega en CPCURRENT() al leerlo; un campo NOCPTRANS llega
* con los bytes del disco, y esos son de CPDBF(): Text() lo pasa a CPCURRENT().
*------------------------------------------------------------------
DEFINE CLASS DataTable AS Custom
	cAlias = ""       && el área en la sesión de datos 1
	cName = ""        && el nombre para los ficheros y los scripts (minúsculas)
	cSource = ""      && el alias o el .dbf que se pidió
	lOpened = .F.     && .T. si el .dbf lo abrió esta clase
	cError = ""       && por qué Open devolvió .F. ("" si la persona canceló el GETFILE)
	nCols = 0
	cSkipped = ""     && las General, separadas por comas
	cFieldList = ""   && las columnas que se exportan, para SCATTER
	nCpDbf = 0
	nDs = 0
	nSelect = 0
	nRecno = 0
	lEof = .F.
	cDeleted = ""
	cPoint = ""
	lOpen = .F.       && Open llegó a cambiar algo (Close tiene que reponerlo)
	DIMENSION aCols[1, 6]

	PROCEDURE Open
		LPARAMETERS tcTable, tlAsk
		LOCAL lcFile, lcAlias, loErr, lnN, lnI, lcPoint
		LOCAL ARRAY laF[1]
		tcTable = ALLTRIM(IIF(VARTYPE(tcTable) == "C", tcTable, ""))
		This.nDs = SET("DATASESSION")
		SET DATASESSION TO 1
		This.lOpen = .T.
		This.nSelect = SELECT(0)
		This.cDeleted = SET("DELETED")
		This.cPoint = SET("POINT")
		lcFile = ""
		lcAlias = ""
		DO CASE
			CASE !EMPTY(tcTable) AND !("\" $ tcTable) AND !("." $ tcTable) AND USED(tcTable)
				lcAlias = UPPER(tcTable)
			CASE !EMPTY(tcTable)
				lcFile = IIF(EMPTY(JUSTEXT(tcTable)), FORCEEXT(tcTable, "dbf"), tcTable)
				IF !FILE(lcFile)
					This.cError = "There is no table or cursor '" + tcTable + "': it is not an alias open in data " + ;
						"session 1 of the IDE, and there is no file " + FULLPATH(lcFile) + "."
					RETURN .F.
				ENDIF
			CASE !EMPTY(ALIAS())
				lcAlias = ALIAS()
			CASE tlAsk
				lcFile = GETFILE("DBF", "Table:", "Open", 0, "FoxDock: the table to work with")
				IF EMPTY(lcFile)
					RETURN .F.
				ENDIF
			OTHERWISE
				This.cError = "No table or cursor is selected in data session 1 of the IDE, and 'table' was not given: " + ;
					"pass the alias of an open table or cursor, or the path of a .dbf."
				RETURN .F.
		ENDCASE
		IF !EMPTY(lcFile)
			lcAlias = "FDD" + SYS(2015)
			TRY
				USE (lcFile) AGAIN SHARED NOUPDATE IN 0 ALIAS (lcAlias)
				This.lOpened = .T.
			CATCH TO loErr
				This.cError = FULLPATH(lcFile) + " could not be opened (" + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message + ;
					"). If it is open exclusively somewhere else, close it there, or open it in this IDE and pass its alias."
			ENDTRY
			IF !This.lOpened
				RETURN .F.
			ENDIF
			This.cName = LOWER(JUSTSTEM(lcFile))
			This.cSource = FULLPATH(lcFile)
		ELSE
			This.cName = LOWER(lcAlias)
			This.cSource = lcAlias
		ENDIF
		This.cAlias = lcAlias
		SELECT (lcAlias)
		This.lEof = EOF()
		This.nRecno = RECNO()
		This.nCpDbf = CPDBF(lcAlias)
		*-- Los Double (Num): _snprintf y strtod de msvcrt. Se declaran en
		*-- cada Open: un CLEAR DLLS del usuario se los lleva.
		DECLARE INTEGER _snprintf IN msvcrt AS FdDataSnprintf STRING @cBuf, INTEGER nCount, STRING cFmt, DOUBLE nValue
		DECLARE DOUBLE strtod IN msvcrt AS FdDataStrtod STRING cText, INTEGER nEnd
		SET DELETED ON
		SET POINT TO "."
		lnN = AFIELDS(laF, lcAlias)
		This.nCols = 0
		This.cSkipped = ""
		This.cFieldList = ""
		FOR lnI = 1 TO lnN
			IF laF[lnI, 2] == "G"
				This.cSkipped = This.cSkipped + IIF(EMPTY(This.cSkipped), "", ",") + LOWER(laF[lnI, 1])
				LOOP
			ENDIF
			This.nCols = This.nCols + 1
			DIMENSION This.aCols[This.nCols, 6]
			This.aCols[This.nCols, 1] = LOWER(laF[lnI, 1])
			This.aCols[This.nCols, 2] = laF[lnI, 2]
			This.aCols[This.nCols, 3] = laF[lnI, 3]
			This.aCols[This.nCols, 4] = laF[lnI, 4]
			This.aCols[This.nCols, 5] = laF[lnI, 5]
			This.aCols[This.nCols, 6] = laF[lnI, 6]
			This.cFieldList = This.cFieldList + IIF(EMPTY(This.cFieldList), "", ",") + laF[lnI, 1]
		ENDFOR
		IF This.nCols = 0
			This.cError = This.cName + " has no field that can be exported (only General fields)."
			RETURN .F.
		ENDIF
		RETURN .T.
	ENDPROC

	*-- Deja la sesión 1 como estaba: el puntero, el área, SET DELETED, SET
	*-- POINT; y cierra el .dbf si lo abrió Open.
	PROCEDURE Close
		LOCAL lcDeleted, lcPoint, loErr
		IF !This.lOpen
			RETURN
		ENDIF
		This.lOpen = .F.
		TRY
			DO CASE
				CASE EMPTY(This.cAlias) OR !USED(This.cAlias)
				CASE This.lOpened
					USE IN (This.cAlias)
				CASE This.lEof
					GO BOTTOM IN (This.cAlias)
					IF !EOF(This.cAlias)
						SKIP 1 IN (This.cAlias)
					ENDIF
				CASE This.nRecno <= RECCOUNT(This.cAlias)
					GO (This.nRecno) IN (This.cAlias)
			ENDCASE
		CATCH TO loErr
		ENDTRY
		lcDeleted = This.cDeleted
		IF !EMPTY(lcDeleted)
			SET DELETED &lcDeleted
		ENDIF
		lcPoint = This.cPoint
		IF !EMPTY(lcPoint)
			SET POINT TO (lcPoint)
		ENDIF
		TRY
			SELECT (This.nSelect)
		CATCH TO loErr
		ENDTRY
		SET DATASESSION TO (This.nDs)
	ENDPROC

	*-- Las filas que se exportan: las no borradas, con el filtro y el orden
	*-- que tenga el área (el puntero vuelve a su sitio en Close).
	PROCEDURE RowCount
		LOCAL lnN
		SELECT (This.cAlias)
		COUNT TO lnN
		RETURN lnN
	ENDPROC

	*-- Un valor de texto (C, V, M) de la columna tnCol en CPCURRENT() y sin
	*-- los espacios de relleno del final.
	PROCEDURE Text
		LPARAMETERS tnCol, tcValue
		IF This.aCols[tnCol, 6] AND This.nCpDbf > 0 AND This.nCpDbf # CPCURRENT()
			tcValue = CPCONVERT(This.nCpDbf, CPCURRENT(), tcValue)
		ENDIF
		RETURN RTRIM(tcValue)
	ENDPROC

	*-- Un número de la columna tnCol con el punto decimal: N y F con los
	*-- decimales de la columna (es lo que guardan), I sin ninguno, Y con cuatro,
	*-- y B con su valor guardado (DoubleText, abajo).
	PROCEDURE Num
		LPARAMETERS tnCol, tnValue
		DO CASE
			CASE This.aCols[tnCol, 2] == "I"
				RETURN ALLTRIM(STR(tnValue, 12, 0))
			CASE This.aCols[tnCol, 2] == "Y"
				RETURN ALLTRIM(STR(MTON(tnValue), 25, 4))
			CASE This.aCols[tnCol, 2] == "B"
				RETURN This.DoubleText(tnValue)
		ENDCASE
		RETURN ALLTRIM(STR(tnValue, 25, This.aCols[tnCol, 4]))
	ENDPROC

	*-- Un Double con su valor guardado, no con los decimales del campo (un B(2)
	*-- con 1/3 no es 0.33): la representación decimal más corta que vuelve al
	*-- MISMO Double. STR no pasa de 16 cifras y 0.1 + 0.2 pide 17, así que la
	*-- escribe _snprintf("%.15g"), y si strtod no la lee bit a bit, "%.16g" y
	*-- "%.17g": strtod es como la lee un motor SQL o un parser de JSON, y el
	*-- literal de VFP la lee igual en todos los valores probados. Con
	PROCEDURE DoubleText
		LPARAMETERS tnValue
		LOCAL lnP, lcS, lcRef
		lcRef = BINTOC(tnValue, "B")
		FOR lnP = 15 TO 17
			lcS = This.Digits(tnValue, lnP)
			IF BINTOC(FdDataStrtod(lcS, 0), "B") == lcRef
				EXIT
			ENDIF
		ENDFOR
		RETURN This.Plain(lcS)
	ENDPROC

	PROTECTED PROCEDURE Digits
		LPARAMETERS tnValue, tnDigits
		LOCAL lcBuf, lnLen
		lcBuf = REPLICATE(CHR(0), 64)
		lnLen = FdDataSnprintf(@lcBuf, 63, "%." + TRANSFORM(tnDigits) + "g", tnValue)
		RETURN LEFT(lcBuf, MAX(0, lnLen))
	ENDPROC

	*-- Sin exponente (msvcrt escribe 1e+015 y -1e-006): 1000000000000000 y
	*-- -0.000001. Un exponente de más de 20 se queda, sin sus ceros (1.5e300).
	PROTECTED PROCEDURE Plain
		LPARAMETERS tcS
		LOCAL lnE, lcMant, lnExp, lcSign, lcDigits, lnPoint
		lnE = AT("e", tcS)
		IF lnE = 0
			RETURN tcS
		ENDIF
		lcMant = LEFT(tcS, lnE - 1)
		lnExp = INT(VAL(SUBSTR(tcS, lnE + 1)))
		IF ABS(lnExp) > 20
			RETURN lcMant + "e" + TRANSFORM(lnExp)
		ENDIF
		lcSign = IIF(LEFT(lcMant, 1) == "-", "-", "")
		lcMant = CHRTRAN(lcMant, "-", "")
		lcDigits = CHRTRAN(lcMant, ".", "")
		lnPoint = IIF(AT(".", lcMant) = 0, LEN(lcMant), AT(".", lcMant) - 1) + lnExp
		DO CASE
			CASE lnPoint <= 0
				RETURN lcSign + "0." + REPLICATE("0", -lnPoint) + lcDigits
			CASE lnPoint >= LEN(lcDigits)
				RETURN lcSign + lcDigits + REPLICATE("0", lnPoint - LEN(lcDigits))
		ENDCASE
		RETURN lcSign + LEFT(lcDigits, lnPoint) + "." + SUBSTR(lcDigits, lnPoint + 1)
	ENDPROC

	*-- Una fecha en ISO 8601 (AAAA-MM-DD), o "" si está vacía.
	PROCEDURE IsoDate
		LPARAMETERS tdValue
		IF EMPTY(tdValue)
			RETURN ""
		ENDIF
		RETURN TRANSFORM(DTOS(tdValue), "@R 9999-99-99")
	ENDPROC

	*-- Una fecha y hora en ISO 8601 con la T (AAAA-MM-DDThh:mm:ss), o "".
	PROCEDURE IsoTime
		LPARAMETERS ttValue
		IF EMPTY(ttValue)
			RETURN ""
		ENDIF
		RETURN TTOC(ttValue, 3)
	ENDPROC

	*-- Lo que se escribe: "a.json (3 rows)" para la barra de estado y el log.
	PROCEDURE Rows
		LPARAMETERS tnRows
		RETURN TRANSFORM(tnRows) + IIF(tnRows = 1, " row", " rows")
	ENDPROC

	*-- Lo mismo, en el idioma de FoxDock (tlEn: en inglés, para el log).
	PROCEDURE RowsShown
		LPARAMETERS toHost, tnRows, tlEn
		IF tlEn
			RETURN toHost.TranslateEn(IIF(tnRows = 1, "data.rows.one", "data.rows.many"), tnRows)
		ENDIF
		RETURN toHost.Translate(IIF(tnRows = 1, "data.rows.one", "data.rows.many"), tnRows)
	ENDPROC
ENDDEFINE


*------------------------------------------------------------------
* Un fichero que se escribe a trozos (una tabla de 100.000 filas no cabe
* entera en una cadena con holgura). tcEncoding: "utf8", "utf8bom" o
* "ansi" (CPCURRENT()). El texto llega siempre en CPCURRENT(). Sin fichero
* (tcFile vacío) solo junta el texto en cBuffer: lo que va a una tool.
*------------------------------------------------------------------
DEFINE CLASS DataFile AS Custom
	cFile = ""
	cEncoding = ""
	cBuffer = ""
	lStarted = .F.

	PROCEDURE Init
		LPARAMETERS tcFile, tcEncoding
		This.cFile = tcFile
		This.cEncoding = tcEncoding
	ENDPROC

	PROCEDURE Write
		LPARAMETERS tcText
		This.cBuffer = This.cBuffer + tcText
		IF !EMPTY(This.cFile) AND LEN(This.cBuffer) > 1000000
			This.Flush()
		ENDIF
	ENDPROC

	*-- Con SET SAFETY ON, STRTOFILE sobre un fichero que existe pregunta
	*-- antes de escribir: se apaga para la primera escritura y se repone.
	PROCEDURE Flush
		LOCAL lcOut, lcSafety
		IF EMPTY(This.cFile)
			RETURN
		ENDIF
		lcOut = IIF(This.cEncoding == "ansi", This.cBuffer, STRCONV(This.cBuffer, 9, CPCURRENT(), 1))
		IF !This.lStarted
			IF This.cEncoding == "utf8bom"
				lcOut = CHR(0xEF) + CHR(0xBB) + CHR(0xBF) + lcOut
			ENDIF
			lcSafety = SET("SAFETY")
			SET SAFETY OFF
			STRTOFILE(lcOut, This.cFile, 0)
			SET SAFETY &lcSafety
			This.lStarted = .T.
		ELSE
			STRTOFILE(lcOut, This.cFile, 1)
		ENDIF
		This.cBuffer = ""
	ENDPROC
ENDDEFINE
