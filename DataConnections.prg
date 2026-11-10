*==================================================================
* DataConnections.prg: el módulo «connections» del paquete «data» de
* FoxDock: las conexiones a bases de datos de servidor, por FoxRemote.
*
*   Data > Connections >   una barra por conexión (las del proyecto primero,
*                          con «(project)»), y en cada una Connect...,
*                          Disconnect, Explore... y Query...; al final Edit
*                          connections... y Reload
*   tools                  ide_data_db_connections, ide_data_db_tables,
*                          ide_data_db_describe e ide_data_db_query (leen)
*
* LOS DOS FICHEROS (connections.json, un array JSON de conexiones planas):
*   <carpeta del proyecto abierto>\connections.json   compartible: va con el
*                                                      proyecto, sin secretos
*   %LOCALAPPDATA%\FoxDock\connections.json            las del usuario
* Se leen los dos y se funden: las del proyecto primero; con el mismo id, se
* queda la del proyecto y el log lo dice. Los campos: id, name, engine
* (sqlserver, mysql, mariadb, postgresql, firebird, sqlite), server, port,
* database, user, driver (vacío: el de la tabla de FoxRemote), windowsAuth,
* allowWrite (false si no está; deja escribir a ide_data_db_execute, con rol
* 10 o más) y agentCanRead (false si no está).
* Cada objeto del array es una conexión y una entrada del submenú Connections.
*
* «database» VACÍA: en SQL Server, MySQL, MariaDB y PostgreSQL es una
* conexión al servidor, sin base: queda en la que dé el servidor (SQL Server,
* la del login; PostgreSQL, «postgres», la que pone FoxRemote), y Explore...
* e ide_data_db_tables dicen cuál (CurrentDatabase). En SQL Server, otra base
* del mismo servidor se lee con nombre de tres partes (ventas.dbo.clientes):
* pasa la guarda. En SQLite y Firebird la base es el fichero y no puede faltar.
*
* EXPLORE... abre una ventana por conexión (DataExploreForm, abajo): la base
* actual y un combo con las del servidor (en SQLite y Firebird, el fichero y
* el combo deshabilitado), la lista de tablas y vistas con un filtro al
* teclear, y Columns y Browse de la elegida, cada una en un BROWSE de solo
* lectura (Browse con el límite de Query..., 0 = sin límite). Las bases y las
* vistas las da FoxRemote (GetDatabases y GetObjects). Elegir otra base es
* UseDatabase de FoxRemote, que vuelve a conectar: con contraseña, solo si
* está guardada. La ventana se cierra sola, con sus cursores, al cerrarse la
* conexión (Disconnect), al releer las conexiones (Reload) y al apagarse el
* módulo.
*
* EXPORT..., en la ventana: la tabla o vista elegida a un .dbf libre, un .json
* (el de Table to JSON) o un .csv (separador ; , o tabulador; CP1252 o UTF-8
* con BOM), todas las filas o las N primeras, con el total del servidor
* delante (SELECT COUNT(*)). Un fichero que existe no se pisa sin «Replace
* it»: lo dice la ventanita, no VFP (se escribe con SET SAFETY OFF y se
* repone). El .json y el .csv en UTF-8 se abren con la aplicación de
* Windows; el .csv en CP1252, en el editor de texto de VFP, que lo enseña
* sin diálogo y con la eñe bien (un UTF-8 saldría allí con el BOM y la eñe
* en dos letras); el .dbf no se abre (el aviso dice dónde está). Un fichero
* abierto en un editor no se escribe: STRTOFILE dejaría 0 bytes.
*
* CREATE VIEW...: una vista remota de VFP de la tabla o vista elegida en un
* .dbc (el abierto, uno de la carpeta del proyecto o uno nuevo), con las
* columnas marcadas, un WHERE opcional y, si la tabla tiene clave primaria,
* actualizable (SendUpdates, Tables, KeyField, Updatable y UpdateName).
* NUNCA UNA CONTRASEÑA EN EL .DBC: la conexión del .dbc guarda la cadena de
* la conexión viva sin PWD, con DispLogin 1 para que USE la pida en la
* ventana del driver; mientras se crea la vista, la contraseña va en un .dsn
* temporal que se borra al acabar. Los varchar van como V (MapVarchar): con
* el relleno, en SQLite fallaba el TABLEUPDATE. Los binarios, como Q y W
* (MapBinary), como en todo lo que se lee de una conexión. Con contraseña, la vista se
* abre con USE ... CONNSTRING; la ventanita enseña la línea.
*
* Query... lee como mucho las filas de su límite: 100 de entrada, 0 = sin
* límite, y lo recuerda en data.connections.queryLimit.
*
* NUNCA UNA CONTRASEÑA EN EL FICHERO. Un fichero que trae una clave password,
* pwd, passwd, secret o pass, o un valor con «pwd=» o «password=», no se lee
* entero, y el log lo dice sin el valor. La contraseña va aparte, cifrada con
* la cuenta de Windows (DPAPI) en %LOCALAPPDATA%\FoxDock\secrets\<id>.cred, y
* solo si se marca «Remember» en el formulario de Connect...; con
* windowsAuth, o sin user (SQLite), no hay contraseña. Lo que FoxRemote dice
* al fallar se limpia de la contraseña antes de ir al log, a la barra de
* estado o a una tool, y el objeto de FoxRemote no la guarda después de
* conectar.
*
* EL AGENTE LEE: ide_data_db_query admite una sola sentencia que empieza por
* SELECT o WITH (DataSqlGuard, abajo; FoxRemote no niega nada), con tope de
* filas. Y solo en las conexiones con agentCanRead: lo que lee el agente sale
* de la máquina hacia el proveedor de IA. Escribir es ide_data_db_execute, y
* solo en las conexiones con allowWrite (Execute, abajo). Una tool no
* pregunta nada: sin la contraseña guardada, contesta que hace falta
* Connect... en el IDE.
*
* FoxRemote es una librería que el plugin pide con requires: FoxPack la deja
* en lib\foxremote\. Sus clases se crean con NEWOBJECT desde su foxremote.prg
* de la caché del código (CodeFile), que nunca entra en SET PROCEDURE: así no
* tapa el foxremote.prg de un proyecto del usuario que tenga clases con los
* mismos nombres, y FoxDock puede actualizar el plugin estando abierto.
*==================================================================

#DEFINE CRLF CHR(13) + CHR(10)
#DEFINE DC_ENGINES "sqlserver,mysql,mariadb,postgresql,firebird,sqlite"
*-- Las claves de una conexión, en el orden de Template.
#DEFINE DC_KEYS "id,name,engine,server,port,database,user,driver,windowsAuth,allowWrite,agentCanRead"

DEFINE CLASS DataConnections AS Custom
	cId = "connections"
	oHost = .NULL.
	oList = .NULL.        && las conexiones (un Empty cada una), por id
	oLive = .NULL.        && los objetos de FoxRemote conectados, por id
	oForms = .NULL.       && los formularios abiertos (modeless), para soltarlos
	cProjectDir = ""      && si no está vacío, la carpeta del «proyecto» (los tests)
	cClosing = ""         && el proyecto que se está cerrando (OnProjectClose): ya no cuenta
	cLastError = ""
	lNeedsConnectBar = .F. && el último fallo fue que falta la contraseña
	nLastRows = 0
	lLastTruncated = .F.
	cLastShort = ""       && QueryWhole: «,columna:CAST,» de lo que no llegó entero (vacío si todo llegó)
	cLastShortWhy = ""    && por qué no se releyó: order_by o wrap_failed
	cLastShortEngine = "" && el motor de esa consulta, para escribir el CAST con sus comillas
	cLastQueryAlias = ""
	cLastTitle = ""       && el título del último BROWSE (lo leen los tests)
	cLastCursor = ""      && el cursor del último RunQuery que salió bien (Query... lo apunta)
	cLastCode = ""        && «not_connected» si el último fallo es que la conexión no está (las tools lo dan)
	cLastStatement = ""   && la palabra de la última escritura de Execute (INSERT, UPDATE...)
	nLastAffected = 0     && sus filas afectadas
	nLastMs = 0           && lo que tardó
	cWhy1 = ""            && los valores del último motivo de la ventana de conexiones
	cWhy2 = ""
	lClosing = .F.        && CloseAll está cerrando: no se rehace el menú en cada una

	PROCEDURE Init
		LPARAMETERS toHost
		This.oHost = toHost
		This.oLive = CREATEOBJECT("Collection")
		This.oForms = CREATEOBJECT("Collection")
		This.Load()
	ENDPROC

	PROCEDURE Destroy
		This.CloseAll()
	ENDPROC

	*-- Al apagar el paquete o desmontar FoxDock: se cierran las conexiones y
	*-- los formularios.
	PROCEDURE CloseAll
		LOCAL loF, loErr
		This.lClosing = .T.
		=This.CloseExplore("", "the connections module was turned off")
		IF VARTYPE(This.oForms) == "O"
			DO WHILE This.oForms.Count > 0
				loF = This.oForms.Item(1)
				This.oForms.Remove(1)
				TRY
					loF.oModule = .NULL.
					loF.Release()
				CATCH TO loErr
				ENDTRY
			ENDDO
		ENDIF
		IF VARTYPE(This.oLive) == "O"
			DO WHILE This.oLive.Count > 0
				This.Disconnect(This.oLive.GetKey(1))
			ENDDO
		ENDIF
	ENDPROC

	PROCEDURE Plugin
		RETURN This.oHost.PluginById("data")
	ENDPROC

	*-- La carpeta de los .prg del paquete, para NEWOBJECT: la del código de este
	*-- motor (CodeFile); sin el plugin, la de este fichero.
	PROCEDURE Home
		LOCAL loP
		loP = This.Plugin()
		RETURN IIF(ISNULL(loP), ADDBS(JUSTPATH(SYS(16))), loP.CodeFile(""))
	ENDPROC

	PROCEDURE FoxRemotePrg
		RETURN This.Home() + "lib\foxremote\foxremote.prg"
	ENDPROC

	PROCEDURE UserFile
		RETURN This.oHost.DataDir + "connections.json"
	ENDPROC

	*-- connections.json del proyecto abierto ("" si no hay ninguno): el
	*-- activo, o el primero abierto que no se esté cerrando.
	PROCEDURE ProjectFile
		LOCAL lcDir, loErr, loPj
		lcDir = This.cProjectDir
		IF EMPTY(lcDir)
			TRY
				IF _VFP.Projects.Count > 0
					IF !(UPPER(_VFP.ActiveProject.Name) == UPPER(This.cClosing))
						lcDir = JUSTPATH(_VFP.ActiveProject.Name)
					ELSE
						FOR EACH loPj IN _VFP.Projects
							IF EMPTY(lcDir) AND !(UPPER(loPj.Name) == UPPER(This.cClosing))
								lcDir = JUSTPATH(loPj.Name)
							ENDIF
						ENDFOR
					ENDIF
				ENDIF
			CATCH TO loErr
				lcDir = ""
			ENDTRY
		ENDIF
		RETURN IIF(EMPTY(lcDir), "", ADDBS(lcDir) + "connections.json")
	ENDPROC

	PROCEDURE SecretFile
		LPARAMETERS tcId
		RETURN This.oHost.DataDir + "secrets\" + LOWER(tcId) + ".cred"
	ENDPROC

	*--------------------------------------------------------------
	* Los ficheros.
	*--------------------------------------------------------------
	PROCEDURE Load
		LOCAL lcProject, loLive, lnI, lcId, loOld, loC
		loOld = This.oList
		This.oList = CREATEOBJECT("Collection")
		lcProject = This.ProjectFile()
		IF !EMPTY(lcProject)
			This.ReadFile(lcProject, "project")
		ENDIF
		This.ReadFile(This.UserFile(), "user")
		*-- Las conectadas que ya no están en los ficheros se cierran. Las que siguen
		*-- se quedan conectadas, salvo si cambió su definición: la viva ya no sería
		*-- la del fichero. Un cambio solo en agentCanRead o allowWrite no la toca.
		FOR lnI = This.oLive.Count TO 1 STEP -1
			lcId = This.oLive.GetKey(lnI)
			DO CASE
				CASE This.oList.GetKey(lcId) = 0
					This.Disconnect(lcId)
				CASE VARTYPE(loOld) == "O" AND loOld.GetKey(lcId) > 0
					loC = This.oList.Item(lcId)
					IF !(This.Definition(loOld.Item(lcId)) == This.Definition(loC))
						This.Disconnect(lcId, "its definition changed")
						This.oHost.NotifyKey("data.conn.changed", loC.cName)
					ENDIF
			ENDCASE
		ENDFOR
		This.oHost.Log("data.connections: " + TRANSFORM(This.oList.Count) + " connection(s)" + ;
			IIF(EMPTY(lcProject), " (no project open)", ""))
		RETURN This.oList.Count
	ENDPROC

	PROCEDURE ReadFile
		LPARAMETERS tcFile, tcOrigin
		LOCAL lcText, loJ, loObjs, loC, loK, lnI, lcWhy, lnN
		IF !FILE(tcFile)
			RETURN 0
		ENDIF
		lcText = This.TextOf(FILETOSTR(tcFile))
		IF !(LEFT(ALLTRIM(lcText, 1, " ", CHR(9), CHR(13), CHR(10)), 1) == "[")
			This.oHost.LogWarn("data.connections: " + tcFile + " is not read: it has to be a JSON array of connections, " + ;
				"[ { " + ["id": ..., "name": ..., "engine": ...] + " }, ... ]")
			RETURN 0
		ENDIF
		loJ = This.oHost.oJson
		loObjs = loJ.Split(lcText)
		*-- Primero, que no haya ninguna contraseña: si la hay, no se lee nada.
		FOR lnI = 1 TO loObjs.Count
			lcWhy = This.SecretIn(loJ.Parse(loObjs.Item(lnI)))
			IF !EMPTY(lcWhy)
				This.oHost.LogWarn("data.connections: " + tcFile + " is not read: connection " + TRANSFORM(lnI) + " has " + ;
					lcWhy + ". A password never goes in connections.json: take it out, and type it in Connect... " + ;
					"(Remember keeps it encrypted with your Windows account).")
				RETURN 0
			ENDIF
		ENDFOR
		lnN = 0
		FOR lnI = 1 TO loObjs.Count
			loC = This.Make(loJ.Parse(loObjs.Item(lnI)), tcFile, tcOrigin)
			IF ISNULL(loC)
				LOOP
			ENDIF
			IF This.oList.GetKey(loC.cId) > 0
				This.oHost.LogWarn("data.connections: '" + loC.cId + "' in " + tcFile + " is left out: " + ;
					This.oList.Item(loC.cId).cFile + " has one with that id")
				LOOP
			ENDIF
			This.oList.Add(loC, loC.cId)
			lnN = lnN + 1
		ENDFOR
		This.oHost.Log("data.connections: " + TRANSFORM(lnN) + " from " + tcFile)
		RETURN lnN
	ENDPROC

	*-- El texto del fichero en CPCURRENT(): UTF-8 (con BOM o sin él) o ANSI.
	PROCEDURE TextOf
		LPARAMETERS tcRaw
		LOCAL lcBack
		IF LEFT(tcRaw, 3) == CHR(0xEF) + CHR(0xBB) + CHR(0xBF)
			RETURN STRCONV(SUBSTR(tcRaw, 4), 11)
		ENDIF
		lcBack = STRCONV(STRCONV(tcRaw, 11), 9)
		IF lcBack == tcRaw AND !(STRCONV(tcRaw, 11) == tcRaw)
			RETURN STRCONV(tcRaw, 11)
		ENDIF
		RETURN tcRaw
	ENDPROC

	*-- Por qué una conexión del fichero lleva una contraseña ("" si no la
	*-- lleva). El motivo nombra la clave, nunca el valor.
	PROCEDURE SecretIn
		LPARAMETERS toC
		LOCAL lnI, lcKey, luV
		FOR lnI = 1 TO toC.Count
			lcKey = LOWER(toC.GetKey(lnI))
			IF INLIST(lcKey, "password", "pwd", "passwd", "secret", "pass")
				RETURN "a '" + lcKey + "' key"
			ENDIF
			luV = toC.Item(lnI)
			IF VARTYPE(luV) == "C" AND (ATC("pwd=", CHRTRAN(luV, " ", "")) > 0 OR ATC("password=", CHRTRAN(luV, " ", "")) > 0)
				RETURN "a password inside its '" + lcKey + "' value"
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- Una conexión del fichero, o .NULL. (con su línea de log) si no vale.
	PROCEDURE Make
		LPARAMETERS toC, tcFile, tcOrigin
		LOCAL loJ, loO, lcId, lcEngine
		loJ = This.oHost.oJson
		lcId = ALLTRIM(TRANSFORM(NVL(loJ.Get(toC, "id", ""), "")))
		lcEngine = LOWER(ALLTRIM(TRANSFORM(NVL(loJ.Get(toC, "engine", ""), ""))))
		DO CASE
			CASE EMPTY(lcId) OR LEN(lcId) > 64 OR LEN(CHRTRAN(LOWER(lcId), "abcdefghijklmnopqrstuvwxyz0123456789_-.", "")) > 0
				This.oHost.LogWarn("data.connections: a connection in " + tcFile + " is left out: its id '" + lcId + ;
					"' has to be 1 to 64 letters, digits, '_', '-' or '.'")
				RETURN .NULL.
			CASE !("," + lcEngine + "," $ "," + DC_ENGINES + ",")
				This.oHost.LogWarn("data.connections: '" + lcId + "' in " + tcFile + " is left out: engine '" + lcEngine + ;
					"' is not one of " + STRTRAN(DC_ENGINES, ",", ", "))
				RETURN .NULL.
		ENDCASE
		loO = CREATEOBJECT("Empty")
		ADDPROPERTY(loO, "cId", LOWER(lcId))
		ADDPROPERTY(loO, "cName", This.Text(loJ.Get(toC, "name", ""), lcId))
		ADDPROPERTY(loO, "cEngine", lcEngine)
		ADDPROPERTY(loO, "cServer", This.Text(loJ.Get(toC, "server", ""), ""))
		ADDPROPERTY(loO, "nPort", INT(VAL(TRANSFORM(NVL(loJ.Get(toC, "port", 0), 0)))))
		ADDPROPERTY(loO, "cDatabase", This.Text(loJ.Get(toC, "database", ""), ""))
		ADDPROPERTY(loO, "cUser", This.Text(loJ.Get(toC, "user", ""), ""))
		ADDPROPERTY(loO, "cDriver", This.Text(loJ.Get(toC, "driver", ""), This.DefaultDriver(lcEngine)))
		ADDPROPERTY(loO, "lWindowsAuth", This.Flag(loJ.Get(toC, "windowsauth", .F.)))
		ADDPROPERTY(loO, "lAllowWrite", This.Flag(loJ.Get(toC, "allowwrite", .F.)))
		ADDPROPERTY(loO, "lAgentCanRead", This.Flag(loJ.Get(toC, "agentcanread", .F.)))
		ADDPROPERTY(loO, "cOrigin", tcOrigin)
		ADDPROPERTY(loO, "cFile", tcFile)
		RETURN loO
	ENDPROC

	*-- Lo que hace que una conexión viva sea esa: si cambia en el fichero,
	*-- Reload la desconecta.
	PROCEDURE Definition
		LPARAMETERS toC
		RETURN toC.cEngine + "|" + LOWER(toC.cServer) + "|" + TRANSFORM(toC.nPort) + "|" + LOWER(toC.cDatabase) + "|" + ;
			LOWER(toC.cUser) + "|" + LOWER(toC.cDriver) + "|" + TRANSFORM(toC.lWindowsAuth)
	ENDPROC

	*-- Solo true es verdadero: "true" entre comillas, 1 o null no lo son.
	PROTECTED PROCEDURE Flag
		LPARAMETERS tuV
		RETURN VARTYPE(tuV) == "L" AND tuV
	ENDPROC

	PROTECTED PROCEDURE Text
		LPARAMETERS tuV, tcDefault
		tuV = IIF(ISNULL(tuV), "", ALLTRIM(TRANSFORM(tuV)))
		RETURN IIF(EMPTY(tuV), tcDefault, tuV)
	ENDPROC

	*-- Los drivers ODBC con los que se probó FoxRemote (su README).
	PROCEDURE DefaultDriver
		LPARAMETERS tcEngine
		DO CASE
			CASE tcEngine == "sqlserver"
				RETURN "ODBC Driver 18 for SQL Server"
			CASE INLIST(tcEngine, "mysql", "mariadb")
				RETURN "MariaDB ODBC 3.2 Driver"
			CASE tcEngine == "postgresql"
				RETURN "PostgreSQL ANSI"
			CASE tcEngine == "firebird"
				RETURN "Firebird ODBC Driver"
		ENDCASE
		RETURN "SQLite3 ODBC Driver"
	ENDPROC

	PROCEDURE EngineClass
		LPARAMETERS tcEngine
		DO CASE
			CASE tcEngine == "sqlserver"
				RETURN "RemoteSqlServer"
			CASE tcEngine == "mysql"
				RETURN "RemoteMySql"
			CASE tcEngine == "mariadb"
				RETURN "RemoteMariaDb"
			CASE tcEngine == "postgresql"
				RETURN "RemotePostgreSql"
			CASE tcEngine == "firebird"
				RETURN "RemoteFirebird"
		ENDCASE
		RETURN "RemoteSqlite"
	ENDPROC

	PROCEDURE Find
		LPARAMETERS tcId
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		IF !EMPTY(tcId) AND This.oList.GetKey(tcId) > 0
			RETURN This.oList.Item(tcId)
		ENDIF
		RETURN .NULL.
	ENDPROC

	*-- Hace falta contraseña: hay usuario y no es la autenticación de Windows.
	PROCEDURE NeedsSecret
		LPARAMETERS toC
		RETURN !toC.lWindowsAuth AND !EMPTY(toC.cUser)
	ENDPROC

	PROCEDURE HasSavedSecret
		LPARAMETERS tcId
		RETURN FILE(This.SecretFile(tcId))
	ENDPROC

	*--------------------------------------------------------------
	* Los secretos (DPAPI).
	*--------------------------------------------------------------
	PROCEDURE SaveSecret
		LPARAMETERS tcId, tcSecret
		LOCAL loD, lcBlob, lcDir, lcSafety
		loD = CREATEOBJECT("DataDpapi")
		lcBlob = loD.Protect(tcSecret)
		IF EMPTY(lcBlob)
			This.cLastError = "The password could not be encrypted with your Windows account (CryptProtectData, error " + ;
				TRANSFORM(loD.nLastError) + "): it was not kept."
			RETURN .F.
		ENDIF
		lcDir = JUSTPATH(This.SecretFile(tcId))
		IF !DIRECTORY(lcDir, 1)
			MKDIR (lcDir)
		ENDIF
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		STRTOFILE(lcBlob, This.SecretFile(tcId), 0)
		SET SAFETY &lcSafety
		This.oHost.Log("data.connections: the password of '" + tcId + "' is kept, encrypted with the Windows account, in " + ;
			This.SecretFile(tcId))
		RETURN .T.
	ENDPROC

	*-- La contraseña guardada, o "" (y por qué, en cLastError).
	PROCEDURE ReadSecret
		LPARAMETERS tcId
		LOCAL loD, lcSecret
		IF !This.HasSavedSecret(tcId)
			RETURN ""
		ENDIF
		loD = CREATEOBJECT("DataDpapi")
		lcSecret = loD.Unprotect(FILETOSTR(This.SecretFile(tcId)))
		IF EMPTY(lcSecret)
			This.cLastError = "The kept password of '" + tcId + "' could not be decrypted (CryptUnprotectData, error " + ;
				TRANSFORM(loD.nLastError) + "): it was kept by another Windows user, or on another machine. Connect... again."
		ENDIF
		RETURN lcSecret
	ENDPROC

	PROCEDURE ForgetSecret
		LPARAMETERS tcId
		IF This.HasSavedSecret(tcId)
			*-- Se borra igual, porque la conexión se fue. Si VFP corre dentro de un
			*-- paquete MSIX, el borrado alcanza también al fichero real, y el log lo dice.
			ERASE (This.SecretFile(tcId))
			This.oHost.Log("data.connections: the kept password of '" + tcId + "' was removed" + ;
				IIF(PEMSTATUS(This.oHost, "lDataShadowed", 5) AND This.oHost.lDataShadowed, ;
				" (inside the package " + This.oHost.cPackage + ": the real file is gone too)", ""))
		ENDIF
	ENDPROC

	*--------------------------------------------------------------
	* Conectar.
	*--------------------------------------------------------------
	PROCEDURE IsConnected
		LPARAMETERS tcId
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		RETURN This.oLive.GetKey(tcId) > 0 AND This.oLive.Item(tcId).nHandle > 0
	ENDPROC

	PROCEDURE Live
		LPARAMETERS tcId
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		RETURN IIF(This.oLive.GetKey(tcId) > 0, This.oLive.Item(tcId), .NULL.)
	ENDPROC

	*-- Conecta tcId. tcPassword: la tecleada en Connect... ("" = la guardada,
	*-- si hace falta). tlRemember: guardarla con DPAPI si conecta.
	PROCEDURE Connect
		LPARAMETERS tcId, tcPassword, tlRemember
		LOCAL loC, loDb, lcPwd, llOk, lcWhy, lcDriverMsg
		This.cLastError = ""
		This.cLastCode = ""
		This.lNeedsConnectBar = .F.
		loC = This.Find(tcId)
		IF ISNULL(loC)
			This.cLastError = This.NoSuch(tcId)
			RETURN .F.
		ENDIF
		IF This.IsConnected(loC.cId)
			RETURN .T.
		ENDIF
		*-- Sin base es una conexión al servidor; pero en SQLite y Firebird la base
		*-- es el fichero.
		IF EMPTY(loC.cDatabase) AND INLIST(loC.cEngine, "sqlite", "firebird")
			This.cLastError = "Connection '" + loC.cId + "' has no database: for " + loC.cEngine + ;
				[ it is the database file, and it goes in the "database" of connections.json.]
			RETURN .F.
		ENDIF
		IF This.oLive.GetKey(loC.cId) > 0
			This.oLive.Remove(loC.cId)
		ENDIF
		lcPwd = ""
		IF This.NeedsSecret(loC)
			lcPwd = IIF(VARTYPE(tcPassword) == "C", tcPassword, "")
			IF EMPTY(lcPwd)
				lcPwd = This.ReadSecret(loC.cId)
			ENDIF
			IF EMPTY(lcPwd)
				This.lNeedsConnectBar = .T.
				This.cLastCode = "not_connected"
				This.cLastError = IIF(EMPTY(This.cLastError), "", This.cLastError + " ") + "Connection '" + loC.cId + ;
					"' needs the password of '" + loC.cUser + "', and none is kept: press FoxDock > Data > Connections > " + ;
					loC.cName + " > Connect... once in the IDE (with Remember, it is kept encrypted with your Windows account)."
				RETURN .F.
			ENDIF
		ENDIF
		loDb = NEWOBJECT(This.EngineClass(loC.cEngine), This.FoxRemotePrg())
		loDb.cDriver = loC.cDriver
		loDb.cServer = loC.cServer
		loDb.nPort = loC.nPort
		loDb.cDatabase = loC.cDatabase
		loDb.cUser = IIF(loC.lWindowsAuth, "", loC.cUser)
		loDb.cPassword = lcPwd
		IF loC.cEngine == "sqlserver"
			loDb.lTrustedConnection = loC.lWindowsAuth
		ENDIF
		llOk = loDb.Connect()
		loDb.cPassword = ""
		IF !llOk
			lcDriverMsg = This.Scrub(loDb.cLastError, lcPwd)
			IF loDb.cLastSqlState == "IM002"
				lcWhy = "the ODBC driver '" + loC.cDriver + "' is not installed for " + IIF(This.Is64(), "64", "32") + ;
					"-bit programs on this Windows (this Visual FoxPro is " + IIF(This.Is64(), "64", "32") + "-bit, and it needs the " + ;
					IIF(This.Is64(), "64", "32") + "-bit driver). Install it, or put the name of the one you have in " + ;
					[the "driver" of this connection (the ODBC Data Source Administrator lists them). The driver manager said: ] + lcDriverMsg
			ELSE
				lcWhy = lcDriverMsg
			ENDIF
			This.cLastError = "Connect to '" + loC.cId + "' failed: " + lcWhy
			This.oHost.LogWarn("data.connections: " + This.cLastError)
			RETURN .F.
		ENDIF
		This.oLive.Add(loDb, loC.cId)
		IF tlRemember AND This.NeedsSecret(loC) AND VARTYPE(tcPassword) == "C" AND !EMPTY(tcPassword)
			This.SaveSecret(loC.cId, tcPassword)
		ENDIF
		This.oHost.Log("data.connections: connected to '" + loC.cId + "' (" + loC.cEngine + ", " + ;
			IIF(EMPTY(loC.cServer), "", loC.cServer + ", ") + ;
			IIF(EMPTY(loC.cDatabase), "no database given: the server's default, " + This.CurrentDatabase(loC.cId), loC.cDatabase) + ")")
		*-- El menú dice qué conexión está conectada.
		This.oHost.RefreshMenu()
		RETURN .T.
	ENDPROC

	*-- La base en la que está la conexión: la de connections.json si la
	*-- tiene; si no, la que diga el servidor (DB_NAME() de SQL Server viene
	*-- rellena de espacios). "" si no está conectada o no se sabe.
	PROCEDURE CurrentDatabase
		LPARAMETERS tcId
		LOCAL loC, loDb, lcSql, lvV, lnDs
		loC = This.Find(tcId)
		IF ISNULL(loC)
			RETURN ""
		ENDIF
		IF !This.IsConnected(loC.cId)
			RETURN loC.cDatabase
		ENDIF
		*-- La de la conexión viva, que el combo de Explore... puede haber
		*-- cambiado; vacía si se conectó sin base.
		loDb = This.Live(loC.cId)
		IF !EMPTY(loDb.cDatabase)
			RETURN loDb.cDatabase
		ENDIF
		DO CASE
			CASE loC.cEngine == "sqlserver"
				lcSql = "SELECT DB_NAME()"
			CASE INLIST(loC.cEngine, "mysql", "mariadb")
				lcSql = "SELECT DATABASE()"
			CASE loC.cEngine == "postgresql"
				lcSql = "SELECT current_database()"
			OTHERWISE
				RETURN ""
		ENDCASE
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lvV = This.Scalar(loC.cId, loDb, lcSql)
		SET DATASESSION TO (lnDs)
		RETURN IIF(VARTYPE(lvV) == "C", ALLTRIM(lvV), "")
	ENDPROC

	*-- Un Scalar de FoxRemote que, con la conexión muerta, no deja salir el
	*-- error de VFP (1466) y pasa por CheckLost. .NULL. si falla.
	PROCEDURE Scalar
		LPARAMETERS tcId, toDb, tcSql
		LOCAL lvV, loErr, lcErr
		lcErr = ""
		TRY
			lvV = toDb.Scalar(tcSql)
		CATCH TO loErr
			lvV = .NULL.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		IF ISNULL(lvV) OR !EMPTY(lcErr)
			=This.CheckLost(tcId, EVL(lcErr, toDb.cLastError))
		ENDIF
		RETURN lvV
	ENDPROC

	*-- Tras un fallo, ¿sigue viva tcId? Así el usuario sabe cuándo se le ha
	*-- desconectado la base. Un ping (Ping de FoxRemote, con el error de VFP
	*-- atrapado: con el handle muerto da 1466). Si no contesta, Lost. .T. si se
	*-- perdió.
	PROCEDURE CheckLost
		LPARAMETERS tcId, tcWhy
		LOCAL loDb, llAlive, loErr, lcWhy
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		loDb = This.Live(tcId)
		IF ISNULL(loDb)
			RETURN .F.
		ENDIF
		lcWhy = ALLTRIM(TRANSFORM(tcWhy))
		llAlive = .F.
		TRY
			llAlive = loDb.nHandle > 0 AND loDb.Ping()
		CATCH TO loErr
			llAlive = .F.
			lcWhy = EVL(lcWhy, TRANSFORM(loErr.ErrorNo) + " " + loErr.Message)
		ENDTRY
		IF llAlive
			RETURN .F.
		ENDIF
		This.Lost(tcId, EVL(lcWhy, "the server does not answer"))
		RETURN .T.
	ENDPROC

	*-- La conexión tcId se perdió: fuera de oLive, su Explore... cerrado con sus
	*-- cursores (Disconnect), el log, el aviso y el menú. cLastError lo dice en
	*-- inglés, con cómo volver a conectar, y cLastCode es «not_connected».
	PROCEDURE Lost
		LPARAMETERS tcId, tcWhy
		LOCAL loC, lcName, lcShort, lcText, lnRoom
		loC = This.Find(tcId)
		lcName = IIF(ISNULL(loC), tcId, loC.cName)
		tcWhy = ALLTRIM(tcWhy)
		IF RIGHT(tcWhy, 1) == "."
			tcWhy = LEFT(tcWhy, LEN(tcWhy) - 1)
		ENDIF
		=This.Disconnect(tcId, "the connection was lost")
		This.cLastError = This.E("data.conn.lost", lcName, tcWhy)
		This.cLastCode = "not_connected"
		This.oHost.LogWarn("data.connections: " + This.cLastError)
		*-- Primero cómo volver a conectar; el motivo, detrás y recortado aquí: el
		*-- aviso no pasa de 255 caracteres, y el mensaje entero del driver se comía
		*-- el resto. El log y lo que lee el agente lo llevan entero.
		lcShort = This.LostReason(tcWhy)
		lcText = This.T("data.conn.lostNotice", lcName, "")
		lnRoom = 255 - LEN(lcText) - LEN(This.T("data.conn.lostWhy", ""))
		IF !EMPTY(lcShort) AND lnRoom >= 20
			IF LEN(lcShort) > lnRoom
				lcShort = LEFT(lcShort, lnRoom - 3) + "..."
			ENDIF
			lcText = This.T("data.conn.lostNotice", lcName, This.T("data.conn.lostWhy", lcShort))
		ENDIF
		This.oHost.Notify(lcText, This.E("data.conn.lostNotice", lcName, This.E("data.conn.lostWhy", tcWhy)))
	ENDPROC

	*-- El motivo para el aviso. El del driver, lo que va detrás de su último
	*-- corchete ([Microsoft][ODBC Driver 17 for SQL Server]...), que viene en el
	*-- idioma de Windows; el nuestro del ping, traducido; otro, citado.
	PROCEDURE LostReason
		LPARAMETERS tcWhy
		LOCAL lnAt, lcR
		lnAt = RAT("]", tcWhy)
		lcR = IIF(lnAt > 0, ALLTRIM(SUBSTR(tcWhy, lnAt + 1)), "")
		DO CASE
			CASE !EMPTY(lcR)
				RETURN lcR
			CASE tcWhy == "the server does not answer"
				RETURN This.T("data.conn.noAnswer")
		ENDCASE
		RETURN This.oHost.Quoted(tcWhy)
	ENDPROC

	*-- El límite de filas de Query... (0 = sin límite), y guardarlo.
	PROCEDURE QueryLimit
		LOCAL lnN
		lnN = This.oHost.Options.Get("data", "connections.queryLimit", 100)
		lnN = IIF(VARTYPE(lnN) == "N", INT(lnN), INT(VAL(TRANSFORM(lnN))))
		RETURN MAX(lnN, 0)
	ENDPROC

	PROCEDURE SaveQueryLimit
		LPARAMETERS tnLimit
		IF This.QueryLimit() # tnLimit
			This.oHost.Options.Set("data", "connections.queryLimit", tnLimit)
		ENDIF
	ENDPROC

	*-- «Keep the cursors open when it closes» de Explore... y de Query...
	*-- (tcWindow: explore o query), una por ventana, sin marcar de entrada; y
	*-- guardarla.
	PROCEDURE KeepCursors
		LPARAMETERS tcWindow
		LOCAL luV
		luV = This.oHost.Options.Get("data", "connections.keep" + PROPER(tcWindow) + "Cursors", .F.)
		RETURN VARTYPE(luV) == "L" AND luV
	ENDPROC

	PROCEDURE SaveKeepCursors
		LPARAMETERS tcWindow, tlKeep
		IF This.KeepCursors(tcWindow) # tlKeep
			This.oHost.Options.Set("data", "connections.keep" + PROPER(tcWindow) + "Cursors", tlKeep)
		ENDIF
	ENDPROC

	*-- «Updatable» de Create view...: marcada de entrada, y después como la dejó
	*-- el usuario la última vez.
	PROCEDURE ViewUpdatable
		LOCAL luV
		luV = This.oHost.Options.Get("data", "connections.createViewUpdatable", .T.)
		RETURN VARTYPE(luV) # "L" OR luV
	ENDPROC

	PROCEDURE SaveViewUpdatable
		LPARAMETERS tlOn
		IF This.ViewUpdatable() # tlOn
			This.oHost.Options.Set("data", "connections.createViewUpdatable", tlOn)
		ENDIF
	ENDPROC

	*-- tcWhy: por qué, para el log; sin él, «the connection was closed».
	PROCEDURE Disconnect
		LPARAMETERS tcId, tcWhy
		LOCAL loDb, loErr
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		IF This.oLive.GetKey(tcId) = 0
			RETURN .F.
		ENDIF
		=This.CloseExplore(tcId, EVL(tcWhy, "the connection was closed"))
		loDb = This.oLive.Item(tcId)
		This.oLive.Remove(tcId)
		TRY
			loDb.Disconnect()
		CATCH TO loErr
			*-- Con el handle muerto, SQLDISCONNECT da 1466; sin esto, el Destroy de
			*-- FoxRemote lo intentaría otra vez al soltar el objeto, ya fuera de este TRY.
			loDb.nHandle = 0
		ENDTRY
		This.oHost.Log("data.connections: disconnected from '" + tcId + "'" + IIF(EMPTY(tcWhy), "", ": " + tcWhy))
		*-- El menú deja de decir «(connected)»; no al cerrarlas todas.
		IF !This.lClosing
			This.oHost.RefreshMenu()
		ENDIF
		RETURN .T.
	ENDPROC

	PROCEDURE Is64
		RETURN TYPE("_WIN64") == "L" AND _WIN64
	ENDPROC

	*-- Un texto de FoxRemote o del driver sin la contraseña (por si la repite).
	PROCEDURE Scrub
		LPARAMETERS tcText, tcPwd
		tcText = TRANSFORM(tcText)
		IF !EMPTY(tcPwd)
			tcText = STRTRAN(tcText, tcPwd, "********")
		ENDIF
		RETURN tcText
	ENDPROC

	PROCEDURE NoSuch
		LPARAMETERS tcId
		RETURN "There is no connection '" + TRANSFORM(tcId) + "' in connections.json (" + This.Ids() + ")."
	ENDPROC

	PROCEDURE Ids
		LOCAL lcS, loC
		lcS = ""
		FOR EACH loC IN This.oList FOXOBJECT
			lcS = lcS + IIF(EMPTY(lcS), "", ", ") + loC.cId
		ENDFOR
		RETURN IIF(EMPTY(lcS), "there are none: FoxDock > Data > Connections > Edit connections... adds them", "there are: " + lcS)
	ENDPROC

	*--------------------------------------------------------------
	* Lo que leen las tools y las barras. Todo en la sesión de datos 1.
	*--------------------------------------------------------------

	*-- "" si el agente puede leer tcId, o por qué no.
	PROCEDURE AgentRefusal
		LPARAMETERS tcId
		LOCAL loC
		loC = This.Find(tcId)
		DO CASE
			CASE ISNULL(loC)
				RETURN This.NoSuch(tcId)
			CASE !loC.lAgentCanRead
				RETURN "Connection '" + loC.cId + "' is not open to the agent: agentCanRead is false in " + loC.cFile + ;
					". What the agent reads leaves this machine for the AI provider, so the person decides it, connection by " + ;
					[connection: to allow it, set "agentCanRead": true in that connection (FoxDock > Data > Connections > ] + ;
					"Edit connections...), then FoxDock > Data > Connections > Reload (Reload plugins would close the connections)."
		ENDCASE
		RETURN ""
	ENDPROC

	*-- Conectada, o conecta sin preguntar nada (Windows, sin usuario o con la
	*-- contraseña guardada). .F. con el motivo en cLastError.
	PROCEDURE Ready
		LPARAMETERS tcId
		This.cLastCode = ""
		IF This.IsConnected(tcId)
			RETURN .T.
		ENDIF
		RETURN This.Connect(tcId, "", .F.)
	ENDPROC

	*-- Las tablas en el cursor tcCursor (sesión 1). Devuelve cuántas, o -1.
	PROCEDURE Tables
		LPARAMETERS tcId, tcCursor
		LOCAL loDb, lnDs, llOk, lnN, lcErr, loErr
		IF !This.Ready(tcId)
			RETURN -1
		ENDIF
		loDb = This.Live(tcId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcErr = ""
		TRY
			llOk = loDb.GetTables(tcCursor)
		CATCH TO loErr
			llOk = .F.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		lnN = IIF(llOk, RECCOUNT(tcCursor), -1)
		SET DATASESSION TO (lnDs)
		IF !llOk AND !This.CheckLost(tcId, EVL(lcErr, loDb.cLastError))
			This.cLastError = "The tables of '" + tcId + "' could not be read: " + EVL(lcErr, loDb.cLastError)
		ENDIF
		RETURN lnN
	ENDPROC

	*-- El nombre de la tabla tal como lo da el servidor, o "" (no está).
	PROCEDURE TableName
		LPARAMETERS tcId, tcTable
		LOCAL lcCur, lcName, lnDs
		lcCur = "FDT" + SYS(2015)
		IF This.Tables(tcId, lcCur) < 0
			RETURN ""
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcName = ""
		SELECT (lcCur)
		LOCATE FOR UPPER(ALLTRIM(name)) == UPPER(ALLTRIM(tcTable))
		IF FOUND()
			lcName = ALLTRIM(name)
		ENDIF
		USE IN (lcCur)
		SET DATASESSION TO (lnDs)
		IF EMPTY(lcName)
			This.cLastError = "There is no table '" + tcTable + "' in connection '" + tcId + "' (ide_data_db_tables lists them)."
		ENDIF
		RETURN lcName
	ENDPROC

	*-- Las columnas de una tabla en tcCursor (sesión 1): name, type, width,
	*-- decimals, nullable, primary_key (los de FoxRemote).
	PROCEDURE Columns
		LPARAMETERS tcId, tcTable, tcCursor
		LOCAL loDb, lnDs, llOk, lcName, lcErr, loErr
		lcName = This.TableName(tcId, tcTable)
		IF EMPTY(lcName)
			RETURN ""
		ENDIF
		loDb = This.Live(tcId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcErr = ""
		TRY
			llOk = This.BinaryRead(loDb, "columns", lcName, tcCursor)
		CATCH TO loErr
			llOk = .F.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		SET DATASESSION TO (lnDs)
		IF !llOk
			IF !This.CheckLost(tcId, EVL(lcErr, loDb.cLastError))
				This.cLastError = "The columns of '" + lcName + "' could not be read: " + EVL(lcErr, loDb.cLastError)
			ENDIF
			RETURN ""
		ENDIF
		RETURN lcName
	ENDPROC

	*-- Lo que se lee de una conexión, con los binarios como binarios: el
	*-- SELECT (tcHow "query", tcArg la sentencia) o las columnas de una tabla
	*-- (tcHow "columns", tcArg su nombre) en tcAlias, con MapBinary puesto en la
	*-- sesión en curso (la 1, la del foxero): SQL_BINARY, SQL_VARBINARY y
	*-- SQL_LONGVARBINARY llegan como Varbinary o Blob, y no como Character o
	*-- General. El valor que tuviera se devuelve siempre, también si la lectura
	*-- falla, como CreateView hace con MapVarchar. Por aquí pasan Query y
	*-- GetColumns a la vez: si no, el CREATE y el INSERT de un script no casan.
	PROCEDURE BinaryRead
		LPARAMETERS toDb, tcHow, tcArg, tcAlias
		LOCAL llMap, llOk
		llMap = CURSORGETPROP("MapBinary", 0)
		TRY
			=CURSORSETPROP("MapBinary", .T., 0)
			IF tcHow == "columns"
				llOk = toDb.GetColumns(tcArg, tcAlias)
			ELSE
				llOk = toDb.Query(tcArg, tcAlias)
			ENDIF
		FINALLY
			=CURSORSETPROP("MapBinary", llMap, 0)
		ENDTRY
		RETURN llOk
	ENDPROC

	*-- Las columnas OCTETS (CHAR o VARCHAR ... CHARACTER SET OCTETS) de la tabla
	*-- tcTable de Firebird, del catálogo del servidor: el driver las da como
	*-- texto, y MapBinary no las toca. «,nombre:CHAR:n,nombre:VARCHAR:n,», con
	*-- el nombre en minúsculas; vacío si no hay o no se pudo leer.
	PROCEDURE FbOctets
		LPARAMETERS tnHandle, tcTable
		LOCAL lnDs, lcOut, lcCur, loErr
		lcOut = ""
		lcCur = "FDO" + SYS(2015)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			IF SQLEXEC(tnHandle, "SELECT TRIM(rf.RDB$FIELD_NAME) AS fname, f.RDB$FIELD_TYPE AS ftype, f.RDB$FIELD_LENGTH AS flen " + ;
					"FROM RDB$RELATION_FIELDS rf JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE " + ;
					"WHERE rf.RDB$RELATION_NAME = '" + STRTRAN(tcTable, "'", "''") + "' AND f.RDB$CHARACTER_SET_ID = 1 " + ;
					"AND f.RDB$FIELD_TYPE IN (14, 37)", lcCur) > 0 AND USED(lcCur)
				SELECT (lcCur)
				SCAN
					lcOut = lcOut + "," + LOWER(ALLTRIM(TRANSFORM(fname))) + ":" + IIF(VAL(TRANSFORM(ftype)) = 14, "CHAR", "VARCHAR") + ;
						":" + TRANSFORM(INT(VAL(TRANSFORM(flen))))
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

	*-- Una columna en el SELECT de una vista de Explore: con el mismo CAST con el
	*-- que la relee TableSelect (ReadCast), o con su nombre entre las comillas del
	*-- motor. tcTypes, de ColumnTypes; tcList, de CastList. Sin el CAST, un
	*-- varbinary(max), un (n)varchar(max) o un LONGTEXT dan el error 1544 en
	*-- CREATE SQL VIEW. Un OCTETS de Firebird va sin CAST, como C(n) o V(n): con
	*-- CAST(x AS BLOB SUB_TYPE BINARY) llega como W, pero al guardarlo TABLEUPDATE
	*-- da .T. y el servidor se queda con lo que tenía.
	PROCEDURE ViewColumn
		LPARAMETERS tcEngine, tcCol, tcTypes, tcList
		LOCAL lcT
		IF tcEngine == "firebird"
			RETURN This.Quoted(tcEngine, tcCol)
		ENDIF
		lcT = STREXTRACT(tcTypes, "," + LOWER(tcCol) + ":", ",")
		RETURN This.CastExpr(tcEngine, tcCol, This.ReadCast(tcEngine, GETWORDNUM(lcT, 1, ":"), VAL(GETWORDNUM(lcT, 2, ":")), ;
			LOWER(tcCol), EVL(tcList, "")))
	ENDPROC

	*-- La columna tcCol en un SELECT, leída con el CAST tcCast de ReadCast y con su
	*-- nombre de siempre; sin CAST, su nombre entre las comillas del motor. Un TEXT
	*-- pasa antes por VARCHAR(MAX), que lo admite desde un nvarchar(max).
	PROCEDURE CastExpr
		LPARAMETERS tcEngine, tcCol, tcCast
		LOCAL lcQ
		lcQ = This.Quoted(tcEngine, tcCol)
		DO CASE
			CASE EMPTY(tcCast)
				RETURN lcQ
			CASE tcCast == "TEXT"
				RETURN "CAST(CAST(" + lcQ + " AS VARCHAR(MAX)) AS TEXT) AS " + lcQ
		ENDCASE
		RETURN "CAST(" + lcQ + " AS " + tcCast + ") AS " + lcQ
	ENDPROC

	*-- La lista del catálogo que necesita ReadCast para la tabla tcTable: las
	*-- columnas OCTETS en Firebird (FbOctets), los textos largos en MySQL y MariaDB
	*-- (MyLongText); en los demás motores, vacía.
	PROCEDURE CastList
		LPARAMETERS tcEngine, tnHandle, tcTable
		DO CASE
			CASE tcEngine == "firebird"
				RETURN This.FbOctets(tnHandle, tcTable)
			CASE INLIST(tcEngine, "mysql", "mariadb")
				RETURN This.MyLongText(tnHandle, tcTable)
		ENDCASE
		RETURN ""
	ENDPROC

	*-- CastList de la tabla tcTable de la conexión tcId, si está conectada; vacía si
	*-- no lo está (entonces cada columna va con el tipo del driver).
	PROCEDURE CastListOf
		LPARAMETERS tcId, tcTable
		LOCAL loC, loDb
		loC = This.Find(tcId)
		loDb = This.Live(tcId)
		IF ISNULL(loC) OR ISNULL(loDb)
			RETURN ""
		ENDIF
		RETURN This.CastList(loC.cEngine, loDb.nHandle, tcTable)
	ENDPROC

	*-- El tipo con el que llega una columna por Explore, «letra:ancho»: W si
	*-- ReadCast la relee como binario, M si la relee como texto largo (las dos con
	*-- el ancho 4 de un Blob o un Memo); si no, el que da el driver.
	PROCEDURE Arrives
		LPARAMETERS tcEngine, tcType, tnWidth, tcName, tcList
		LOCAL lcCast
		lcCast = This.ReadCast(tcEngine, tcType, tnWidth, tcName, tcList)
		DO CASE
			CASE INLIST(lcCast, "IMAGE", "BLOB SUB_TYPE BINARY")
				RETURN "W:4"
			CASE INLIST(lcCast, "TEXT", "CHAR(16777215)")
				RETURN "M:4"
		ENDCASE
		RETURN tcType + ":" + TRANSFORM(tnWidth)
	ENDPROC

	*-- Las columnas de tcTable con su letra y su ancho, como las da GetColumns con
	*-- MapBinary: «,nombre:letra:ancho,», en minúsculas; vacío si no se pudo.
	PROCEDURE ColumnTypes
		LPARAMETERS toDb, tcTable
		LOCAL lcOut, lcCur, lnDs, loErr
		lcOut = ""
		lcCur = "FDT" + SYS(2015)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			IF This.BinaryRead(toDb, "columns", tcTable, lcCur) AND USED(lcCur)
				SELECT (lcCur)
				SCAN
					lcOut = lcOut + "," + LOWER(ALLTRIM(name)) + ":" + ALLTRIM(type) + ":" + TRANSFORM(width)
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

	*-- Con qué tipo vuelve a leer TableSelect una columna, o "" si no hace falta.
	*-- tcList, según el motor: las columnas OCTETS de Firebird (FbOctets) o los
	*-- textos largos de MySQL y MariaDB (MyLongText). En SQL Server, un
	*-- (n)varchar(max) que llega como C(0) va por TEXT, y un varbinary(max) que
	*-- llega como Q(0), por IMAGE.
	PROCEDURE ReadCast
		LPARAMETERS tcEngine, tcType, tnWidth, tcName, tcList
		DO CASE
			CASE tcEngine == "firebird"
				RETURN IIF("," + tcName + ":" $ tcList, "BLOB SUB_TYPE BINARY", "")
			CASE INLIST(tcEngine, "mysql", "mariadb")
				RETURN IIF("," + tcName + "," $ tcList, "CHAR(16777215)", "")
			CASE tcEngine == "sqlserver" AND tcType == "C" AND tnWidth = 0
				RETURN "TEXT"
			CASE tcEngine == "sqlserver" AND tcType == "Q" AND tnWidth = 0
				RETURN "IMAGE"
		ENDCASE
		RETURN ""
	ENDPROC

	*-- Las columnas LONGTEXT y JSON de la tabla tcTable de MySQL o MariaDB, del
	*-- catálogo: el driver da su tamaño como -1 y VFP las corta en un C(255) (o
	*-- C(252)); con CAST(x AS CHAR(16777215)) llegan como memo, enteras.
	*-- «,nombre,», en minúsculas; vacío si no hay o no se pudo leer. tcTypes, otros
	*-- DATA_TYPE del catálogo («'json'»); sin él, los dos.
	PROCEDURE MyLongText
		LPARAMETERS tnHandle, tcTable, tcTypes
		LOCAL lnDs, lcOut, lcCur, loErr
		lcOut = ""
		lcCur = "FDL" + SYS(2015)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			IF SQLEXEC(tnHandle, "SELECT COLUMN_NAME AS cname FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() " + ;
					"AND TABLE_NAME = '" + STRTRAN(tcTable, "'", "''") + "' AND DATA_TYPE IN (" + EVL(tcTypes, "'longtext', 'json'") + ")", lcCur) > 0 AND USED(lcCur)
				SELECT (lcCur)
				SCAN
					lcOut = lcOut + "," + LOWER(ALLTRIM(TRANSFORM(cname)))
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

	*-- Un SELECT en el cursor tcAlias (sesión 1), con tnMax filas como mucho
	*-- (CURSORSETPROP("MaxRecords"): se pide una de más para saber si había
	*-- más, y se quita); tnMax 0, todas (MaxRecords -1).
	*-- Pasa antes por DataSqlGuard: lo que no es una lectura no llega al motor.
	*-- .F. con el motivo en cLastError.
	PROCEDURE Query
		LPARAMETERS tcId, tcSql, tnMax, tcAlias
		LOCAL loG, lcWhy, loDb, lnDs, lnOld, llOk, lcErr, loErr, loC, lcTmp
		This.nLastRows = 0
		This.lLastTruncated = .F.
		loG = CREATEOBJECT("DataSqlGuard")
		loC = This.Find(tcId)
		loG.cEngine = IIF(ISNULL(loC), "", loC.cEngine)
		lcWhy = loG.Check(tcSql)
		IF !EMPTY(lcWhy)
			This.cLastError = "Only reading: one statement that starts with SELECT or WITH, without a ';' and something " + ;
				"after it. This one " + lcWhy + ". Nothing was sent to the server. (To write, ide_data_db_execute, on a " + ;
				"connection with allowWrite true and with agent role 10 or higher.)"
			RETURN .F.
		ENDIF
		IF !This.Ready(tcId)
			RETURN .F.
		ENDIF
		loDb = This.Live(tcId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		IF USED(tcAlias)
			USE IN (tcAlias)
		ENDIF
		lnOld = CURSORGETPROP("MaxRecords", 0)
		=CURSORSETPROP("MaxRecords", IIF(tnMax > 0, tnMax + 1, -1), 0)
		lcErr = ""
		TRY
			llOk = This.BinaryRead(loDb, "query", loG.cSql, tcAlias)
		CATCH TO loErr
			llOk = .F.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		FINALLY
			=CURSORSETPROP("MaxRecords", lnOld, 0)
		ENDTRY
		IF llOk AND !USED(tcAlias)
			llOk = .F.
			lcErr = "the statement gave no rows to read"
		ENDIF
		IF llOk
			IF tnMax > 0 AND RECCOUNT(tcAlias) > tnMax
				This.lLastTruncated = .T.
				*-- La fila de más no se borra: con SET DELETED OFF, lo normal en el IDE,
				*-- seguiría en el cursor y en el BROWSE. Se rehace el cursor con las tnMax
				*-- primeras y el mismo alias; INTO CURSOR no acepta el nombre de uno
				*-- abierto, así que va por otro y se cierra el de antes.
				lcTmp = "FDQ" + SYS(2015)
				TRY
					SELECT * FROM &tcAlias WHERE RECNO() <= tnMax INTO CURSOR (lcTmp) READWRITE
					USE IN (tcAlias)
					SELECT * FROM &lcTmp INTO CURSOR (tcAlias) READWRITE
				CATCH TO loErr
					llOk = .F.
					lcErr = "the first " + TRANSFORM(tnMax) + " rows could not be kept: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
				FINALLY
					IF USED(lcTmp)
						USE IN (lcTmp)
					ENDIF
				ENDTRY
			ENDIF
			This.nLastRows = IIF(llOk, IIF(tnMax > 0, MIN(RECCOUNT(tcAlias), tnMax), RECCOUNT(tcAlias)), 0)
		ENDIF
		SET DATASESSION TO (lnDs)
		IF !llOk AND !This.CheckLost(tcId, IIF(EMPTY(lcErr), loDb.cLastError, lcErr))
			This.cLastError = "The query on '" + tcId + "' failed: " + IIF(EMPTY(lcErr), loDb.cLastError, lcErr)
		ENDIF
		RETURN llOk
	ENDPROC

	*-- Query para un SQL escrito a mano (Query... de la ventana e ide_data_db_query):
	*-- si una columna no llega entera, la vuelve a leer envuelta, SELECT <columnas,
	*-- con su CAST> FROM (<sentencia>) AS q, con el mismo alias y el mismo tope.
	*-- Con ORDER BY no se relee (una tabla derivada no guarda el orden), y si la
	*-- envoltura falla queda la primera lectura: en los dos casos, cLastShort dice
	*-- qué columnas no llegaron enteras y cLastShortWhy, por qué. TableSelect va
	*-- por Query, que relee por su cuenta con el catálogo.
	PROCEDURE QueryWhole
		LPARAMETERS tcId, tcSql, tnMax, tcAlias
		LOCAL loC, lcEngine, lcShort, lcCols, lcWrap, lnDs, laF[1], lnN, lnI, lcName, lcTmp, llOk, lnRows, llTrunc, loErr, lcErr
		This.cLastShort = ""
		This.cLastShortWhy = ""
		This.cLastShortEngine = ""
		IF !This.Query(tcId, tcSql, tnMax, tcAlias)
			RETURN .F.
		ENDIF
		loC = This.Find(tcId)
		lcEngine = IIF(ISNULL(loC), "", loC.cEngine)
		IF !INLIST(lcEngine, "sqlserver", "mysql", "mariadb")
			RETURN .T.
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcShort = This.ShortColumns(lcEngine, tcAlias)
		lcCols = ""
		IF !EMPTY(lcShort)
			lnN = AFIELDS(laF, tcAlias)
			FOR lnI = 1 TO lnN
				lcName = LOWER(laF[lnI, 1])
				lcCols = lcCols + IIF(lnI = 1, "", ",") + lcName + ":" + STREXTRACT(lcShort, "," + lcName + ":", ",")
			ENDFOR
		ENDIF
		SET DATASESSION TO (lnDs)
		IF EMPTY(lcShort)
			RETURN .T.
		ENDIF
		lcWrap = This.WrapSql(lcEngine, tcSql, lcCols)
		IF EMPTY(lcWrap)
			This.cLastShort = lcShort
			This.cLastShortWhy = "order_by"
			This.cLastShortEngine = lcEngine
			RETURN .T.
		ENDIF
		lnRows = This.nLastRows
		llTrunc = This.lLastTruncated
		lcTmp = "FDW" + SYS(2015)
		IF !This.Query(tcId, lcWrap, tnMax, lcTmp)
			This.cLastError = ""
			This.nLastRows = lnRows
			This.lLastTruncated = llTrunc
			This.cLastShort = lcShort
			This.cLastShortWhy = "wrap_failed"
			This.cLastShortEngine = lcEngine
			RETURN .T.
		ENDIF
		*-- La relectura, con el alias de la primera: INTO CURSOR no acepta el nombre
		*-- de uno abierto.
		SET DATASESSION TO 1
		llOk = .T.
		TRY
			USE IN (tcAlias)
			SELECT * FROM &lcTmp INTO CURSOR (tcAlias) READWRITE
		CATCH TO loErr
			llOk = .F.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		IF USED(lcTmp)
			USE IN (lcTmp)
		ENDIF
		SET DATASESSION TO (lnDs)
		IF !llOk
			This.cLastError = "The query on '" + tcId + "' was read again and could not be kept: " + lcErr
		ENDIF
		RETURN llOk
	ENDPROC

	*-- Con qué CAST se vuelve a leer una columna de un SQL escrito a mano, de su
	*-- tipo en la primera lectura, o "" si llega entera. Es el de ReadCast, sin
	*-- catálogo, y por el tipo, no por los valores: en SQL Server, un Q(0) o un C(0),
	*-- que llegan vacíos; en MySQL y MariaDB, un C(255), que solo sale de un LONGTEXT
	*-- (o de un JSON de MariaDB), cortado; en MySQL además un C(252), que es como
	*-- llega su JSON (un VARCHAR(252) también llega así, y se relee como memo).
	PROCEDURE ShortCast
		LPARAMETERS tcEngine, tcType, tnWidth
		DO CASE
			CASE tcEngine == "sqlserver"
				RETURN This.ReadCast(tcEngine, tcType, tnWidth, "", "")
			CASE INLIST(tcEngine, "mysql", "mariadb") AND tcType == "C" AND (tnWidth = 255 OR (tnWidth = 252 AND tcEngine == "mysql"))
				RETURN This.ReadCast(tcEngine, tcType, tnWidth, "c", ",c,")
		ENDCASE
		RETURN ""
	ENDPROC

	*-- Las columnas del cursor tcAlias (sesión en curso) que no llegan enteras,
	*-- «,nombre:CAST,» en minúsculas; vacío si todas llegan.
	PROCEDURE ShortColumns
		LPARAMETERS tcEngine, tcAlias
		LOCAL lnN, lnI, laF[1], lcOut, lcCast
		lcOut = ""
		lnN = AFIELDS(laF, tcAlias)
		FOR lnI = 1 TO lnN
			lcCast = This.ShortCast(tcEngine, laF[lnI, 2], laF[lnI, 3])
			IF !EMPTY(lcCast)
				lcOut = lcOut + "," + LOWER(laF[lnI, 1]) + ":" + lcCast
			ENDIF
		ENDFOR
		RETURN IIF(EMPTY(lcOut), "", lcOut + ",")
	ENDPROC

	*-- La sentencia tcSql envuelta para volver a leerla: SELECT <columnas> FROM
	*-- (<sentencia>) AS q. tcCols, «nombre:CAST,nombre:,...» en el orden de la
	*-- primera lectura (el CAST vacío, la columna por su nombre). Con ORDER BY en
	*-- cualquier sitio, "": una tabla derivada no garantiza el orden.
	PROCEDURE WrapSql
		LPARAMETERS tcEngine, tcSql, tcCols
		LOCAL lcU, lcS, lcOut, lnI, lcC
		lcU = " " + UPPER(CHRTRAN(tcSql, CHR(9) + CHR(10) + CHR(13) + "()", "     ")) + " "
		DO WHILE "  " $ lcU
			lcU = STRTRAN(lcU, "  ", " ")
		ENDDO
		IF " ORDER BY " $ lcU
			RETURN ""
		ENDIF
		lcS = tcSql
		DO WHILE INLIST(RIGHT(lcS, 1), ";", " ", CHR(9), CHR(10), CHR(13))
			lcS = LEFT(lcS, LEN(lcS) - 1)
		ENDDO
		lcOut = ""
		FOR lnI = 1 TO GETWORDCOUNT(tcCols, ",")
			lcC = GETWORDNUM(tcCols, lnI, ",")
			lcOut = lcOut + IIF(lnI = 1, "", ", ") + This.CastExpr(tcEngine, GETWORDNUM(lcC, 1, ":"), SUBSTR(lcC, AT(":", lcC) + 1))
		ENDFOR
		RETURN "SELECT " + lcOut + " FROM (" + lcS + ") AS q"
	ENDPROC

	*-- Lo que no llegó entero en el último QueryWhole, para leerlo: «nombre
	*-- (CAST...)», separado por comas; vacío si todo llegó.
	PROCEDURE ShortText
		LOCAL lcOut, lnI, lcC
		lcOut = ""
		FOR lnI = 1 TO GETWORDCOUNT(This.cLastShort, ",")
			lcC = GETWORDNUM(This.cLastShort, lnI, ",")
			lcOut = lcOut + IIF(lnI = 1, "", ", ") + GETWORDNUM(lcC, 1, ":") + " (" + ;
				This.CastExpr(This.cLastShortEngine, GETWORDNUM(lcC, 1, ":"), SUBSTR(lcC, AT(":", lcC) + 1)) + ")"
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- La línea del aviso de Query... para lo que no llegó entero, vacía si todo
	*-- llegó: los nombres, el motivo y un CAST de ejemplo (el más corto), para que
	*-- quepa en el aviso de pantalla (255 caracteres). En el idioma de FoxDock
	*-- (tlLocal) o en inglés para el log, que lleva además el CAST de cada una.
	PROCEDURE ShortNote
		LPARAMETERS tlLocal
		LOCAL lcKey, lcNames, lcOne, lcCast, lnI, lcC
		IF EMPTY(This.cLastShort)
			RETURN ""
		ENDIF
		lcNames = ""
		lcOne = ""
		FOR lnI = 1 TO GETWORDCOUNT(This.cLastShort, ",")
			lcC = GETWORDNUM(This.cLastShort, lnI, ",")
			lcNames = lcNames + IIF(lnI = 1, "", ", ") + GETWORDNUM(lcC, 1, ":")
			lcCast = This.CastExpr(This.cLastShortEngine, GETWORDNUM(lcC, 1, ":"), SUBSTR(lcC, AT(":", lcC) + 1))
			IF EMPTY(lcOne) OR LEN(lcCast) < LEN(lcOne)
				lcOne = lcCast
			ENDIF
		ENDFOR
		lcKey = IIF(This.cLastShortWhy == "order_by", "data.conn.queryNotWholeOrder", "data.conn.queryNotWholeWrap")
		IF tlLocal
			RETURN This.T(lcKey, lcNames, lcOne)
		ENDIF
		RETURN This.E(lcKey, lcNames, lcOne) + ". All of them: " + This.ShortText()
	ENDPROC

	*-- Lo que escribe el agente (ide_data_db_execute). allowWrite de la conexión
	*-- manda; una sola sentencia de las siete de CheckWrite; un UPDATE o un
	*-- DELETE sin WHERE, un DROP y un TRUNCATE, solo con tlWholeTable. Cada
	*-- sentencia queda hecha al volver (autocommit). Lo que hace y lo que se le
	*-- niega va al log, para que el usuario vea qué tocó el agente. .F. con el
	*-- motivo en cLastError.
	PROCEDURE Execute
		LPARAMETERS tcId, tcSql, tlWholeTable
		LOCAL loC, loG, lcWhy, loDb, lnT0, lnR, lcErr, loErr, lnDs, lcShort
		This.cLastError = ""
		This.cLastCode = ""
		This.cLastStatement = ""
		This.nLastAffected = 0
		This.nLastMs = 0
		lcShort = LEFT(ALLTRIM(CHRTRAN(TRANSFORM(tcSql), CHR(13) + CHR(10) + CHR(9), "   ")), 200)
		loC = This.Find(tcId)
		loG = CREATEOBJECT("DataSqlGuard")
		DO CASE
			CASE ISNULL(loC)
				This.cLastError = This.NoSuch(tcId)
			CASE !loC.lAllowWrite
				This.cLastError = "The connection " + loC.cName + " does not allow writes: allowWrite is false in " + loC.cFile + ;
					". It is the programmer's key, connection by connection: to allow it, set " + ["allowWrite": true] + ;
					" in that connection (FoxDock > Data > Connections > Edit connections...), then FoxDock > Data > Connections > " + ;
					"Reload (Reload plugins would close the connections)."
			OTHERWISE
				loG.cEngine = loC.cEngine
				lcWhy = loG.CheckWrite(tcSql, tlWholeTable)
				IF !EMPTY(lcWhy)
					This.cLastError = "Not run: " + lcWhy + ". Nothing was sent to the server."
				ENDIF
		ENDCASE
		IF !EMPTY(This.cLastError)
			This.oHost.LogWarn("data.connections: the agent was refused a write on '" + LOWER(ALLTRIM(TRANSFORM(tcId))) + "': " + ;
				lcShort + " (" + This.cLastError + ")")
			RETURN .F.
		ENDIF
		IF !This.Ready(loC.cId)
			This.oHost.LogWarn("data.connections: the agent's write on '" + loC.cId + "' was not run: " + This.cLastError)
			RETURN .F.
		ENDIF
		lcShort = LEFT(ALLTRIM(CHRTRAN(loG.cSql, CHR(13) + CHR(10) + CHR(9), "   ")), 200)
		loDb = This.Live(loC.cId)
		lcErr = ""
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lnT0 = SECONDS()
		TRY
			lnR = loDb.Execute(loG.cSql)
		CATCH TO loErr
			lnR = -1
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		This.nLastMs = INT((SECONDS() - lnT0) * 1000)
		SET DATASESSION TO (lnDs)
		IF lnR < 0
			IF !This.CheckLost(loC.cId, EVL(lcErr, loDb.cLastError))
				This.cLastError = "The statement on '" + loC.cId + "' failed: " + EVL(lcErr, loDb.cLastError)
			ENDIF
			This.oHost.LogWarn("data.connections: the agent's write on '" + loC.cId + "' failed: " + lcShort + " (" + This.cLastError + ")")
			RETURN .F.
		ENDIF
		This.cLastStatement = loG.cStatement
		This.nLastAffected = lnR
		This.oHost.Log("data.connections: the agent wrote on '" + loC.cId + "': " + lcShort + " (" + TRANSFORM(lnR) + " row(s), " + ;
			TRANSFORM(This.nLastMs) + " ms)")
		RETURN .T.
	ENDPROC

	*-- Las filas de un cursor de la sesión 1 en JSON, como ide_data_to_json
	*-- (DataJson.Walk: el mismo tratamiento de cada tipo). Devuelve el texto
	*-- del array "rows" y cuántas, en nLastRows.
	PROCEDURE RowsJson
		LPARAMETERS tcAlias, tnMax
		LOCAL loT, loJ, loR, lcRows
		loT = CREATEOBJECT("DataTable")
		loJ = NEWOBJECT("DataJson", This.Home() + "DataJson.prg", "", This.oHost)
		lcRows = ""
		TRY
			IF loT.Open(tcAlias, .F.)
				loR = loJ.Walk(loT, tnMax, "", 0)
				lcRows = STRTRAN(loR.cClip, "," + CRLF, ",")
				This.nLastRows = loR.nDone
			ELSE
				This.cLastError = loT.cError
			ENDIF
		FINALLY
			loT.Close()
		ENDTRY
		RETURN "[" + lcRows + "]"
	ENDPROC

	*--------------------------------------------------------------
	* El menú.
	*--------------------------------------------------------------
	PROCEDURE FillMenu
		LPARAMETERS tcPopup, tnBar
		LOCAL loP, loC, lnI, lnB, lcSub, lcCaption, lcCon, llOn
		loP = This.Plugin()
		lcCon = tcPopup + "C"
		tnBar = loP.DefineBar(tcPopup, tnBar + 1, "", "", "", "")
		*-- En el idioma de FoxDock (DataStrings.prg).
		tnBar = loP.DefineSubmenu(tcPopup, tnBar + 1, This.T("data.conn.menu"), lcCon)
		lnB = 0
		lnI = 0
		FOR EACH loC IN This.oList FOXOBJECT
			lnI = lnI + 1
			lcSub = lcCon + TRANSFORM(lnI)
			*-- El título dice si está conectada, y Connect o Disconnect, el que toca.
			*-- El menú se rehace al conectar, al desconectar, al perderse una y al
			*-- recargar.
			llOn = This.IsConnected(loC.cId)
			lcCaption = CHRTRAN(loC.cName, "[]\", "()/") + IIF(loC.cOrigin == "project", This.T("data.conn.project"), "") + ;
				IIF(llOn, This.T("data.conn.connectedMark"), "")
			lnB = loP.DefineSubmenu(lcCon, lnB + 1, lcCaption, lcSub)
			=loP.DefineBar(lcSub, 1, This.T("data.conn.connect"), "DbConnect", loC.cId, This.T("data.conn.connect.message", loC.cName, loC.cEngine), llOn)
			=loP.DefineBar(lcSub, 2, This.T("data.conn.disconnect"), "DbDisconnect", loC.cId, This.T("data.conn.disconnect.message", loC.cName), !llOn)
			=loP.DefineBar(lcSub, 3, "", "", "", "")
			=loP.DefineBar(lcSub, 4, This.T("data.conn.explore"), "DbExplore", loC.cId, This.T("data.conn.explore.message", loC.cName))
			=loP.DefineBar(lcSub, 5, This.T("data.conn.query"), "DbQuery", loC.cId, This.T("data.conn.query.message"))
		ENDFOR
		IF lnI = 0
			lnB = loP.DefineBar(lcCon, lnB + 1, This.T("data.conn.none"), "DbEdit", "", This.T("data.conn.none.message"))
		ENDIF
		lnB = loP.DefineBar(lcCon, lnB + 1, "", "", "", "")
		lnB = loP.DefineBar(lcCon, lnB + 1, This.T("data.conn.edit"), "DbEdit", "", This.T("data.conn.edit.message"))
		lnB = loP.DefineBar(lcCon, lnB + 1, This.T("data.conn.reload"), "DbReload", "", This.T("data.conn.reload.message"))
		RETURN tnBar
	ENDPROC

	PROCEDURE GetAgentTools
		LPARAMETERS toTools
		toTools.Add(CREATEOBJECT("IdeDataDbConnectionsTool"))
		toTools.Add(CREATEOBJECT("IdeDataDbTablesTool"))
		toTools.Add(CREATEOBJECT("IdeDataDbDescribeTool"))
		toTools.Add(CREATEOBJECT("IdeDataDbQueryTool"))
		toTools.Add(CREATEOBJECT("IdeDataDbExecuteTool"))
		RETURN 5
	ENDPROC

	*--------------------------------------------------------------
	* Las barras. Ningún diálogo de VFP: lo que pide algo, un formulario propio
	* modeless; lo que pasa, a la barra de estado y al log.
	*--------------------------------------------------------------
	PROCEDURE ConnectBar
		LPARAMETERS tcId
		LOCAL loC
		loC = This.Find(tcId)
		DO CASE
			CASE ISNULL(loC)
				This.oHost.NotifyQuoted("data.said", This.NoSuch(tcId))
			CASE This.IsConnected(loC.cId)
				This.oHost.NotifyKey("data.conn.already", loC.cName)
			CASE This.NeedsSecret(loC) AND !This.HasSavedSecret(loC.cId)
				This.ShowForm("DataConnectForm", loC)
			CASE This.Connect(loC.cId, "", .F.)
				This.oHost.NotifyKey("data.conn.connected", loC.cName)
			OTHERWISE
				This.oHost.NotifyQuoted("data.said", This.cLastError)
				IF This.lNeedsConnectBar
					This.ShowForm("DataConnectForm", loC)
				ENDIF
		ENDCASE
	ENDPROC

	PROCEDURE DisconnectBar
		LPARAMETERS tcId
		LOCAL loC
		loC = This.Find(tcId)
		DO CASE
			CASE ISNULL(loC)
				This.oHost.NotifyQuoted("data.said", This.NoSuch(tcId))
			CASE This.Disconnect(loC.cId)
				This.oHost.NotifyKey("data.conn.disconnected", loC.cName)
			OTHERWISE
				This.oHost.NotifyKey("data.conn.notConnected", loC.cName)
		ENDCASE
	ENDPROC

	*-- Conectada, o lo dice (y abre Connect... si falta la contraseña).
	PROTECTED PROCEDURE BarReady
		LPARAMETERS tcId
		LOCAL loC
		loC = This.Find(tcId)
		IF ISNULL(loC)
			This.oHost.NotifyQuoted("data.said", This.NoSuch(tcId))
			RETURN .F.
		ENDIF
		IF This.Ready(loC.cId)
			RETURN .T.
		ENDIF
		This.oHost.NotifyQuoted("data.said", This.cLastError)
		IF This.lNeedsConnectBar
			This.ShowForm("DataConnectForm", loC)
		ENDIF
		RETURN .F.
	ENDPROC

	*-- La ventana de la conexión. Si no está conectada, conecta como las demás
	*-- barras (con el formulario de la contraseña si hace falta: entonces no
	*-- abre nada, y Explore... otra vez la abre). Una por conexión: si ya está
	*-- abierta, se trae delante. Devuelve la ventana, o .NULL.
	PROCEDURE ExploreBar
		LPARAMETERS tcId
		LOCAL loC, loF
		IF !This.BarReady(tcId)
			RETURN .NULL.
		ENDIF
		loC = This.Find(tcId)
		loF = This.ExploreForm(loC.cId)
		IF ISNULL(loF)
			loF = This.ShowForm("DataExploreForm", loC)
		ELSE
			loF.Show()
		ENDIF
		RETURN loF
	ENDPROC

	*-- La ventana de Explore... abierta de tcId, o .NULL.
	PROCEDURE ExploreForm
		LPARAMETERS tcId
		RETURN This.FormOf("DataExploreForm", tcId)
	ENDPROC

	*-- Una ventana abierta de la clase tcClass y la conexión tcId, o .NULL.
	PROCEDURE FormOf
		LPARAMETERS tcClass, tcId
		LOCAL loF
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		FOR EACH loF IN This.oForms FOXOBJECT
			IF LOWER(loF.Class) == LOWER(tcClass) AND loF.cConnId == tcId
				RETURN loF
			ENDIF
		ENDFOR
		RETURN .NULL.
	ENDPROC

	*-- Cierra la ventana de Explore... de tcId ("" = todas) y los cursores que
	*-- abrió, y el log dice por qué; y con ella las de Export... y Create
	*-- view... de esa conexión. Devuelve cuántas de Explore... cerró.
	PROCEDURE CloseExplore
		LPARAMETERS tcId, tcWhy
		LOCAL loF, lnN, lnI, laF[1], lnK, laK[1]
		IF VARTYPE(This.oForms) # "O"
			RETURN 0
		ENDIF
		tcId = LOWER(ALLTRIM(TRANSFORM(tcId)))
		lnK = 0
		FOR EACH loF IN This.oForms FOXOBJECT
			IF INLIST(LOWER(loF.Class), "dataexportform", "dataviewform", "datascriptform") AND (EMPTY(tcId) OR loF.cConnId == tcId)
				lnK = lnK + 1
				DIMENSION laK[lnK]
				laK[lnK] = loF
			ENDIF
		ENDFOR
		FOR lnI = 1 TO lnK
			loF = laK[lnI]
			loF.Release()
		ENDFOR
		loF = .NULL.
		laK = .NULL.
		lnN = 0
		FOR EACH loF IN This.oForms FOXOBJECT
			IF LOWER(loF.Class) == "dataexploreform" AND (EMPTY(tcId) OR loF.cConnId == tcId)
				lnN = lnN + 1
				DIMENSION laF[lnN]
				laF[lnN] = loF
			ENDIF
		ENDFOR
		loF = .NULL.
		FOR lnI = 1 TO lnN
			loF = laF[lnI]
			loF.CloseCursors()
			This.oHost.Log("data.connections: Explore... of '" + loF.cConnId + "' closed: " + tcWhy)
			loF.Release()
		ENDFOR
		loF = .NULL.
		laF = .NULL.
		RETURN lnN
	ENDPROC

	*-- Lo que dice la ventana: en su cuadro, en la barra de estado y en el log
	*-- (Notify lo escribe). tcLog, lo mismo en inglés para el log. Sin tcLog,
	*-- tcText es un motivo que ya está en inglés (cLastError, de la lógica que
	*-- comparten la ventana y las tools): en la ventana y en el aviso sale
	*-- citado (Quoted); en el log, tal cual.
	PROCEDURE ExploreSay
		LPARAMETERS toF, tcText, tcLog
		LOCAL lcShown
		lcShown = IIF(VARTYPE(tcLog) == "C", tcText, This.oHost.Quoted(tcText))
		IF VARTYPE(toF) == "O"
			toF.edtSay.Value = lcShown
		ENDIF
		This.oHost.Notify(This.T("data.said", lcShown), "Data: " + IIF(VARTYPE(tcLog) == "C", tcLog, tcText))
	ENDPROC

	*-- Una cadena de la ventana por su clave, en el idioma de FoxDock y en inglés en el log.
	PROCEDURE ExploreSayKey
		LPARAMETERS toF, tcKey, tv1, tv2, tv3, tv4, tv5, tv6
		This.ExploreSay(toF, This.T(tcKey, tv1, tv2, tv3, tv4, tv5, tv6), This.E(tcKey, tv1, tv2, tv3, tv4, tv5, tv6))
	ENDPROC

	*-- La cadena en el idioma de FoxDock, y en inglés.
	PROCEDURE T
		LPARAMETERS tcKey, tv1, tv2, tv3, tv4, tv5, tv6
		RETURN This.oHost.Translate(tcKey, tv1, tv2, tv3, tv4, tv5, tv6)
	ENDPROC

	PROCEDURE E
		LPARAMETERS tcKey, tv1, tv2, tv3, tv4, tv5, tv6
		RETURN This.oHost.TranslateEn(tcKey, tv1, tv2, tv3, tv4, tv5, tv6)
	ENDPROC

	*-- Las bases del servidor que la conexión puede abrir, en tcCursor (sesión 1,
	*-- columna name): GetDatabases de FoxRemote. Devuelve cuántas, o -1 con el
	*-- motivo en cLastError. En SQLite y Firebird la base es el fichero: 0, y
	*-- ningún cursor (la ventana enseña el fichero con el combo deshabilitado).
	PROCEDURE Databases
		LPARAMETERS tcId, tcCursor
		LOCAL loC
		loC = This.Find(tcId)
		DO CASE
			CASE ISNULL(loC)
				This.cLastError = This.NoSuch(tcId)
				RETURN -1
			CASE INLIST(loC.cEngine, "sqlite", "firebird")
				RETURN 0
		ENDCASE
		RETURN This.ReadNames(loC.cId, "GetDatabases", tcCursor, "the databases")
	ENDPROC

	*-- Las tablas y las vistas de la base actual, en tcCursor (sesión 1: name, y
	*-- type «table» o «view»): GetObjects de FoxRemote (GetTables da solo
	*-- tablas). Devuelve cuántas, o -1 con el motivo en cLastError.
	PROCEDURE TablesAndViews
		LPARAMETERS tcId, tcCursor
		LOCAL loC
		loC = This.Find(tcId)
		IF ISNULL(loC)
			This.cLastError = This.NoSuch(tcId)
			RETURN -1
		ENDIF
		RETURN This.ReadNames(loC.cId, "GetObjects", tcCursor, "the tables and views")
	ENDPROC

	*-- tcMethod de FoxRemote (GetDatabases o GetObjects) en tcCursor, sesión 1.
	*-- -1 con el motivo en cLastError.
	PROTECTED PROCEDURE ReadNames
		LPARAMETERS tcId, tcMethod, tcCursor, tcWhat
		LOCAL loDb, lnDs, llOk, lnN, lcCmd, lcErr, loErr
		IF !This.Ready(tcId)
			RETURN -1
		ENDIF
		loDb = This.Live(tcId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcCmd = "loDb." + tcMethod + "(tcCursor)"
		lcErr = ""
		TRY
			llOk = &lcCmd
		CATCH TO loErr
			llOk = .F.
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		lnN = IIF(llOk AND USED(tcCursor), RECCOUNT(tcCursor), -1)
		SET DATASESSION TO (lnDs)
		IF lnN < 0 AND !This.CheckLost(tcId, EVL(lcErr, loDb.cLastError))
			This.cLastError = tcWhat + " of '" + tcId + "' could not be read: " + EVL(lcErr, loDb.cLastError)
			This.cLastError = UPPER(LEFT(This.cLastError, 1)) + SUBSTR(This.cLastError, 2)
		ENDIF
		RETURN lnN
	ENDPROC

	*-- El nombre de una tabla o vista de la base actual tal como lo da el
	*-- servidor, o "" con el motivo en cLastError. Así no llega al SQL nada que
	*-- no sea el nombre de algo que existe.
	PROCEDURE ObjectName
		LPARAMETERS tcId, tcName
		LOCAL lcCur, lcName, lnDs
		lcCur = "FDO" + SYS(2015)
		IF This.TablesAndViews(tcId, lcCur) < 0
			RETURN ""
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcName = ""
		SELECT (lcCur)
		LOCATE FOR UPPER(ALLTRIM(name)) == UPPER(ALLTRIM(tcName))
		IF FOUND()
			lcName = ALLTRIM(name)
		ENDIF
		USE IN (lcCur)
		SET DATASESSION TO (lnDs)
		IF EMPTY(lcName)
			This.cLastError = "There is no table or view '" + ALLTRIM(tcName) + "' in the database " + This.CurrentDatabase(tcId) + ;
				" of '" + tcId + "'."
		ENDIF
		RETURN lcName
	ENDPROC

	*-- La conexión a otra base del mismo servidor, con UseDatabase de FoxRemote,
	*-- que desconecta y vuelve a conectar. El objeto ya no tiene la contraseña
	*-- (se borra al conectar), y sin ella falla y deja la conexión cerrada: se le
	*-- da la guardada solo mientras dura, y sin una guardada no se intenta. Si
	*-- falla, se vuelve a la base de antes; si ni eso, la conexión se da por
	*-- cerrada (Disconnect: la ventana se va).
	PROCEDURE UseDatabase
		LPARAMETERS tcId, tcDatabase
		LOCAL loC, loDb, lcPwd, llOk, lcWhy, lcOld
		This.cLastError = ""
		tcDatabase = ALLTRIM(TRANSFORM(tcDatabase))
		loC = This.Find(tcId)
		DO CASE
			CASE ISNULL(loC)
				This.cLastError = This.NoSuch(tcId)
				RETURN .F.
			CASE INLIST(loC.cEngine, "sqlite", "firebird")
				This.cLastError = "In " + loC.cEngine + " the database is the file of the connection: there is no other to change to."
				RETURN .F.
			CASE !This.IsConnected(loC.cId)
				This.cLastError = "'" + loC.cId + "' is not connected: Connect... first."
				RETURN .F.
		ENDCASE
		lcOld = This.CurrentDatabase(loC.cId)
		IF LOWER(lcOld) == LOWER(tcDatabase)
			RETURN .T.
		ENDIF
		lcPwd = ""
		IF This.NeedsSecret(loC)
			lcPwd = This.ReadSecret(loC.cId)
			IF EMPTY(lcPwd)
				This.cLastError = "Changing the database opens a new connection to the server, and that needs the password of '" + ;
					loC.cUser + "', which FoxDock did not keep (Remember was not marked in Connect...). Disconnect, and Connect... " + ;
					"with Remember; or put the database in connections.json. " + loC.cName + " is still in " + lcOld + "."
				This.oHost.LogWarn("data.connections: " + This.cLastError)
				RETURN .F.
			ENDIF
		ENDIF
		loDb = This.Live(loC.cId)
		loDb.cPassword = lcPwd
		llOk = loDb.UseDatabase(tcDatabase)
		lcWhy = IIF(llOk, "", This.Scrub(loDb.cLastError, lcPwd))
		IF !llOk AND loDb.nHandle < 1
			*-- Al fallar, la deja cerrada, con la base de antes en cDatabase.
			=loDb.Connect()
		ENDIF
		loDb.cPassword = ""
		IF llOk
			This.oHost.Log("data.connections: '" + loC.cId + "' is now in the database " + This.CurrentDatabase(loC.cId) + ;
				" (it was in " + lcOld + ")")
			RETURN .T.
		ENDIF
		IF loDb.nHandle < 1
			This.cLastError = "Changing '" + loC.cId + "' to the database " + tcDatabase + " failed, and it could not connect " + ;
				"again to " + lcOld + ": " + lcWhy + " The connection is closed: Connect... again."
			This.oHost.LogWarn("data.connections: " + This.cLastError)
			This.Disconnect(loC.cId)
		ELSE
			This.cLastError = "Changing '" + loC.cId + "' to the database " + tcDatabase + " failed: " + lcWhy + " " + ;
				loC.cName + " is still in " + This.CurrentDatabase(loC.cId) + "."
			This.oHost.LogWarn("data.connections: " + This.cLastError)
		ENDIF
		RETURN .F.
	ENDPROC

	*-- Columns de Explore...: las columnas de tcName (de GetColumns: name, type,
	*-- width, decimals, nullable, primary_key) en un BROWSE de solo lectura,
	*-- c_<id>_<tabla>_columns. Lo dice en la ventana toF.
	PROCEDURE ExploreColumns
		LPARAMETERS toF, tcName
		LOCAL loC, loDb, lcName, lcCur, lcTmp, lnDs, llOk, lcKey, lnN, lcTitle
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcName)
		IF EMPTY(lcName)
			This.ExploreSay(toF, This.cLastError)
			RETURN .F.
		ENDIF
		loDb = This.Live(loC.cId)
		lcCur = This.CursorName(loC.cId, lcName + "_columns")
		lcTmp = "FDC" + SYS(2015)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		llOk = This.BinaryRead(loDb, "columns", lcName, lcTmp)
		IF llOk
			lcKey = loDb.GetPrimaryKey(lcName)
			lnN = RECCOUNT(lcTmp)
			This.ReadOnlyCursor(lcTmp, lcCur)
		ENDIF
		SET DATASESSION TO (lnDs)
		IF !llOk
			This.ExploreSay(toF, This.T("data.columns.failed", lcName, This.oHost.Quoted(loDb.cLastError)), ;
				This.E("data.columns.failed", lcName, loDb.cLastError))
			RETURN .F.
		ENDIF
		toF.Keep(lcCur)
		lcTitle = This.T("data.columns.title", lcName, loC.cName, ;
			IIF(EMPTY(lcKey), This.T("data.columns.titleNoKey"), This.T("data.columns.titleKey", lcKey)))
		This.Browse(lcCur, lcTitle)
		This.ExploreSay(toF, This.T("data.columns.said", lcName, lnN, IIF(EMPTY(lcKey), This.T("data.columns.noKey"), ;
			This.T("data.columns.key", lcKey)), lcCur), This.E("data.columns.said", lcName, lnN, ;
			IIF(EMPTY(lcKey), This.E("data.columns.noKey"), This.E("data.columns.key", lcKey)), lcCur))
		RETURN .T.
	ENDPROC

	*-- Browse de Explore...: las tnLimit primeras filas de tcName (0 = todas) en
	*-- un BROWSE de solo lectura, c_<id>_<tabla>, con un título que dice si
	*-- cortó. Pasa por Query (la guarda y el tope de filas).
	PROCEDURE ExploreBrowse
		LPARAMETERS toF, tcName, tnLimit
		LOCAL loC, lcName, lcCur, lcTmp, lnDs, lcTitle
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcName)
		IF EMPTY(lcName)
			This.ExploreSay(toF, This.cLastError)
			RETURN .F.
		ENDIF
		tnLimit = MAX(INT(tnLimit), 0)
		lcCur = This.CursorName(loC.cId, lcName)
		lcTmp = "FDB" + SYS(2015)
		IF !This.TableSelect(loC.cId, lcName, tnLimit, lcTmp)
			This.ExploreSay(toF, This.cLastError)
			RETURN .F.
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		This.ReadOnlyCursor(lcTmp, lcCur)
		SET DATASESSION TO (lnDs)
		toF.Keep(lcCur)
		lcTitle = This.T("data.browse.title", lcName, loC.cName, IIF(This.lLastTruncated, ;
			This.T("data.browse.first", This.nLastRows, tnLimit), ;
			This.T("data.browse.rows", This.nLastRows) + IIF(tnLimit = 0, This.T("data.browse.all"), "")))
		This.Browse(lcCur, lcTitle)
		This.ExploreSay(toF, This.T("data.browse.said", lcTitle, lcCur), This.E("data.browse.said", ;
			This.E("data.browse.title", lcName, loC.cName, IIF(This.lLastTruncated, This.E("data.browse.first", This.nLastRows, tnLimit), ;
			This.E("data.browse.rows", This.nLastRows) + IIF(tnLimit = 0, This.E("data.browse.all"), ""))), lcCur))
		RETURN .T.
	ENDPROC

	*-- To object: las filas de tcAlias (sesión 1) en una Collection, un objeto
	*-- por fila (SCATTER NAME ... MEMO), en la variable PUBLIC tcVar, para
	*-- usarlas desde la ventana de comandos: desde un método solo una PUBLIC
	*-- llega allí (SetVar deja una privada del método). No pisa nada: un nombre
	*-- que no vale o una variable que ya existe se niegan. El cursor no se
	*-- mueve. tcFrom, lo que dice el panel. .T. si la hizo.
	PROCEDURE ToObject
		LPARAMETERS toF, tcAlias, tcVar, tcFrom
		LOCAL lnDs, lnSel, loC, loR, lnRec, lnN, lcFirst
		tcVar = ALLTRIM(TRANSFORM(tcVar))
		DO CASE
			CASE !This.IsVarName(tcVar)
				This.ToObjectSay(toF, "data.object.badName", tcVar)
				RETURN .F.
			CASE TYPE(tcVar) # "U"
				This.ToObjectSay(toF, "data.object.exists", tcVar)
				RETURN .F.
		ENDCASE
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		IF EMPTY(tcAlias) OR !USED(tcAlias) OR RECCOUNT(tcAlias) = 0
			SET DATASESSION TO (lnDs)
			This.ToObjectSay(toF, "data.object.noRows", EVL(tcFrom, tcAlias))
			RETURN .F.
		ENDIF
		lnSel = SELECT()
		SELECT (tcAlias)
		lnRec = IIF(EOF(), 0, RECNO())
		lcFirst = LOWER(FIELD(1))
		loC = CREATEOBJECT("Collection")
		SCAN
			SCATTER NAME loR MEMO
			loC.Add(loR)
		ENDSCAN
		IF lnRec > 0
			GO lnRec
		ENDIF
		SELECT (lnSel)
		SET DATASESSION TO (lnDs)
		lnN = loC.Count
		PUBLIC &tcVar
		&tcVar = loC
		This.oHost.Log("data.connections: " + tcVar + " (PUBLIC): " + TRANSFORM(lnN) + " rows of " + tcFrom)
		This.ToObjectSay(toF, "data.object.made", tcVar, lnN, tcFrom, lcFirst)
		RETURN .T.
	ENDPROC

	*-- Lo que dice: en el panel de Explore..., o en la línea de estado de Query.
	PROCEDURE ToObjectSay
		LPARAMETERS toF, tcKey, tv1, tv2, tv3, tv4
		IF PEMSTATUS(toF, "edtSay", 5)
			This.ExploreSayKey(toF, tcKey, tv1, tv2, tv3, tv4)
		ELSE
			toF.lblError.Caption = This.T(tcKey, tv1, tv2, tv3, tv4)
			This.oHost.Notify(This.T("data.said", toF.lblError.Caption), "Data: " + This.E(tcKey, tv1, tv2, tv3, tv4))
		ENDIF
	ENDPROC

	*-- Un nombre de variable de VFP: letras, dígitos y _, empezando por letra o _.
	PROCEDURE IsVarName
		LPARAMETERS tcName
		RETURN !EMPTY(tcName) AND LEN(tcName) <= 128 AND (ISALPHA(tcName) OR LEFT(tcName, 1) == "_") AND ;
			LEN(CHRTRAN(LOWER(tcName), "abcdefghijklmnopqrstuvwxyz0123456789_", "")) = 0
	ENDPROC

	*-- El nombre que propone «A objeto»: lo + el de la tabla o el cursor (loG10_cl).
	PROCEDURE ObjectVarName
		LPARAMETERS tcFrom
		LOCAL lcN
		lcN = CHRTRAN(ALLTRIM(TRANSFORM(tcFrom)), CHRTRAN(LOWER(ALLTRIM(TRANSFORM(tcFrom))), "abcdefghijklmnopqrstuvwxyz0123456789_", ""), "")
		RETURN "lo" + UPPER(LEFT(lcN, 1)) + LOWER(SUBSTR(lcN, 2))
	ENDPROC

	*-- To object en Explore...: las filas que enseña Browse (su tope), a la variable.
	PROCEDURE ExploreToObject
		LPARAMETERS toF, tcName, tnLimit, tcVar
		LOCAL lcName, lcTmp, llOk, lnDs
		lcName = This.ObjectName(toF.cConnId, tcName)
		IF EMPTY(lcName)
			This.ExploreSay(toF, This.cLastError)
			RETURN .F.
		ENDIF
		lcTmp = "FDO" + SYS(2015)
		IF !This.TableSelect(toF.cConnId, lcName, MAX(INT(tnLimit), 0), lcTmp)
			This.ExploreSay(toF, This.cLastError)
			RETURN .F.
		ENDIF
		llOk = This.ToObject(toF, lcTmp, tcVar, lcName)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		IF USED(lcTmp)
			USE IN (lcTmp)
		ENDIF
		SET DATASESSION TO (lnDs)
		RETURN llOk
	ENDPROC

	*-- Las filas de una tabla o vista (tcName, como la da el servidor) en
	*-- tcAlias, con tnMax como mucho (0 = todas), por Query. Ordenadas por la
	*-- clave primaria si la tiene, para que «las N primeras» sean siempre las
	*-- mismas (sin ORDER BY, SQL Server las da en cualquier orden). En SQL
	*-- Server, un (n)varchar(max) llega como C(0), vacío: se vuelve a leer con
	*-- CAST(CAST(x AS VARCHAR(MAX)) AS TEXT), como hace el Open() de FoxRemote;
	*-- y un varbinary(max), como Q(0), vacío: con CAST(x AS IMAGE), que llega
	*-- como W. En Firebird, las columnas OCTETS (FbOctets) llegan como texto: se
	*-- vuelven a leer con CAST(x AS BLOB SUB_TYPE BINARY), que llega como W con
	*-- sus bytes y sin el relleno de un C. En MySQL y MariaDB, un LONGTEXT o un
	*-- JSON llega como C(255) cortado: se vuelve a leer con CAST(x AS CHAR(16777215)).
	PROCEDURE TableSelect
		LPARAMETERS tcId, tcName, tnMax, tcAlias
		LOCAL loC, loDb, lcKey, lcOrder, lcCols, llLong, laF[1], lnN, lnI, lnDs, lcFrom, lcK, loErr, lcOct, lcCast
		loC = This.Find(tcId)
		IF !This.Ready(loC.cId)
			RETURN .F.
		ENDIF
		loDb = This.Live(loC.cId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			lcKey = loDb.GetPrimaryKey(tcName)
		CATCH TO loErr
			*-- Con la conexión muerta, el error de VFP no sale de aquí: el Query de
			*-- abajo falla y pasa por CheckLost.
			lcKey = ""
		ENDTRY
		SET DATASESSION TO (lnDs)
		lcOrder = ""
		FOR lnI = 1 TO GETWORDCOUNT(lcKey, ",")
			lcK = ALLTRIM(GETWORDNUM(lcKey, lnI, ","))
			lcOrder = lcOrder + IIF(EMPTY(lcOrder), " ORDER BY ", ", ") + This.Quoted(loC.cEngine, lcK)
		ENDFOR
		lcFrom = " FROM " + This.Quoted(loC.cEngine, tcName) + lcOrder
		IF !This.Query(loC.cId, "SELECT *" + lcFrom, tnMax, tcAlias)
			RETURN .F.
		ENDIF
		IF !INLIST(loC.cEngine, "sqlserver", "firebird", "mysql", "mariadb")
			RETURN .T.
		ENDIF
		lcOct = This.CastList(loC.cEngine, loDb.nHandle, tcName)
		IF EMPTY(lcOct) AND !(loC.cEngine == "sqlserver")
			RETURN .T.
		ENDIF
		SET DATASESSION TO 1
		lnN = AFIELDS(laF, tcAlias)
		SET DATASESSION TO (lnDs)
		lcCols = ""
		llLong = .F.
		FOR lnI = 1 TO lnN
			lcCast = This.ReadCast(loC.cEngine, laF[lnI, 2], laF[lnI, 3], LOWER(laF[lnI, 1]), lcOct)
			llLong = llLong OR !EMPTY(lcCast)
			lcCols = lcCols + IIF(lnI = 1, "", ", ") + This.CastExpr(loC.cEngine, laF[lnI, 1], lcCast)
		ENDFOR
		IF !llLong
			RETURN .T.
		ENDIF
		RETURN This.Query(loC.cId, "SELECT " + lcCols + lcFrom, tnMax, tcAlias)
	ENDPROC

	*-- El botón Create view... de Explore...: la ventanita de la tabla o vista elegida.
	PROCEDURE ViewBar
		LPARAMETERS toF, tcName
		LOCAL loC, lcName
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcName)
		IF EMPTY(lcName)
			This.ExploreSay(toF, This.cLastError)
			RETURN .NULL.
		ENDIF
		RETURN This.ShowForm("DataViewForm", loC, lcName)
	ENDPROC

	*-- Los .dbc que propone Create view...: el abierto (DBC() de la sesión 1) y
	*-- los de la carpeta del proyecto, o, sin proyecto, de la carpeta de datos
	*-- de FoxDock; el primero es el de entrada, y si no hay ninguno, uno nuevo
	*-- <conexión>.dbc en esa carpeta. Separados por CHR(13).
	PROCEDURE DbcChoices
		LPARAMETERS tcId
		LOCAL lcDir, lcOut, lnDs, lcOpen, laD[1], lnN, lnI, loP
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcOpen = DBC()
		SET DATASESSION TO (lnDs)
		lcDir = JUSTPATH(This.ProjectFile())
		IF EMPTY(lcDir)
			loP = This.Plugin()
			lcDir = IIF(ISNULL(loP), "", loP.OutDir())
		ENDIF
		lcDir = ADDBS(lcDir)
		lcOut = IIF(EMPTY(lcOpen), "", lcOpen + CHR(13))
		lnN = ADIR(laD, lcDir + "*.dbc")
		FOR lnI = 1 TO lnN
			IF !(UPPER(lcDir + laD[lnI, 1]) == UPPER(lcOpen))
				lcOut = lcOut + lcDir + LOWER(laD[lnI, 1]) + CHR(13)
			ENDIF
		ENDFOR
		IF EMPTY(lcOut)
			lcOut = lcDir + LOWER(CHRTRAN(tcId, CHRTRAN(LOWER(tcId), "abcdefghijklmnopqrstuvwxyz0123456789_", ""), "")) + ".dbc" + CHR(13)
		ENDIF
		RETURN lcOut
	ENDPROC

	*-- Lo que hay con ese nombre en el .dbc: "view", "table" o "". En la
	*-- sesión 1; no deja abierto el .dbc si no lo estaba, ni cambia el actual.
	PROCEDURE DbcHas
		LPARAMETERS tcDbc, tcName
		LOCAL lcOut, lnDs, lcOld, llOpened, loErr
		lcOut = ""
		tcDbc = ALLTRIM(TRANSFORM(tcDbc))
		tcName = LOWER(ALLTRIM(TRANSFORM(tcName)))
		IF EMPTY(tcName) OR !(LOWER(JUSTEXT(tcDbc)) == "dbc") OR !FILE(tcDbc)
			RETURN lcOut
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcOld = DBC()
		llOpened = .F.
		TRY
			IF DBUSED(tcDbc)
				SET DATABASE TO (tcDbc)
			ELSE
				OPEN DATABASE (tcDbc)
				llOpened = .T.
			ENDIF
			lcOut = ICASE(INDBC(tcName, "VIEW"), "view", INDBC(tcName, "TABLE"), "table", "")
		CATCH TO loErr
			lcOut = ""
		ENDTRY
		IF llOpened AND DBUSED(tcDbc)
			SET DATABASE TO (tcDbc)
			CLOSE DATABASE
		ENDIF
		IF !EMPTY(lcOld) AND DBUSED(lcOld)
			SET DATABASE TO (lcOld)
		ENDIF
		SET DATASESSION TO (lnDs)
		RETURN lcOut
	ENDPROC

	*-- Create view... de la ventanita toF: la vista tcView de tcTable en tcDbc
	*-- (lo crea si no está), con las columnas tcCols (separadas por comas, como
	*-- las da el servidor), tcWhere y tlUpdatable. tlReplace (Reemplazar): una
	*-- vista con ese nombre se borra y se hace otra vez. .T. si la hizo.
	PROCEDURE CreateView
		LPARAMETERS toF, tcTable, tcDbc, tcView, tcCols, tcWhere, tlUpdatable, tlReplace
		LOCAL loC, loDb, lcName, lcWhy, lcKey, lcCs, lcNo, lcConn, lcSql, lnI, lcCol, lnDs, lcOldDbc, llOpened, llMap, lcCmd, llBin
		LOCAL loErr, lcErr, lnH, laF[1], lnN, lcField, llPwd, lnTry, lcMemo, llExists, llServer, llInUse, llReplaced, lcDsn, lcUse
		LOCAL lcProbe, llProbe, laE[1], lcTypes, lcList, lcJson
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcTable)
		tcView = LOWER(ALLTRIM(tcView))
		tcDbc = ALLTRIM(tcDbc)
		tcWhere = ALLTRIM(CHRTRAN(tcWhere, CHR(13) + CHR(10) + CHR(9), "   "))
		*-- lcWhy, la clave de la cadena (o el cLastError, en inglés, entre «!»).
		DO CASE
			CASE EMPTY(lcName)
				lcWhy = "!" + This.cLastError
			CASE EMPTY(tcView) OR !BETWEEN(LEFT(tcView, 1), "a", "z") OR ;
					LEN(CHRTRAN(tcView, "abcdefghijklmnopqrstuvwxyz0123456789_", "")) > 0 OR LEN(tcView) > 128
				lcWhy = "data.view.badName"
			CASE !(LOWER(JUSTEXT(tcDbc)) == "dbc") OR !DIRECTORY(JUSTPATH(tcDbc), 1)
				lcWhy = "data.view.badDbc"
			CASE EMPTY(tcCols)
				lcWhy = "data.view.noColumns"
			OTHERWISE
				lcWhy = ""
		ENDCASE
		IF !EMPTY(lcWhy)
			IF LEFT(lcWhy, 1) == "!"
				This.ExploreSay(toF, SUBSTR(lcWhy, 2))
			ELSE
				This.ExploreSayKey(toF, lcWhy, tcView)
			ENDIF
			RETURN .F.
		ENDIF
		loDb = This.Live(loC.cId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcKey = IIF(tlUpdatable, loDb.GetPrimaryKey(lcName), "")
		*-- La cadena de la conexión viva (lleva PWD) y la misma sin él.
		lcCs = SQLGETPROP(loDb.nHandle, "ConnectString")
		lcNo = This.WithoutPassword(lcCs)
		llPwd = !(lcNo == lcCs)
		*-- La cadena con PWD no se escribe nunca en el .dbc: cada escritura de la
		*-- conexión de un .dbc abierto va a un bloque nuevo del .DCT y el viejo se
		*-- queda. Mientras se hace la vista, la conexión dice FILEDSN= de un .dsn
		*-- temporal con la contraseña, que se borra al acabar.
		lcDsn = ""
		lcUse = lcCs
		lcSql = ""
		lcTypes = This.ColumnTypes(loDb, lcName)
		lcList = This.CastList(loC.cEngine, loDb.nHandle, lcName)
		lcJson = IIF(loC.cEngine == "mysql" AND tlUpdatable, This.MyLongText(loDb.nHandle, lcName, "'json'"), "")
		FOR lnI = 1 TO GETWORDCOUNT(tcCols, ",")
			lcCol = ALLTRIM(GETWORDNUM(tcCols, lnI, ","))
			lcSql = lcSql + IIF(lnI = 1, "", ", ") + This.ViewColumn(loC.cEngine, lcCol, lcTypes, lcList)
		ENDFOR
		lcSql = "SELECT " + lcSql + " FROM " + This.Quoted(loC.cEngine, lcName)
		lcProbe = lcSql + " WHERE 1=0 AND (" + tcWhere + ")"
		lcSql = lcSql + IIF(EMPTY(tcWhere), "", " WHERE " + tcWhere)
		llProbe = .F.
		lcOldDbc = DBC()
		llOpened = .F.
		lcErr = ""
		llMap = CURSORGETPROP("MapVarchar", 0)
		llBin = CURSORGETPROP("MapBinary", 0)
		lcConn = ""
		lcMemo = ""
		TRY
			*-- CREATE SQL VIEW no manda el WHERE al servidor: con una columna que no
			*-- existe, la vista se haría y fallaría al abrirla. El SELECT con WHERE 1=0
			*-- por la conexión de FoxRemote lo prueba antes, sin traer filas y en
			*-- cualquier motor, y antes de tocar el .dbc: si falla, no hay nada que
			*-- deshacer. Con un parámetro de vista (?x) no se prueba: SQLEXEC lo pediría.
			IF !EMPTY(tcWhere) AND !("?" $ tcWhere)
				TRY
					IF SQLEXEC(loDb.nHandle, lcProbe, "fdviewprobe") < 0
						=AERROR(laE)
						llProbe = .T.
					ENDIF
				CATCH TO loErr
					DIMENSION laE[1, 7]
					laE[1, 2] = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
					llProbe = .T.
				ENDTRY
				IF USED("fdviewprobe")
					USE IN fdviewprobe
				ENDIF
				IF llProbe
					llServer = .T.
					ERROR TRANSFORM(laE[1, 2])
				ENDIF
			ENDIF
			DO CASE
				CASE !FILE(tcDbc)
					CREATE DATABASE (tcDbc)
					llOpened = .T.
				CASE DBUSED(tcDbc)
					SET DATABASE TO (tcDbc)
				OTHERWISE
					OPEN DATABASE (tcDbc)
					llOpened = .T.
			ENDCASE
			DO CASE
				*-- Reemplazar, solo una vista, y no si está abierta en el IDE: DROP VIEW no
				*-- cierra el cursor de una vista abierta.
				CASE tlReplace AND INDBC(tcView, "VIEW") AND USED(tcView)
					llInUse = .T.
					ERROR "the view " + tcView + " is open in the IDE"
				CASE tlReplace AND INDBC(tcView, "VIEW")
					DROP VIEW (tcView)
					llReplaced = .T.
				CASE INDBC(tcView, "VIEW") OR INDBC(tcView, "TABLE")
					llExists = .T.
					ERROR "there is already a view or table " + tcView + " in " + tcDbc
			ENDCASE
			*-- La conexión del .dbc, una por conexión de FoxDock: la que ya tenga
			*-- esta cadena, o una nueva (<id>, <id>_2...).
			lcConn = LOWER(CHRTRAN(loC.cId, CHRTRAN(LOWER(loC.cId), "abcdefghijklmnopqrstuvwxyz0123456789_", ""), ""))
			lcConn = IIF(BETWEEN(LEFT(lcConn, 1), "a", "z"), lcConn, "c_" + lcConn)
			lnTry = 1
			DO WHILE INDBC(lcConn + IIF(lnTry = 1, "", "_" + TRANSFORM(lnTry)), "CONNECTION") AND ;
					!(DBGETPROP(lcConn + IIF(lnTry = 1, "", "_" + TRANSFORM(lnTry)), "Connection", "ConnectString") == lcNo)
				lnTry = lnTry + 1
			ENDDO
			lcConn = lcConn + IIF(lnTry = 1, "", "_" + TRANSFORM(lnTry))
			IF llPwd
				lcDsn = ADDBS(SYS(2023)) + "foxdock-" + SYS(2015) + ".dsn"
				=STRTOFILE(This.DsnText(lcCs), lcDsn)
				lcUse = "FILEDSN=" + lcDsn + ";"
			ENDIF
			IF !INDBC(lcConn, "CONNECTION")
				lcCmd = "CREATE CONNECTION " + lcConn + " CONNSTRING lcUse"
				&lcCmd
			ELSE
				=DBSETPROP(lcConn, "Connection", "ConnectString", lcUse)
			ENDIF
			=DBSETPROP(lcConn, "Connection", "DispLogin", 3)
			=CURSORSETPROP("MapVarchar", .T., 0)
			=CURSORSETPROP("MapBinary", .T., 0)
			lcCmd = "CREATE SQL VIEW " + tcView + " REMOTE CONNECTION " + lcConn + " AS " + lcSql
			&lcCmd
		CATCH TO loErr
			lcErr = IIF(loErr.ErrorNo = 1098, loErr.Message, TRANSFORM(loErr.ErrorNo) + " " + loErr.Message)
		FINALLY
			=CURSORSETPROP("MapVarchar", llMap, 0)
			=CURSORSETPROP("MapBinary", llBin, 0)
			*-- La cadena sin la contraseña pase lo que pase, y el .dsn, borrado.
			*-- DispLogin 1 en su conexión del .dbc, la nueva o la de antes: USE a secas
			*-- y Modify en el diseñador piden la contraseña en la ventana del driver en
			*-- vez de dar el error 1526. Mientras CREATE SQL VIEW la usa, en 3: con 1 el
			*-- driver abriría su ventana al crear. También si la vista falla: si no, la
			*-- conexión se quedaría en 3 y las vistas de antes volverían al 1526. Lo que
			*-- viene después va por la conexión de FoxRemote (CONNSTRING lnH) y no lo usa.
			IF !EMPTY(lcConn) AND INDBC(lcConn, "CONNECTION")
				=DBSETPROP(lcConn, "Connection", "ConnectString", lcNo)
				=DBSETPROP(lcConn, "Connection", "DispLogin", 1)
			ENDIF
			IF !EMPTY(lcDsn) AND FILE(lcDsn)
				ERASE (lcDsn)
			ENDIF
		ENDTRY
		IF EMPTY(lcErr) AND !EMPTY(lcKey)
			TRY
				*-- Actualizable: los nombres de los campos de la vista, de un USE NODATA.
				lnH = loDb.nHandle
				USE (tcView) NODATA IN 0 ALIAS fdviewchk CONNSTRING lnH
				lnN = AFIELDS(laF, "fdviewchk")
				USE IN fdviewchk
				=DBSETPROP(tcView, "View", "SendUpdates", .T.)
				=DBSETPROP(tcView, "View", "Tables", lcName)
				FOR lnI = 1 TO MIN(lnN, GETWORDCOUNT(tcCols, ","))
					lcCol = ALLTRIM(GETWORDNUM(tcCols, lnI, ","))
					lcField = tcView + "." + LOWER(laF[lnI, 1])
					=DBSETPROP(lcField, "Field", "UpdateName", lcName + "." + lcCol)
					DO CASE
						CASE ("," + UPPER(lcCol) + ",") $ ("," + UPPER(STRTRAN(lcKey, " ", "")) + ",")
							=DBSETPROP(lcField, "Field", "KeyField", .T.)
						CASE loC.cEngine == "sqlite" AND laF[lnI, 2] == "M"
							*-- Una columna TEXT de SQLite llega como memo, y por la vista no se escribe
							*-- (WhereType 3 da «Update conflict»; 1, la deja vacía).
							lcMemo = lcMemo + IIF(EMPTY(lcMemo), "", ", ") + lcCol
						CASE ("," + LOWER(lcCol) + ",") $ lcJson
							*-- Un JSON de MySQL llega entero por el CAST, pero guardarlo da «Update
							*-- conflict»: se lee y no se escribe.
							lcMemo = lcMemo + IIF(EMPTY(lcMemo), "", ", ") + lcCol
						OTHERWISE
							=DBSETPROP(lcField, "Field", "Updatable", .T.)
					ENDCASE
				ENDFOR
			CATCH TO loErr
				lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
			ENDTRY
		ENDIF
		IF EMPTY(lcErr)
			*-- Que el servidor la acepta: abierta sin datos, por la conexión de FoxRemote.
			TRY
				lnH = loDb.nHandle
				USE (tcView) NODATA IN 0 ALIAS fdviewchk CONNSTRING lnH
				USE IN fdviewchk
			CATCH TO loErr
				llServer = .T.
				lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
			ENDTRY
		ENDIF
		*-- Con la comprobación del WHERE fallida no se abrió el .dbc: el de INDBC sería otro.
		IF !EMPTY(lcErr) AND !llProbe AND INDBC(tcView, "VIEW") AND !llExists AND !llInUse
			TRY
				DELETE VIEW (tcView)
			CATCH TO loErr
			ENDTRY
		ENDIF
		IF llOpened
			SET DATABASE TO (tcDbc)
			CLOSE DATABASE
		ENDIF
		IF !EMPTY(lcOldDbc) AND DBUSED(lcOldDbc)
			SET DATABASE TO (lcOldDbc)
		ENDIF
		SET DATASESSION TO (lnDs)
		IF !EMPTY(lcErr)
			lcErr = This.Scrub(lcErr, "") + IIF(RIGHT(lcErr, 1) == ".", "", ".")
			*-- La que falla deja también su línea en el log, con el motivo.
			This.oHost.LogWarn("data.connections: view " + tcView + " not made in " + tcDbc + ": " + lcErr)
			*-- Lo nuestro, en el idioma de FoxDock; lo del motor, citado.
			DO CASE
				CASE llInUse
					This.ExploreSayKey(toF, "data.view.inUse", tcView)
				CASE llExists
					This.ExploreSayKey(toF, "data.view.exists", tcView, tcDbc)
				CASE llServer
					This.ExploreSay(toF, This.T("data.view.serverRefused", This.oHost.Quoted(lcErr)), This.E("data.view.serverRefused", lcErr))
				OTHERWISE
					This.ExploreSay(toF, This.T("data.view.failed", This.oHost.Quoted(lcErr)), This.E("data.view.failed", lcErr))
			ENDCASE
			RETURN .F.
		ENDIF
		toF.edtLines.Value = This.ViewLines(tcDbc, tcView, lcConn, lcNo, llPwd)
		This.oHost.Log("data.connections: view " + tcView + IIF(llReplaced, " replaced", " made") + " in " + tcDbc + " (" + IIF(EMPTY(lcKey), "read only", "updatable") + ;
			"), connection " + lcConn + " of the .dbc, without a password")
		This.ExploreSay(toF, This.T(IIF(llReplaced, "data.view.remade", "data.view.made"), tcView, This.T(IIF(EMPTY(lcKey), "data.view.readOnly", "data.view.isUpdatable")), ;
			tcDbc, lcConn, This.T(IIF(llPwd, "data.view.withPassword", "data.view.noPassword")), ;
			IIF(EMPTY(lcMemo), "", This.T(IIF(loC.cEngine == "mysql", "data.view.notUpdatableJson", "data.view.notUpdatable"), lcMemo)) + IIF(loC.cEngine == "sqlite", This.T("data.view.sqliteUtf8"), "") + ;
			IIF(llPwd, This.T("data.view.askLogin", tcView), "")), ;
			This.E(IIF(llReplaced, "data.view.remade", "data.view.made"), tcView, This.E(IIF(EMPTY(lcKey), "data.view.readOnly", "data.view.isUpdatable")), ;
			tcDbc, lcConn, This.E(IIF(llPwd, "data.view.withPassword", "data.view.noPassword")), ;
			IIF(EMPTY(lcMemo), "", This.E(IIF(loC.cEngine == "mysql", "data.view.notUpdatableJson", "data.view.notUpdatable"), lcMemo)) + IIF(loC.cEngine == "sqlite", This.E("data.view.sqliteUtf8"), "") + ;
			IIF(llPwd, This.E("data.view.askLogin", tcView), "")))
		*-- La que abre Open.
		IF PEMSTATUS(toF, "cmdOpen", 5)
			toF.cMadeView = tcView
			toF.cMadeDbc = tcDbc
			toF.lMadePwd = llPwd
			toF.cmdOpen.Enabled = .T.
		ENDIF
		RETURN .T.
	ENDPROC

	*-- Open: lo que dicen las líneas de la ventana, hecho. En la sesión 1, la
	*-- del IDE (las ventanas de FoxDock ya van en ella; con una privada, SET
	*-- DATASESSION TO 1 y USE la dejan ahí, y sigue al cerrar la ventana): el
	*-- .dbc (OPEN DATABASE de uno ya abierto no da error, pero se elige con SET
	*-- DATABASE), USE <vista> IN 0 con el límite de filas de Query..., y un
	*-- BROWSE como el de Browse. Si ya estaba abierta, REQUERY: otro USE ... IN 0
	*-- la abriría otra vez con otro alias. Con contraseña, la guardada con
	*-- Remember (la tecleada no se guarda); sin ella, no abre y lo dice. Nada
	*-- modal. .T. si la abrió.
	PROCEDURE OpenView
		LPARAMETERS toF
		LOCAL loC, lcView, lcDbc, lcPwd, lcConn, lcCs, lnDs, loErr, lcErr, lnArea, lnRows, lnLimit, lcTitle
		loC = This.Find(toF.cConnId)
		lcView = toF.cMadeView
		lcDbc = toF.cMadeDbc
		IF EMPTY(lcView) OR ISNULL(loC)
			RETURN .F.
		ENDIF
		*-- La que las líneas dicen: si la cadena viva llevaba PWD (CreateView, llPwd).
		*-- Una SQLite con usuario no la lleva, y se abre sin ella.
		lcPwd = ""
		IF toF.lMadePwd
			lcPwd = This.ReadSecret(loC.cId)
			IF EMPTY(lcPwd)
				This.ExploreSayKey(toF, "data.view.openNeedsPassword", lcView, loC.cName)
				This.oHost.Log("data.connections: view " + lcView + " not opened: the password of '" + loC.cId + "' is not kept")
				RETURN .F.
			ENDIF
		ENDIF
		lnLimit = This.QueryLimit()
		lcTitle = This.T("data.view.browseTitle", lcView, loC.cName)
		lcErr = ""
		lcConn = ""
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		TRY
			IF DBUSED(lcDbc)
				SET DATABASE TO (lcDbc)
			ELSE
				OPEN DATABASE (lcDbc)
			ENDIF
			lcConn = DBGETPROP(lcView, "View", "ConnectName")
			IF USED(lcView)
				SELECT (lcView)
			ELSE
				IF EMPTY(lcPwd)
					USE (lcView) IN 0 NODATA
				ELSE
					lcCs = This.WithPassword(DBGETPROP(lcConn, "Connection", "ConnectString"), lcPwd)
					USE (lcView) IN 0 NODATA CONNSTRING (lcCs)
				ENDIF
				SELECT (lcView)
			ENDIF
			=CURSORSETPROP("MaxRecords", IIF(lnLimit > 0, lnLimit, -1), lcView)
			=REQUERY(lcView)
			GO TOP IN (lcView)
			lnArea = SELECT(lcView)
			lnRows = RECCOUNT(lcView)
		CATCH TO loErr
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		ENDTRY
		SET DATASESSION TO (lnDs)
		IF !EMPTY(lcErr)
			lcErr = This.Scrub(lcErr, lcPwd)
			This.ExploreSay(toF, This.T("data.view.openFailed", This.oHost.Quoted(lcErr)), This.E("data.view.openFailed", lcErr))
			RETURN .F.
		ENDIF
		This.Browse(lcView, lcTitle)
		This.oHost.Log("data.connections: view " + lcView + " opened from " + lcDbc + " (connection " + lcConn + " of the .dbc" + ;
			IIF(EMPTY(lcPwd), "", ", with the kept password") + "), area " + TRANSFORM(lnArea) + ", " + TRANSFORM(lnRows) + " row(s)" + ;
			IIF(lnLimit > 0, " (limit " + TRANSFORM(lnLimit) + ")", ""))
		This.ExploreSayKey(toF, "data.view.opened", lcView, lnArea, lnRows)
		RETURN .T.
	ENDPROC

	*-- tcCs con la contraseña, y el «;» delante si falta. La cadena viva de
	*-- PostgreSQL acaba en «A1=7.4», sin «;», y WithoutPassword no se lo pone:
	*-- sin él quedaría «A1=7.4PWD=...» y el driver no recibiría PWD. La de SQL
	*-- Server acaba en «;» y queda como estaba.
	PROCEDURE WithPassword
		LPARAMETERS tcCs, tcPwd
		RETURN tcCs + IIF(EMPTY(tcCs) OR RIGHT(tcCs, 1) == ";", "", ";") + "PWD=" + tcPwd
	ENDPROC

	*-- Las líneas que abren la vista tcView desde la ventana de comandos: la
	*-- conexión tcConn del .dbc guarda tcNo, sin contraseña; con tlPwd la piden y
	*-- la pegan como Abrir (WithPassword).
	PROCEDURE ViewLines
		LPARAMETERS tcDbc, tcView, tcConn, tcNo, tlPwd
		LOCAL lcJoin
		lcJoin = SUBSTR(This.WithPassword(tcNo, "<the password>"), LEN(tcNo) + 1)
		RETURN [OPEN DATABASE "] + tcDbc + ["] + CRLF + ;
			IIF(tlPwd, "USE " + tcView + [ CONNSTRING DBGETPROP("] + tcConn + [", "Connection", "ConnectString") + "] + lcJoin + ["], ;
			"USE " + tcView)
	ENDPROC

	*-- El .dsn de una cadena de conexión, para FILEDSN=: [ODBC] y una línea por
	*-- clave, DRIVER sin llaves. Un valor entre llaves, que puede llevar «;»,
	*-- va tal cual.
	PROCEDURE DsnText
		LPARAMETERS tcCs
		LOCAL lcOut, lnI, lcCh, lcPart, llBrace, lcKey, lcVal
		lcOut = "[ODBC]" + CHR(13) + CHR(10)
		lcPart = ""
		llBrace = .F.
		FOR lnI = 1 TO LEN(tcCs) + 1
			lcCh = IIF(lnI > LEN(tcCs), ";", SUBSTR(tcCs, lnI, 1))
			IF lcCh == ";" AND !llBrace
				IF "=" $ lcPart
					lcKey = ALLTRIM(LEFT(lcPart, AT("=", lcPart) - 1))
					lcVal = ALLTRIM(SUBSTR(lcPart, AT("=", lcPart) + 1))
					IF UPPER(lcKey) == "DRIVER" AND LEFT(lcVal, 1) == "{" AND RIGHT(lcVal, 1) == "}"
						lcVal = SUBSTR(lcVal, 2, LEN(lcVal) - 2)
					ENDIF
					lcOut = lcOut + lcKey + "=" + lcVal + CHR(13) + CHR(10)
				ENDIF
				lcPart = ""
			ELSE
				lcPart = lcPart + lcCh
				llBrace = ICASE(lcCh == "{", .T., lcCh == "}", .F., llBrace)
			ENDIF
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- Una cadena ODBC sin PWD= ni PASSWORD= (las partes separadas por «;»).
	PROCEDURE WithoutPassword
		LPARAMETERS tcCs
		LOCAL laP[1], lnN, lnI, lcOut, lcKey
		lnN = ALINES(laP, tcCs, 1, ";")
		lcOut = ""
		FOR lnI = 1 TO lnN
			lcKey = UPPER(ALLTRIM(GETWORDNUM(laP[lnI], 1, "=")))
			IF !EMPTY(laP[lnI]) AND !INLIST(lcKey, "PWD", "PASSWORD")
				lcOut = lcOut + laP[lnI] + ";"
			ENDIF
		ENDFOR
		RETURN IIF(RIGHT(tcCs, 1) == ";" OR EMPTY(lcOut), lcOut, LEFT(lcOut, LEN(lcOut) - 1))
	ENDPROC

	*-- El botón Export... de Explore...: la ventanita de la tabla o vista elegida.
	PROCEDURE ExportBar
		LPARAMETERS toF, tcName
		LOCAL loC, lcName
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcName)
		IF EMPTY(lcName)
			This.ExploreSay(toF, This.cLastError)
			RETURN .NULL.
		ENDIF
		RETURN This.ShowForm("DataExportForm", loC, lcName)
	ENDPROC

	*-- Script as... de Explore...: la ventanita de tcName.
	PROCEDURE ScriptBar
		LPARAMETERS toF, tcName
		LOCAL loC, lcName
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcName)
		IF EMPTY(lcName)
			This.ExploreSay(toF, This.cLastError)
			RETURN .NULL.
		ENDIF
		RETURN This.ShowForm("DataScriptForm", loC, lcName)
	ENDPROC

	*-- El script de la ventanita toF: tcKind create, insert o update; tcDialect,
	*-- el id; tnFirst 0, todas las filas; tcTo «clip» al portapapeles, si no, al
	*-- fichero <tabla>-<kind>.sql (.prg en VFP) de OutDir(), abierto como lo abre
	*-- Script table as. Lo que pasa, en la ventanita, el aviso y el log.
	PROCEDURE ScriptTable
		LPARAMETERS toF, tcName, tcKind, tcDialect, tnFirst, tcTo
		LOCAL loP, loS, loC, lcFile, loR, llClip, lcRows, lcRowsEn, lcText, lcTextEn
		loC = This.Find(toF.cConnId)
		loP = This.Plugin()
		loS = loP.Module("script")
		IF ISNULL(loS)
			This.ExploreSay(toF, "The script module of the data package is not loaded (options.data.script.enabled).")
			RETURN .F.
		ENDIF
		llClip = tcTo == "clip"
		lcFile = IIF(llClip, "", loP.OutDir() + LOWER(tcName) + "-" + tcKind + IIF(tcDialect == "vfp", ".prg", ".sql"))
		loR = loS.RemoteScript(loC.cId, tcName, tcKind, tcDialect, IIF(tcKind == "create", 0, MAX(INT(tnFirst), 0)), lcFile)
		IF ISNULL(loR)
			This.ExploreSay(toF, loS.cLastError)
			RETURN .F.
		ENDIF
		DO CASE
			CASE tcKind == "create"
				STORE "" TO lcRows, lcRowsEn
			CASE loR.lTruncated
				lcRows = ", " + This.T("data.export.firstOf", loR.nDone, loR.nRows)
				lcRowsEn = ", " + This.E("data.export.firstOf", loR.nDone, loR.nRows)
			OTHERWISE
				lcRows = ", " + This.T(IIF(loR.nRows = 1, "data.rows.one", "data.rows.many"), loR.nRows)
				lcRowsEn = ", " + This.E(IIF(loR.nRows = 1, "data.rows.one", "data.rows.many"), loR.nRows)
		ENDCASE
		IF llClip AND !This.oHost.ToClipboard(loR.cText, "the script " + loR.cName + " (" + tcKind + ")")
			*-- Otro programa tiene el portapapeles: el aviso lo dice, sin dar el script
			*-- por copiado.
			toF.edtSay.Value = This.T("data.script.clipBusy", loR.cName, loS.KindName(tcKind), loS.DialectName(tcDialect), lcRows)
			This.oHost.Notify(toF.edtSay.Value, This.E("data.script.clipBusy", loR.cName, loS.KindName(tcKind), loS.DialectName(tcDialect), lcRowsEn))
			RETURN .F.
		ENDIF
		IF llClip
			lcText = This.T("data.script.clipDone", loR.cName, loS.KindName(tcKind), loS.DialectName(tcDialect), lcRows, LEN(loR.cText))
			lcTextEn = This.E("data.script.clipDone", loR.cName, loS.KindName(tcKind), loS.DialectName(tcDialect), lcRowsEn, LEN(loR.cText))
		ELSE
			IF loS.Utf8File(tcDialect)
				=loP.OpenWithWindows(lcFile)
			ELSE
				=This.oHost.Editor.Open(lcFile)
			ENDIF
			lcText = This.T("data.script.done", loR.cName, loS.KindName(tcKind), loS.DialectName(tcDialect), lcRows, ;
				This.T("data.inFile", lcFile), IIF(EMPTY(loR.cSkipped), "", This.T("data.skippedGeneral", loR.cSkipped)) + ;
				IIF(loR.nLeftOut = 0, "", This.T("data.leftOutRows", TRANSFORM(loR.nLeftOut))))
			lcTextEn = This.E("data.script.done", loR.cName, loS.KindName(tcKind), loS.DialectName(tcDialect), lcRowsEn, ;
				This.E("data.inFile", lcFile), IIF(EMPTY(loR.cSkipped), "", This.E("data.skippedGeneral", loR.cSkipped)) + ;
				IIF(loR.nLeftOut = 0, "", This.E("data.leftOutRows", TRANSFORM(loR.nLeftOut))))
		ENDIF
		toF.edtSay.Value = lcText
		This.oHost.Notify(lcText, lcTextEn)
		RETURN .T.
	ENDPROC

	*-- Las filas de tcName según el servidor (SELECT COUNT(*)), o -1.
	PROCEDURE ServerCount
		LPARAMETERS tcId, tcName
		LOCAL loC, loDb, lnDs, lvV
		loC = This.Find(tcId)
		IF ISNULL(loC) OR !This.Ready(loC.cId)
			RETURN -1
		ENDIF
		loDb = This.Live(loC.cId)
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lvV = This.Scalar(loC.cId, loDb, "SELECT COUNT(*) FROM " + This.Quoted(loC.cEngine, tcName))
		SET DATASESSION TO (lnDs)
		RETURN IIF(VARTYPE(lvV) == "N", lvV, IIF(VARTYPE(lvV) == "C", VAL(lvV), -1))
	ENDPROC

	*-- Export de la ventanita toF: tcFormat dbf, json o csv; tnFirst 0, todas
	*-- las filas; tcSep y tcEnc (ansi o utf8bom) para el .csv. Lo que pasa, en
	*-- la ventanita, la barra de estado y el log. .T. si escribió.
	*-- tcTo «clip» lo pone en el portapapeles (JSON y CSV; el texto de VFP, sin
	*-- codificación), y tlSchemaOnly deja el JSON en sus columnas, sin filas.
	PROCEDURE Export
		LPARAMETERS toF, tcName, tcFormat, tcFile, tnFirst, tcSep, tcEnc, tlReplace, tlOpen, tcTo, tlSchemaOnly
		LOCAL loC, lcName, lnTotal, lcTmp, lnDs, lcSafety, loErr, lcErr, lnRows, lcText, loP, lcOpened, lcArg, lcPart, lcPartEn
		LOCAL llClip, lcCols, lnCols, loDb, loTo, llHeld
		loC = This.Find(toF.cConnId)
		lcName = This.ObjectName(toF.cConnId, tcName)
		llClip = VARTYPE(tcTo) == "C" AND tcTo == "clip"
		tlSchemaOnly = tcFormat == "json" AND VARTYPE(tlSchemaOnly) == "L" AND tlSchemaOnly
		*-- lcErr, la clave de la cadena y su valor (o el cLastError, entre «!»).
		lcErr = ""
		lcArg = ""
		DO CASE
			CASE EMPTY(lcName)
				lcErr = "!" + This.cLastError
			CASE llClip AND tcFormat == "dbf"
				lcErr = "data.export.noClipDbf"
			CASE llClip
				*-- Al portapapeles: el fichero no cuenta.
			CASE EMPTY(JUSTSTEM(tcFile)) OR !(LOWER(JUSTEXT(tcFile)) == tcFormat)
				lcErr = "data.export.badName"
				lcArg = tcFormat
			CASE !DIRECTORY(JUSTPATH(tcFile), 1)
				lcErr = "data.export.noFolder"
				lcArg = JUSTPATH(tcFile)
			CASE FILE(tcFile) AND !tlReplace
				lcErr = "data.export.exists"
				lcArg = tcFile
			CASE This.InEditor(tcFile)
				lcErr = "data.export.inEditor"
				lcArg = tcFile
			CASE This.InUse(tcFile)
				*-- Con el fichero abierto por otro programa, STRTOFILE no da error y
				*-- escribe 0 bytes.
				lcErr = "data.export.inUse"
				lcArg = tcFile
		ENDCASE
		IF !EMPTY(lcErr)
			IF LEFT(lcErr, 1) == "!"
				This.ExploreSay(toF, SUBSTR(lcErr, 2))
			ELSE
				This.ExploreSayKey(toF, lcErr, lcArg)
			ENDIF
			RETURN .F.
		ENDIF
		tnFirst = MAX(INT(tnFirst), 0)
		lnTotal = This.ServerCount(loC.cId, lcName)
		lcTmp = "FDX" + SYS(2015)
		lnRows = 0
		IF !tlSchemaOnly
			IF !This.TableSelect(loC.cId, lcName, tnFirst, lcTmp)
				This.ExploreSay(toF, This.cLastError)
				RETURN .F.
			ENDIF
			lnRows = This.nLastRows
		ENDIF
		*-- El JSON lleva las columnas como las da ide_data_db_describe (GetColumns).
		lcCols = "FDK" + SYS(2015)
		lnCols = 0
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		IF tcFormat == "json"
			loDb = This.Live(loC.cId)
			IF This.BinaryRead(loDb, "columns", lcName, lcCols)
				lnCols = RECCOUNT(lcCols)
			ELSE
				IF USED(lcTmp)
					USE IN (lcTmp)
				ENDIF
				SET DATASESSION TO (lnDs)
				This.ExploreSay(toF, This.T("data.columns.failed", lcName, This.oHost.Quoted(loDb.cLastError)), ;
					This.E("data.columns.failed", lcName, loDb.cLastError))
				RETURN .F.
			ENDIF
		ENDIF
		*-- Al portapapeles, un DataFile sin fichero: junta el texto en cBuffer.
		loTo = IIF(llClip, CREATEOBJECT("DataFile", "", "ansi"), tcFile)
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		lcErr = ""
		llHeld = .F.
		TRY
			DO CASE
				CASE tcFormat == "dbf"
					This.WriteDbf(lcTmp, tcFile)
				CASE tcFormat == "json"
					This.WriteJsonDoc(IIF(tlSchemaOnly, "", lcTmp), lcCols, loTo, lcName, loC.cName)
				OTHERWISE
					This.WriteCsv(lcTmp, loTo, tcSep, tcEnc)
			ENDCASE
			IF llClip
				llHeld = !This.oHost.ToClipboard(loTo.cBuffer, "the export of " + lcName)
			ENDIF
		CATCH TO loErr
			lcErr = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		FINALLY
			SET SAFETY &lcSafety
			SET DATASESSION TO 1
			IF USED(lcTmp)
				USE IN (lcTmp)
			ENDIF
			IF USED(lcCols)
				USE IN (lcCols)
			ENDIF
			SET DATASESSION TO (lnDs)
		ENDTRY
		*-- Otro programa tenía el portapapeles: no se copió nada.
		IF llHeld
			This.ExploreSay(toF, This.T("data.export.notWritten", lcName, This.T("data.export.theClip"), This.T("data.export.clipHeld")), ;
				This.E("data.export.notWritten", lcName, This.E("data.export.theClip"), This.E("data.export.clipHeld")))
			RETURN .F.
		ENDIF
		IF !EMPTY(lcErr) OR (!llClip AND !FILE(tcFile))
			This.ExploreSay(toF, This.T("data.export.notWritten", lcName, IIF(llClip, This.T("data.export.theClip"), tcFile), ;
				IIF(EMPTY(lcErr), This.T("data.export.notThere"), This.oHost.Quoted(lcErr))), ;
				This.E("data.export.notWritten", lcName, IIF(llClip, This.E("data.export.theClip"), tcFile), ;
				EVL(lcErr, This.E("data.export.notThere"))))
			RETURN .F.
		ENDIF
		lcPart = IIF(tnFirst > 0 AND lnRows < lnTotal, This.T("data.export.firstOf", lnRows, lnTotal), This.T("data.export.allOfThem"))
		lcPartEn = IIF(tnFirst > 0 AND lnRows < lnTotal, This.E("data.export.firstOf", lnRows, lnTotal), This.E("data.export.allOfThem"))
		IF llClip
			*-- El portapapeles: ni fichero que abrir ni editor.
			IF tlSchemaOnly
				This.ExploreSayKey(toF, "data.export.schemaClip", lcName, loC.cName, lnCols, LEN(loTo.cBuffer))
			ELSE
				This.ExploreSay(toF, This.T("data.export.clipDone", lcName, loC.cName, lnRows, lcPart, LEN(loTo.cBuffer)), ;
					This.E("data.export.clipDone", lcName, loC.cName, lnRows, lcPartEn, LEN(loTo.cBuffer)))
			ENDIF
			RETURN .T.
		ENDIF
		lcText = IIF(tlSchemaOnly, This.E("data.export.schemaDone", lcName, loC.cName, lnCols, tcFile, ""), ;
			This.E("data.export.done", lcName, loC.cName, lnRows, lcPartEn, tcFile, ""))
		This.oHost.Log("data.connections: " + lcText)
		*-- Solo con «Open it» (un agente la quita: si no, Excel o el visor de .json
		*-- saldrían en la pantalla de quien trabaja), y el aviso dice con qué se
		*-- abrió.
		lcOpened = ""
		DO CASE
			CASE !tlOpen
			CASE tcFormat == "json" OR (tcFormat == "csv" AND tcEnc == "utf8bom")
				loP = This.Plugin()
				IF loP.OpenWithWindows(tcFile)
					lcOpened = "data.export.openedWindows"
				ENDIF
			CASE tcFormat == "csv"
				*-- CP1252 es la del editor de VFP; en un editor de texto (el de la FLL), no
				*-- en el de programas, que lo pintaría como código. Solo con el IDE a la
				*-- vista, como el BROWSE: con _screen oculto el editor se abre igual, pero
				*-- no sale en la lista de ventanas y nadie lo cierra.
				IF _screen.Visible AND This.oHost.Editor.Open(tcFile)
					This.oHost.Log("data.connections: " + tcFile + " opened in the editor of VFP")
					lcOpened = "data.export.openedEditor"
				ENDIF
		ENDCASE
		IF tlSchemaOnly
			This.ExploreSay(toF, This.T("data.export.schemaDone", lcName, loC.cName, lnCols, tcFile, IIF(EMPTY(lcOpened), "", This.T(lcOpened))), ;
				This.E("data.export.schemaDone", lcName, loC.cName, lnCols, tcFile, IIF(EMPTY(lcOpened), "", This.E(lcOpened))))
		ELSE
			This.ExploreSay(toF, This.T("data.export.done", lcName, loC.cName, lnRows, lcPart, tcFile, IIF(EMPTY(lcOpened), "", This.T(lcOpened))), ;
				This.E("data.export.done", lcName, loC.cName, lnRows, lcPartEn, tcFile, IIF(EMPTY(lcOpened), "", This.E(lcOpened))))
		ENDIF
		RETURN .T.
	ENDPROC

	*-- ¿Lo tiene abierto otro programa sin dejar escribir? (FOPEN para escribir
	*-- da -1 con FERROR 5). Un fichero que no está, no.
	PROCEDURE InUse
		LPARAMETERS tcFile
		LOCAL lnH
		IF !FILE(tcFile)
			RETURN .F.
		ENDIF
		lnH = FOPEN(tcFile, 2)
		IF lnH < 0
			RETURN .T.
		ENDIF
		=FCLOSE(lnH)
		RETURN .F.
	ENDPROC

	*-- ¿Está tcFile abierto en un editor de VFP? (la lista de ventanas del host;
	*-- trae el nombre del fichero, sin la carpeta)
	PROCEDURE InEditor
		LPARAMETERS tcFile
		LOCAL loList, lnI, loI, loErr, llOpen, loJson
		llOpen = .F.
		TRY
			loJson = This.oHost.oJson
			loList = loJson.Split(This.oHost.Windows.List())
			FOR lnI = 1 TO loList.Count
				loI = loJson.ToObject(loList.Item(lnI))
				IF loI.isEditor AND PEMSTATUS(loI, "file", 5) AND LOWER(loI.file) == LOWER(JUSTFNAME(tcFile))
					llOpen = .T.
				ENDIF
			ENDFOR
		CATCH TO loErr
			llOpen = .F.
		ENDTRY
		RETURN llOpen
	ENDPROC

	*-- Un .dbf libre con COPY TO, con los tipos de VFP del cursor; un .fpt si
	*-- hay memo. Lo de antes con ese nombre se borra primero (el .fpt y el .cdx
	*-- de otra exportación).
	PROTECTED PROCEDURE WriteDbf
		LPARAMETERS tcAlias, tcFile
		IF FILE(FORCEEXT(tcFile, "fpt"))
			ERASE (FORCEEXT(tcFile, "fpt"))
		ENDIF
		IF FILE(FORCEEXT(tcFile, "cdx"))
			ERASE (FORCEEXT(tcFile, "cdx"))
		ENDIF
		SELECT (tcAlias)
		COPY TO (tcFile)
	ENDPROC

	*-- El .json de Export...: un objeto con table, connection, columns (las de
	*-- GetColumns, como ide_data_db_describe) y, con tcRows, rows (las filas de
	*-- Table to JSON: DataJson.Walk, un objeto por fila). tuTo: el fichero (UTF-8
	*-- sin BOM) o un DataFile (el del portapapeles). DataJson.FromJson lo lee.
	PROTECTED PROCEDURE WriteJsonDoc
		LPARAMETERS tcRows, tcCols, tuTo, tcTable, tcConn
		LOCAL loF, loJ
		loF = IIF(VARTYPE(tuTo) == "O", tuTo, CREATEOBJECT("DataFile", tuTo, "utf8"))
		loJ = NEWOBJECT("DataJson", This.Home() + "DataJson.prg", "", This.oHost)
		loF.Write("{" + CRLF + ["table": ] + loJ.Quote(tcTable) + "," + CRLF + ["connection": ] + loJ.Quote(tcConn) + "," + CRLF + ;
			["columns": ])
		This.WalkInto(loJ, tcCols, loF)
		IF !EMPTY(tcRows)
			loF.Write("," + CRLF + ["rows": ])
			This.WalkInto(loJ, tcRows, loF)
		ENDIF
		loF.Write(CRLF + "}" + CRLF)
		loF.Flush()
	ENDPROC

	*-- Un array JSON con las filas de tcAlias, en toF.
	PROTECTED PROCEDURE WalkInto
		LPARAMETERS toJ, tcAlias, toF
		LOCAL loT
		loT = CREATEOBJECT("DataTable")
		TRY
			IF !loT.Open(tcAlias, .F.)
				ERROR loT.cError
			ENDIF
			=toJ.Walk(loT, 0, "", 0, toF)
		FINALLY
			loT.Close()
		ENDTRY
	ENDPROC

	*-- Un .csv: la fila de cabecera con los nombres; los textos sin el relleno,
	*-- entre comillas solo si llevan el separador, comillas o un salto de línea
	*-- (las comillas, dobladas); los números con punto; las fechas en ISO
	*-- 8601; lógicos true/false; NULL, vacío; binarios en base64. Líneas con
	*-- CRLF.
	*-- tuTo, el fichero o un DataFile (el del portapapeles).
	PROTECTED PROCEDURE WriteCsv
		LPARAMETERS tcAlias, tuTo, tcSep, tcEnc
		LOCAL loT, loF, lnI, lcLine, lcList, lvV, lcType
		LOCAL ARRAY laRow[1]
		loT = CREATEOBJECT("DataTable")
		loF = IIF(VARTYPE(tuTo) == "O", tuTo, CREATEOBJECT("DataFile", tuTo, IIF(tcEnc == "utf8bom", "utf8bom", "ansi")))
		TRY
			IF !loT.Open(tcAlias, .F.)
				ERROR loT.cError
			ENDIF
			lcLine = ""
			FOR lnI = 1 TO loT.nCols
				lcLine = lcLine + IIF(lnI > 1, tcSep, "") + This.CsvText(loT.aCols[lnI, 1], tcSep)
			ENDFOR
			loF.Write(lcLine + CRLF)
			lcList = loT.cFieldList
			SELECT (loT.cAlias)
			SCAN
				SCATTER FIELDS &lcList MEMO TO laRow
				lcLine = ""
				FOR lnI = 1 TO loT.nCols
					lvV = laRow[lnI]
					lcType = loT.aCols[lnI, 2]
					DO CASE
						CASE ISNULL(lvV)
							lvV = ""
						CASE INLIST(lcType, "C", "V", "M")
							lvV = This.CsvText(loT.Text(lnI, lvV), tcSep)
						CASE INLIST(lcType, "N", "F", "I", "B", "Y")
							lvV = loT.Num(lnI, lvV)
						CASE lcType == "D"
							lvV = loT.IsoDate(lvV)
						CASE lcType == "T"
							lvV = loT.IsoTime(lvV)
						CASE lcType == "L"
							lvV = IIF(lvV, "true", "false")
						CASE INLIST(lcType, "Q", "W")
							lvV = STRCONV(lvV, 13)
						OTHERWISE
							lvV = ""
					ENDCASE
					lcLine = lcLine + IIF(lnI > 1, tcSep, "") + lvV
				ENDFOR
				loF.Write(lcLine + CRLF)
			ENDSCAN
			loF.Flush()
		FINALLY
			loT.Close()
		ENDTRY
	ENDPROC

	PROCEDURE CsvText
		LPARAMETERS tcText, tcSep
		IF tcSep $ tcText OR ["] $ tcText OR CHR(13) $ tcText OR CHR(10) $ tcText
			RETURN ["] + STRTRAN(tcText, ["], [""]) + ["]
		ENDIF
		RETURN tcText
	ENDPROC

	*-- tcFrom pasa a tcTo, de solo lectura (sesión 1). SELECT ... INTO CURSOR
	*-- sin READWRITE da error 111 en REPLACE, APPEND y DELETE, y NOFILTER hace
	*-- un cursor propio, no un filtro sobre tcFrom. Si tcTo estaba abierto (su
	*-- BROWSE con él), se cierra antes.
	PROTECTED PROCEDURE ReadOnlyCursor
		LPARAMETERS tcFrom, tcTo
		IF USED(tcTo)
			USE IN (tcTo)
		ENDIF
		SELECT * FROM &tcFrom INTO CURSOR (tcTo) NOFILTER
		USE IN (tcFrom)
	ENDPROC

	PROCEDURE QueryBar
		LPARAMETERS tcId
		LOCAL loC
		IF !This.BarReady(tcId)
			RETURN .F.
		ENDIF
		loC = This.Find(tcId)
		This.ShowForm("DataQueryForm", loC)
		RETURN .T.
	ENDPROC

	*-- Lo que manda el botón Run de Query..., con el límite de su spinner (sin
	*-- él, el guardado; 0 = sin límite).
	PROCEDURE RunQuery
		LPARAMETERS tcId, tcSql, tnLimit
		LOCAL lcCur, loC
		loC = This.Find(tcId)
		IF VARTYPE(tnLimit) # "N"
			tnLimit = This.QueryLimit()
		ENDIF
		tnLimit = MAX(INT(tnLimit), 0)
		lcCur = This.CursorName(tcId, "query")
		This.cLastCursor = ""
		IF !This.QueryWhole(tcId, tcSql, tnLimit, lcCur)
			This.oHost.NotifyQuoted("data.said", This.cLastError)
			RETURN .F.
		ENDIF
		This.cLastCursor = lcCur
		This.Browse(lcCur)
		This.oHost.Notify(This.T("data.conn.queryRows", This.nLastRows, loC.cName, IIF(This.lLastTruncated, This.T("data.conn.firstN", tnLimit), ""), lcCur) + ;
			This.ShortNote(.T.), ;
			This.E("data.conn.queryRows", This.nLastRows, loC.cName, IIF(This.lLastTruncated, This.E("data.conn.firstN", tnLimit), ""), lcCur) + ;
			This.ShortNote(.F.))
		RETURN .T.
	ENDPROC

	*-- Edit connections... abre la ventana FoxDock - Connections
	*-- (DataConnectionsForm), una sola: otra vez, la trae delante.
	PROCEDURE EditBar
		LOCAL loF
		loF = This.FormByClass("DataConnectionsForm")
		IF ISNULL(loF)
			loF = This.ShowForm("DataConnectionsForm", .NULL.)
		ELSE
			loF.Fill()
			loF.Show()
		ENDIF
		RETURN loF
	ENDPROC

	*-- La ventana abierta de la clase tcClass que no es de una conexión, o .NULL.
	PROCEDURE FormByClass
		LPARAMETERS tcClass
		LOCAL loF
		FOR EACH loF IN This.oForms FOXOBJECT
			IF LOWER(loF.Class) == LOWER(tcClass)
				RETURN loF
			ENDIF
		ENDFOR
		RETURN .NULL.
	ENDPROC

	*-- New... (tcId vacío) o Edit... de la lista: la ventana FoxDock -
	*-- Connection, una sola. Abierta con cambios sin guardar, no carga otra: lo dice.
	PROCEDURE OpenEdit
		LPARAMETERS tcId
		LOCAL loF, loC
		loC = IIF(EMPTY(tcId), .NULL., This.Find(tcId))
		loF = This.FormByClass("DataConnectionEditForm")
		IF ISNULL(loF)
			loF = This.ShowForm("DataConnectionEditForm", loC)
			RETURN loF
		ENDIF
		IF loF.IsDirty()
			loF.Say("data.connEdit.unsaved")
		ELSE
			loF.LoadConn(loC)
		ENDIF
		loF.Show()
		RETURN loF
	ENDPROC

	*-- Por qué no vale la conexión de la ventana (la clave del aviso, o ""),
	*-- con sus valores en cWhy1 y cWhy2. tlNew: el id tiene que estar libre en
	*-- las dos listas (uno del proyecto taparía al tuyo). Una contraseña en un
	*-- campo, como SecretIn en el fichero.
	PROCEDURE CheckConnection
		LPARAMETERS toC, tlNew
		LOCAL loK
		This.cWhy1 = toC.cId
		This.cWhy2 = ""
		DO CASE
			CASE EMPTY(toC.cId) OR LEN(toC.cId) > 64 OR LEN(CHRTRAN(LOWER(toC.cId), "abcdefghijklmnopqrstuvwxyz0123456789_-.", "")) > 0
				RETURN "data.connEdit.badId"
			CASE tlNew AND This.oList.GetKey(LOWER(toC.cId)) > 0
				This.cWhy2 = This.oList.Item(LOWER(toC.cId)).cFile
				RETURN "data.connEdit.idTaken"
			CASE EMPTY(toC.cName)
				RETURN "data.connEdit.needName"
			CASE !("," + toC.cEngine + "," $ "," + DC_ENGINES + ",")
				RETURN "data.connEdit.badEngine"
			CASE toC.nPort < 0 OR toC.nPort > 65535
				This.cWhy1 = TRANSFORM(toC.nPort)
				RETURN "data.connEdit.badPort"
		ENDCASE
		loK = CREATEOBJECT("Collection")
		loK.Add(toC.cName, "name")
		loK.Add(toC.cServer, "server")
		loK.Add(toC.cDatabase, "database")
		loK.Add(toC.cUser, "user")
		loK.Add(toC.cDriver, "driver")
		This.cWhy1 = This.SecretIn(loK)
		IF !EMPTY(This.cWhy1)
			RETURN "data.connEdit.noPassword"
		ENDIF
		RETURN ""
	ENDPROC

	*-- Save de la ventana: comprueba, escribe el fichero entero
	*-- (SaveConnection) y, como Reload pero solo para ella, cierra su Explore...
	*-- si cambió su definición, lee otra vez los ficheros (Load la desconecta si
	*-- hace falta) y rehace el menú y la lista. La clave del aviso si no, o "".
	PROCEDURE StoreConnection
		LPARAMETERS toC, tcFile, tlNew
		LOCAL lcWhy, loOld, llChanged
		lcWhy = This.CheckConnection(toC, tlNew)
		IF !EMPTY(lcWhy)
			RETURN lcWhy
		ENDIF
		loOld = IIF(tlNew, .NULL., This.Find(toC.cId))
		llChanged = !ISNULL(loOld) AND !(This.Definition(loOld) == This.Definition(toC))
		lcWhy = This.SaveConnection(toC, tcFile)
		IF !EMPTY(lcWhy)
			RETURN lcWhy
		ENDIF
		IF llChanged
			=This.CloseExplore(toC.cId, "its definition changed")
		ENDIF
		This.Reloaded()
		This.oHost.NotifyKey("data.conns.saved", toC.cName, tcFile)
		RETURN ""
	ENDPROC

	*-- Delete de la ventana (ya confirmado): la desconecta, cierra su
	*-- Explore..., la quita de su fichero, olvida su contraseña guardada y relee.
	PROCEDURE DeleteConnection
		LPARAMETERS tcId
		LOCAL loC, lcWhy
		loC = This.Find(tcId)
		This.cWhy1 = tcId
		This.cWhy2 = ""
		IF ISNULL(loC)
			RETURN "data.conns.notThere"
		ENDIF
		lcWhy = This.FileRefusal(loC.cFile)
		IF !EMPTY(lcWhy)
			RETURN lcWhy
		ENDIF
		IF This.IsConnected(loC.cId)
			This.Disconnect(loC.cId, "the connection was deleted")
		ENDIF
		=This.CloseExplore(loC.cId, "the connection was deleted")
		lcWhy = This.RemoveConnection(loC.cId, loC.cFile)
		IF !EMPTY(lcWhy)
			RETURN lcWhy
		ENDIF
		This.ForgetSecret(loC.cId)
		This.Reloaded()
		This.oHost.NotifyKey("data.conns.removed", loC.cName, loC.cFile)
		RETURN ""
	ENDPROC

	PROCEDURE Reloaded
		LOCAL loF
		=This.Load()
		This.oHost.RefreshMenu()
		loF = This.FormByClass("DataConnectionsForm")
		IF !ISNULL(loF)
			loF.Fill()
		ENDIF
	ENDPROC

	*-- Por qué no se escribe tcFile ("" si se puede; la clave del aviso, con el
	*-- fichero en cWhy1): abierto en el editor (STRTOFILE lo dejaría en 0
	*-- bytes; InEditor mira el nombre, así que vale para los dos
	*-- connections.json), que no es un array, o que ya lleva una contraseña
	*-- (ReadFile no lo lee).
	PROCEDURE FileRefusal
		LPARAMETERS tcFile
		LOCAL lcText, loJ, loObjs, lnI
		This.cWhy1 = tcFile
		IF This.InEditor(tcFile)
			RETURN "data.conns.fileOpen"
		ENDIF
		IF !FILE(tcFile)
			RETURN ""
		ENDIF
		lcText = ALLTRIM(This.TextOf(FILETOSTR(tcFile)), 1, " ", CHR(9), CHR(13), CHR(10))
		IF !EMPTY(lcText) AND !(LEFT(lcText, 1) == "[")
			RETURN "data.conns.notArray"
		ENDIF
		loJ = This.oHost.oJson
		loObjs = loJ.Split(lcText)
		FOR lnI = 1 TO loObjs.Count
			IF !EMPTY(This.SecretIn(loJ.Parse(loObjs.Item(lnI))))
				RETURN "data.conns.hasPassword"
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- toC en tcFile, en el sitio de la que tiene su id o al final, y el fichero
	*-- entero reescrito con el molde de Template (WriteConnections). Las demás,
	*-- desde lo leído (ObjectText), con sus claves de más. "" o la clave.
	PROCEDURE SaveConnection
		LPARAMETERS toC, tcFile
		LOCAL lcWhy, loJ, loObjs, lnI, lcObj, lcOut, llDone
		lcWhy = This.FileRefusal(tcFile)
		IF !EMPTY(lcWhy)
			RETURN lcWhy
		ENDIF
		loJ = This.oHost.oJson
		lcOut = ""
		llDone = .F.
		IF FILE(tcFile)
			loObjs = loJ.Split(This.TextOf(FILETOSTR(tcFile)))
			FOR lnI = 1 TO loObjs.Count
				lcObj = loObjs.Item(lnI)
				IF !llDone AND This.IdOf(lcObj) == LOWER(toC.cId)
					lcOut = lcOut + IIF(EMPTY(lcOut), "", "," + CRLF) + This.ObjectText(toC, lcObj)
					llDone = .T.
				ELSE
					lcOut = lcOut + IIF(EMPTY(lcOut), "", "," + CRLF) + This.ObjectText(.NULL., lcObj)
				ENDIF
			ENDFOR
		ENDIF
		IF !llDone
			lcOut = lcOut + IIF(EMPTY(lcOut), "", "," + CRLF) + This.ObjectText(toC, "")
		ENDIF
		RETURN This.WriteConnections(tcFile, lcOut)
	ENDPROC

	*-- tcId fuera de tcFile; las demás, reescritas como en SaveConnection.
	PROCEDURE RemoveConnection
		LPARAMETERS tcId, tcFile
		LOCAL lcWhy, loJ, loObjs, lnI, lcObj, lcOut, llDone
		lcWhy = This.FileRefusal(tcFile)
		IF !EMPTY(lcWhy)
			RETURN lcWhy
		ENDIF
		This.cWhy1 = tcId
		IF !FILE(tcFile)
			RETURN "data.conns.notThere"
		ENDIF
		loJ = This.oHost.oJson
		lcOut = ""
		llDone = .F.
		loObjs = loJ.Split(This.TextOf(FILETOSTR(tcFile)))
		FOR lnI = 1 TO loObjs.Count
			lcObj = loObjs.Item(lnI)
			IF !llDone AND This.IdOf(lcObj) == LOWER(ALLTRIM(tcId))
				llDone = .T.
			ELSE
				lcOut = lcOut + IIF(EMPTY(lcOut), "", "," + CRLF) + This.ObjectText(.NULL., lcObj)
			ENDIF
		ENDFOR
		IF !llDone
			RETURN "data.conns.notThere"
		ENDIF
		RETURN This.WriteConnections(tcFile, lcOut)
	ENDPROC

	PROCEDURE IdOf
		LPARAMETERS tcObj
		LOCAL loJ
		loJ = This.oHost.oJson
		RETURN LOWER(ALLTRIM(TRANSFORM(NVL(loJ.Get(loJ.Parse(tcObj), "id", ""), ""))))
	ENDPROC

	*-- Un objeto del fichero en el molde de Template: dos espacios, una clave
	*-- por línea, las de la ventana en el orden de Template (port solo si no es
	*-- 0) y detrás las que la ventana no conoce, con su clave como se escribió y
	*-- su valor tal cual (RawMembers: anidados también). toC: la de la
	*-- ventana; sin él, las claves de la ventana salen de lo leído en tcRaw (las
	*-- que tiene).
	PROCEDURE ObjectText
		LPARAMETERS toC, tcRaw
		LOCAL loJ, loP, lcOut, lnI, lcKey, luV, loR, loM
		loJ = This.oHost.oJson
		lcOut = ""
		IF !ISNULL(toC)
			lcOut = This.KeyLine(lcOut, "id", loJ.Quote(LOWER(toC.cId)))
			lcOut = This.KeyLine(lcOut, "name", loJ.Quote(toC.cName))
			lcOut = This.KeyLine(lcOut, "engine", loJ.Quote(toC.cEngine))
			lcOut = This.KeyLine(lcOut, "server", loJ.Quote(toC.cServer))
			IF toC.nPort > 0
				lcOut = This.KeyLine(lcOut, "port", TRANSFORM(toC.nPort))
			ENDIF
			lcOut = This.KeyLine(lcOut, "database", loJ.Quote(toC.cDatabase))
			lcOut = This.KeyLine(lcOut, "user", loJ.Quote(toC.cUser))
			lcOut = This.KeyLine(lcOut, "driver", loJ.Quote(toC.cDriver))
			lcOut = This.KeyLine(lcOut, "windowsAuth", IIF(toC.lWindowsAuth, "true", "false"))
			lcOut = This.KeyLine(lcOut, "allowWrite", IIF(toC.lAllowWrite, "true", "false"))
			lcOut = This.KeyLine(lcOut, "agentCanRead", IIF(toC.lAgentCanRead, "true", "false"))
		ELSE
			loP = loJ.Parse(tcRaw)
			FOR lnI = 1 TO GETWORDCOUNT(DC_KEYS, ",")
				lcKey = GETWORDNUM(DC_KEYS, lnI, ",")
				IF loP.GetKey(LOWER(lcKey)) = 0
					LOOP
				ENDIF
				luV = loP.Item(LOWER(lcKey))
				IF lcKey == "port" AND (VARTYPE(luV) # "N" OR luV = 0)
					LOOP
				ENDIF
				lcOut = This.KeyLine(lcOut, lcKey, loJ.Stringify(luV))
			ENDFOR
		ENDIF
		IF !EMPTY(tcRaw)
			loR = This.RawMembers(tcRaw)
			FOR EACH loM IN loR FOXOBJECT
				IF !("," + LOWER(loM.cKey) + "," $ "," + LOWER(DC_KEYS) + ",")
					lcOut = This.KeyLine(lcOut, loM.cKey, loM.cRaw)
				ENDIF
			ENDFOR
		ENDIF
		RETURN "  {" + CRLF + lcOut + CRLF + "  }"
	ENDPROC

	PROTECTED PROCEDURE KeyLine
		LPARAMETERS tcOut, tcKey, tcValue
		RETURN tcOut + IIF(EMPTY(tcOut), "", "," + CRLF) + "    " + This.oHost.oJson.Quote(tcKey) + ": " + tcValue
	ENDPROC

	*-- Los miembros de primer nivel de un objeto JSON, con la clave como se
	*-- escribió y el valor en crudo, anidados incluidos (Parse pone las claves en
	*-- minúsculas y no lee un valor anidado). Una Collection de Empty {cKey, cRaw}.
	PROCEDURE RawMembers
		LPARAMETERS tcObj
		LOCAL loOut, lnLen, lnI, lnK, lcC, lnDepth, llStr, lnStart, lcKey, loM
		loOut = CREATEOBJECT("Collection")
		lnLen = LEN(tcObj)
		lnI = AT("{", tcObj)
		IF lnI = 0
			RETURN loOut
		ENDIF
		lnI = lnI + 1
		DO WHILE lnI <= lnLen
			lcC = SUBSTR(tcObj, lnI, 1)
			IF INLIST(lcC, " ", CHR(9), CHR(13), CHR(10), ",")
				lnI = lnI + 1
				LOOP
			ENDIF
			IF !(lcC == ["])
				EXIT
			ENDIF
			lcKey = ""
			lnK = lnI + 1
			DO WHILE lnK <= lnLen AND !(SUBSTR(tcObj, lnK, 1) == ["])
				IF SUBSTR(tcObj, lnK, 1) == "\"
					lcKey = lcKey + SUBSTR(tcObj, lnK, 1)
					lnK = lnK + 1
				ENDIF
				lcKey = lcKey + SUBSTR(tcObj, lnK, 1)
				lnK = lnK + 1
			ENDDO
			lnI = lnK + 1
			DO WHILE lnI <= lnLen AND !(SUBSTR(tcObj, lnI, 1) == ":")
				lnI = lnI + 1
			ENDDO
			lnI = lnI + 1
			lnStart = lnI
			lnDepth = 0
			llStr = .F.
			DO WHILE lnI <= lnLen
				lcC = SUBSTR(tcObj, lnI, 1)
				DO CASE
					CASE llStr AND lcC == "\"
						lnI = lnI + 1
					CASE lcC == ["]
						llStr = !llStr
					CASE llStr
					CASE INLIST(lcC, "{", "[")
						lnDepth = lnDepth + 1
					CASE INLIST(lcC, "}", "]") AND lnDepth > 0
						lnDepth = lnDepth - 1
					CASE INLIST(lcC, ",", "}") AND lnDepth = 0
						EXIT
				ENDCASE
				lnI = lnI + 1
			ENDDO
			loM = CREATEOBJECT("Empty")
			ADDPROPERTY(loM, "cKey", lcKey)
			ADDPROPERTY(loM, "cRaw", ALLTRIM(SUBSTR(tcObj, lnStart, lnI - lnStart), 1, " ", CHR(9), CHR(13), CHR(10)))
			loOut.Add(loM)
			IF lnI <= lnLen AND SUBSTR(tcObj, lnI, 1) == "}"
				EXIT
			ENDIF
			lnI = lnI + 1
		ENDDO
		RETURN loOut
	ENDPROC

	*-- El fichero, en UTF-8 sin BOM (TextOf lo lee igual) y con CRLF.
	PROCEDURE WriteConnections
		LPARAMETERS tcFile, tcObjects
		LOCAL lcBytes, lcSafety, loErr, llOk
		lcBytes = STRCONV("[" + CRLF + tcObjects + IIF(EMPTY(tcObjects), "", CRLF) + "]" + CRLF, 9)
		This.cWhy1 = tcFile
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		TRY
			=STRTOFILE(lcBytes, tcFile, 0)
			llOk = FILETOSTR(tcFile) == lcBytes
		CATCH TO loErr
			llOk = .F.
		FINALLY
			SET SAFETY &lcSafety
		ENDTRY
		IF !llOk
			RETURN "data.conns.notWritten"
		ENDIF
		This.oHost.Log("data.connections: " + tcFile + " written (" + TRANSFORM(LEN(lcBytes)) + " bytes)")
		RETURN ""
	ENDPROC

	*-- Open the file...: el connections.json del proyecto, o el tuyo, en el
	*-- editor; con el ejemplo si no existe.
	PROCEDURE OpenFileBar
		LOCAL lcFile, lcSafety
		lcFile = This.ProjectFile()
		IF EMPTY(lcFile)
			lcFile = This.UserFile()
		ENDIF
		IF !FILE(lcFile)
			lcSafety = SET("SAFETY")
			SET SAFETY OFF
			STRTOFILE(This.Template(), lcFile, 0)
			SET SAFETY &lcSafety
			This.oHost.Log("data.connections: " + lcFile + " made with an example")
		ENDIF
		=This.oHost.Editor.Open(lcFile)
		*-- Corto, para que quepa con la ruta en el aviso (255 caracteres).
		This.oHost.NotifyKey("data.conn.editing", lcFile)
	ENDPROC

	PROCEDURE ReloadBar
		LOCAL lnN, loF
		=This.CloseExplore("", "the connections were read again")
		lnN = This.Load()
		This.oHost.RefreshMenu()
		*-- Y la lista de FoxDock - Connections, si está abierta. La ventana de una
		*-- conexión se queda como está: Guardar relee el fichero entero.
		loF = This.FormByClass("DataConnectionsForm")
		IF !ISNULL(loF)
			loF.Fill()
		ENDIF
		This.oHost.NotifyKey("data.conn.read", lnN)
	ENDPROC

	*-- Dos conexiones, para que se vean la coma y dos motores; la de SQL Server,
	*-- con la autenticación de Windows y sin base.
	PROCEDURE Template
		RETURN "[" + CRLF + ;
			"  {" + CRLF + ;
			[    "id": "example",] + CRLF + ;
			[    "name": "Example (SQLite)",] + CRLF + ;
			[    "engine": "sqlite",] + CRLF + ;
			[    "server": "",] + CRLF + ;
			[    "database": "C:\\data\\example.db",] + CRLF + ;
			[    "user": "",] + CRLF + ;
			[    "driver": "SQLite3 ODBC Driver",] + CRLF + ;
			[    "windowsAuth": false,] + CRLF + ;
			[    "allowWrite": false,] + CRLF + ;
			[    "agentCanRead": false] + CRLF + ;
			"  }," + CRLF + ;
			"  {" + CRLF + ;
			[    "id": "sqlexpress",] + CRLF + ;
			[    "name": "SQL Server on this PC",] + CRLF + ;
			[    "engine": "sqlserver",] + CRLF + ;
			[    "server": "localhost\\SQLEXPRESS",] + CRLF + ;
			[    "database": "",] + CRLF + ;
			[    "user": "",] + CRLF + ;
			[    "driver": "ODBC Driver 18 for SQL Server",] + CRLF + ;
			[    "windowsAuth": true,] + CRLF + ;
			[    "allowWrite": false,] + CRLF + ;
			[    "agentCanRead": false] + CRLF + ;
			"  }" + CRLF + ;
			"]" + CRLF
	ENDPROC

	*-- Un nombre de cursor válido para VFP: c_<id>_<qué>.
	PROCEDURE CursorName
		LPARAMETERS tcId, tcWhat
		LOCAL lcS
		lcS = LOWER("c_" + tcId + "_" + tcWhat)
		lcS = CHRTRAN(lcS, CHRTRAN(lcS, "abcdefghijklmnopqrstuvwxyz0123456789_", ""), REPLICATE("_", 64))
		RETURN LEFT(lcS, 60)
	ENDPROC

	PROCEDURE Quoted
		LPARAMETERS tcEngine, tcName
		DO CASE
			CASE tcEngine == "sqlserver"
				RETURN "[" + STRTRAN(tcName, "]", "]]") + "]"
			CASE INLIST(tcEngine, "mysql", "mariadb")
				RETURN "`" + STRTRAN(tcName, "`", "``") + "`"
		ENDCASE
		RETURN ["] + STRTRAN(tcName, ["], [""]) + ["]
	ENDPROC

	*-- NORMAL: desde el botón Run de Query... la ventana activa es el
	*-- formulario, y sin NORMAL el BROWSE toma sus ajustes (el título, el tamaño
	*-- y el sitio): saldría encima del formulario con su título, y ni
	*-- WEXIST(<alias>) ni WONTOP() lo encontrarían. NOMODIFY deja añadir y
	*-- borrar filas: NOAPPEND y NODELETE también, que el cursor es una lectura.
	*-- tcTitle: con título, la ventana del BROWSE se llama como él y no como el
	*-- alias (WEXIST(<alias>) da .F.); USE IN del cursor la cierra igual.
	PROCEDURE Browse
		LPARAMETERS tcCursor, tcTitle
		LOCAL lnDs, lcTitle
		lcTitle = IIF(VARTYPE(tcTitle) == "C", tcTitle, "")
		This.cLastTitle = lcTitle
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		SELECT (tcCursor)
		GO TOP
		IF _screen.Visible
			IF EMPTY(lcTitle)
				BROWSE NOWAIT NOMODIFY NOAPPEND NODELETE NORMAL IN SCREEN
			ELSE
				BROWSE NOWAIT NOMODIFY NOAPPEND NODELETE NORMAL IN SCREEN TITLE lcTitle
			ENDIF
		ENDIF
		SET DATASESSION TO (lnDs)
	ENDPROC

	*-- Las ventanas abiertas vuelven a poner sus textos en el idioma de FoxDock.
	*-- Lo llama DataPlugin.BuildMenu, que el host vuelve a llamar al cambiar de
	*-- idioma (y al rehacer el menú: poner los mismos textos no cambia nada).
	*-- Una ventana que falla no para a las demás; el log lo dice.
	PROCEDURE Retext
		LOCAL loF, loErr
		FOR EACH loF IN This.oForms FOXOBJECT
			TRY
				IF PEMSTATUS(loF, "Texts", 5)
					loF.Texts()
				ENDIF
			CATCH TO loErr
				This.oHost.LogWarn("data.connections: the texts of " + loF.Name + " could not be put again: " + ;
					TRANSFORM(loErr.ErrorNo) + " " + loErr.Message)
			ENDTRY
		ENDFOR
	ENDPROC

	*-- Un formulario propio, modeless: se guarda para soltarlo al apagar.
	PROCEDURE ShowForm
		LPARAMETERS tcClass, toC, tvMore
		LOCAL loF
		*-- El tercero, solo a quien lo declara (un Init con dos da «Must specify
		*-- additional parameters» si recibe tres).
		IF PCOUNT() >= 3
			loF = NEWOBJECT(tcClass, This.Home() + "DataConnections.prg", "", This, toC, tvMore)
		ELSE
			loF = NEWOBJECT(tcClass, This.Home() + "DataConnections.prg", "", This, toC)
		ENDIF
		loF.cKey = SYS(2015)
		This.oForms.Add(loF, loF.cKey)
		loF.Show()
		RETURN loF
	ENDPROC

	PROCEDURE FormGone
		LPARAMETERS tcKey
		IF !EMPTY(tcKey) AND This.oForms.GetKey(tcKey) > 0
			This.oForms.Remove(tcKey)
		ENDIF
	ENDPROC
ENDDEFINE


*------------------------------------------------------------------
* DPAPI por DECLARE: CryptProtectData y CryptUnprotectData con la cuenta de
* Windows del usuario, sin diálogo (CRYPTPROTECT_UI_FORBIDDEN). Las
* funciones se declaran en cada llamada: un CLEAR DLLS del usuario se las
* lleva.
*------------------------------------------------------------------
DEFINE CLASS DataDpapi AS Custom
	nLastError = 0

	PROCEDURE Protect
		LPARAMETERS tcText
		RETURN This.Crypt(.T., tcText)
	ENDPROC

	PROCEDURE Unprotect
		LPARAMETERS tcBlob
		IF EMPTY(tcBlob)
			RETURN ""
		ENDIF
		RETURN This.Crypt(.F., tcBlob)
	ENDPROC

	PROTECTED PROCEDURE Crypt
		LPARAMETERS tlProtect, tcData
		LOCAL lnIn, lcIn, lcOut, lnOk, lnLen, lnPtr, lcRes
		DECLARE INTEGER CryptProtectData IN crypt32 AS FdDpapiProtect STRING @cIn, STRING cDescr, INTEGER pEntropy, ;
			INTEGER pReserved, INTEGER pPrompt, INTEGER dwFlags, STRING @cOut
		DECLARE INTEGER CryptUnprotectData IN crypt32 AS FdDpapiUnprotect STRING @cIn, INTEGER ppDescr, INTEGER pEntropy, ;
			INTEGER pReserved, INTEGER pPrompt, INTEGER dwFlags, STRING @cOut
		DECLARE INTEGER LocalAlloc IN kernel32 AS FdDpapiAlloc INTEGER uFlags, INTEGER uBytes
		DECLARE INTEGER LocalFree IN kernel32 AS FdDpapiFree INTEGER hMem
		DECLARE RtlMoveMemory IN kernel32 AS FdDpapiToPtr INTEGER nDest, STRING cSrc, INTEGER nLen
		DECLARE RtlMoveMemory IN kernel32 AS FdDpapiFromPtr STRING @cDest, INTEGER nSrc, INTEGER nLen
		DECLARE INTEGER GetLastError IN kernel32 AS FdDpapiLastError
		This.nLastError = 0
		lcRes = ""
		lnIn = FdDpapiAlloc(0x40, MAX(LEN(tcData), 1))
		FdDpapiToPtr(lnIn, tcData, LEN(tcData))
		lcIn = BINTOC(LEN(tcData), "4RS") + BINTOC(lnIn, "4RS")
		lcOut = REPLICATE(CHR(0), 8)
		IF tlProtect
			lnOk = FdDpapiProtect(@lcIn, STRCONV("FoxDock" + CHR(0), 5), 0, 0, 0, 1, @lcOut)
		ELSE
			lnOk = FdDpapiUnprotect(@lcIn, 0, 0, 0, 0, 1, @lcOut)
		ENDIF
		IF lnOk = 0
			This.nLastError = FdDpapiLastError()
		ELSE
			lnLen = CTOBIN(LEFT(lcOut, 4), "4RS")
			lnPtr = CTOBIN(SUBSTR(lcOut, 5, 4), "4RS")
			lcRes = SPACE(lnLen)
			FdDpapiFromPtr(@lcRes, lnPtr, lnLen)
			FdDpapiFree(lnPtr)
		ENDIF
		FdDpapiFree(lnIn)
		RETURN lcRes
	ENDPROC
ENDDEFINE


*------------------------------------------------------------------
* La guarda de ide_data_db_query y de Query...: una sola sentencia que
* empieza por SELECT o WITH. Se mira el texto sin los literales ('...'), los
* identificadores entre comillas ("...", [...], `...`) ni los comentarios
* (de «--» al salto de línea, y /* */): ahí dentro un ; o un DELETE no son
* SQL. Fuera:
*   - un ; con algo detrás: dos sentencias (un ; solo al final se quita)
*   - la primera palabra tiene que ser SELECT o WITH
*   - ninguna palabra que escribe o cambia algo (INSERT, UPDATE, DELETE,
*     DROP, ..., INTO de SELECT ... INTO, y FOR UPDATE): un WITH puede llevar
*     un DELETE dentro (PostgreSQL), y SELECT ... INTO crea una tabla.
* La guarda no basta sola: una función del servidor puede escribir desde un
* SELECT. El manual pide un usuario de solo lectura para el agente.
* Check devuelve "" (y la sentencia, sin el ; final, en cSql) o el motivo.
*------------------------------------------------------------------
DEFINE CLASS DataSqlGuard AS Custom
	cSql = ""
	cEngine = ""      && el motor, para decir con qué comillas se reescribe
	cStatement = ""   && la palabra con la que empieza la sentencia que pasa CheckWrite
	cWords = "INSERT UPDATE DELETE DROP ALTER CREATE TRUNCATE MERGE UPSERT EXEC EXECUTE CALL GRANT REVOKE " + ;
		"INTO ATTACH DETACH PRAGMA VACUUM COPY LOCK REINDEX RENAME SET DECLARE BEGIN COMMIT ROLLBACK"
	*-- Lo que no va en una escritura, en ningún sitio de ella (SET, INTO,
	*-- RENAME o DROP sí: los llevan UPDATE, INSERT y ALTER).
	cWriteWords = "EXEC EXECUTE CALL GRANT REVOKE ATTACH DETACH PRAGMA VACUUM COPY LOCK DECLARE BEGIN COMMIT ROLLBACK"

	*-- La guarda de ide_data_db_execute. Una sola sentencia de INSERT, UPDATE,
	*-- DELETE, CREATE, ALTER, DROP o TRUNCATE, mirada como Check (sin literales
	*-- ni comentarios: un where dentro de una cadena no cuenta). Un SELECT o un
	*-- WITH van a ide_data_db_query. Un UPDATE o un DELETE sin WHERE, un DROP y
	*-- un TRUNCATE, solo con tlWholeTable. Devuelve "" (y la sentencia en cSql,
	*-- y su palabra en cStatement) o el motivo.
	PROCEDURE CheckWrite
		LPARAMETERS tcSql, tlWholeTable
		LOCAL lcSql, lcCode, lcFirst, lcUp, lnW, lcW, lnLast
		LOCAL ARRAY laW[1]
		lcSql = ALLTRIM(TRANSFORM(tcSql), 1, " ", CHR(9), CHR(13), CHR(10))
		This.cSql = ""
		This.cStatement = ""
		IF EMPTY(lcSql)
			RETURN "the statement is empty"
		ENDIF
		lcCode = This.Code(lcSql)
		IF RIGHT(RTRIM(lcCode), 1) == ";"
			lnLast = RAT(";", lcCode)
			lcCode = LEFT(lcCode, lnLast - 1)
			lcSql = LEFT(lcSql, lnLast - 1)
		ENDIF
		IF ";" $ lcCode
			RETURN "it has more than one statement (a ';' with something after it): ide_data_db_execute runs one at a time"
		ENDIF
		lcUp = " " + UPPER(CHRTRAN(lcCode, "(),.;=<>+-*/%!|&^~:@#$?{}", SPACE(30))) + " "
		lcFirst = GETWORDNUM(lcUp, 1)
		DO CASE
			CASE INLIST(lcFirst, "SELECT", "WITH")
				RETURN "it is a " + lcFirst + ": reading goes through ide_data_db_query"
			CASE !INLIST(lcFirst, "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "TRUNCATE")
				RETURN "it starts with " + IIF(EMPTY(lcFirst), "nothing", "'" + lcFirst + "'") + ;
					": ide_data_db_execute runs one INSERT, UPDATE, DELETE, CREATE, ALTER, DROP or TRUNCATE"
		ENDCASE
		FOR lnW = 1 TO ALINES(laW, STRTRAN(This.cWriteWords, " ", CHR(13)), 1 + 4)
			lcW = laW[lnW]
			IF " " + lcW + " " $ lcUp
				RETURN "it has " + lcW + " in it" + This.Rewrite(lcW, lcUp)
			ENDIF
		ENDFOR
		IF !tlWholeTable
			DO CASE
				CASE lcFirst == "UPDATE" AND !(" WHERE " $ lcUp)
					RETURN "the UPDATE has no WHERE: it would change every row of the table; pass wholeTable: true if that is what you mean"
				CASE lcFirst == "DELETE" AND !(" WHERE " $ lcUp)
					RETURN "the DELETE has no WHERE: it would delete every row of the table; pass wholeTable: true if that is what you mean"
				CASE lcFirst == "TRUNCATE"
					RETURN "a TRUNCATE empties the whole table; pass wholeTable: true if that is what you mean"
				CASE lcFirst == "DROP"
					RETURN "a DROP removes the whole table; pass wholeTable: true if that is what you mean"
			ENDCASE
		ENDIF
		This.cStatement = lcFirst
		This.cSql = ALLTRIM(lcSql, 1, " ", CHR(9), CHR(13), CHR(10))
		RETURN ""
	ENDPROC

	PROCEDURE Check
		LPARAMETERS tcSql
		LOCAL lcSql, lcCode, lcFirst, lcUp, lnW, lcW, lnLast
		LOCAL ARRAY laW[1]
		lcSql = ALLTRIM(TRANSFORM(tcSql), 1, " ", CHR(9), CHR(13), CHR(10))
		This.cSql = ""
		IF EMPTY(lcSql)
			RETURN "is empty"
		ENDIF
		lcCode = This.Code(lcSql)
		IF RIGHT(RTRIM(lcCode), 1) == ";"
			lnLast = RAT(";", lcCode)
			lcCode = LEFT(lcCode, lnLast - 1)
			lcSql = LEFT(lcSql, lnLast - 1)
		ENDIF
		IF ";" $ lcCode
			RETURN "has more than one statement (a ';' with something after it)"
		ENDIF
		lcUp = " " + UPPER(CHRTRAN(lcCode, "(),.;=<>+-*/%!|&^~:@#$?{}", SPACE(30))) + " "
		lcFirst = GETWORDNUM(lcUp, 1)
		IF !INLIST(lcFirst, "SELECT", "WITH")
			RETURN "starts with " + IIF(EMPTY(lcFirst), "nothing", "'" + lcFirst + "'")
		ENDIF
		FOR lnW = 1 TO ALINES(laW, STRTRAN(This.cWords, " ", CHR(13)), 1 + 4)
			lcW = laW[lnW]
			IF " " + lcW + " " $ lcUp
				RETURN "has " + lcW + " in it" + This.Rewrite(lcW, lcUp)
			ENDIF
		ENDFOR
		This.cSql = ALLTRIM(lcSql, 1, " ", CHR(9), CHR(13), CHR(10))
		RETURN ""
	ENDPROC

	*-- Cómo se reescribe un falso positivo: FOR UPDATE es un bloqueo y
	*-- sobra; una columna o una tabla con ese nombre va entre las comillas del
	*-- motor (cEngine, si lo puso quien llama).
	PROCEDURE Rewrite
		LPARAMETERS tcWord, tcUp
		LOCAL lcQ
		IF tcWord == "UPDATE" AND " FOR UPDATE " $ tcUp
			RETURN " (FOR UPDATE locks rows: leave it out, the agent only reads)"
		ENDIF
		DO CASE
			CASE This.cEngine == "sqlserver"
				lcQ = "[" + LOWER(tcWord) + "]"
			CASE INLIST(This.cEngine, "mysql", "mariadb")
				lcQ = "`" + LOWER(tcWord) + "`"
			OTHERWISE
				lcQ = ["] + LOWER(tcWord) + ["]
		ENDCASE
		RETURN " (if it is not a statement: a column or a table called " + LOWER(tcWord) + ;
			" goes in the quotes of the engine (" + lcQ + " here))"
	ENDPROC

	*-- El código sin literales ni comentarios: cada carácter de dentro (y los
	*-- tabuladores y saltos), un espacio; mismo largo que tcSql, para que los
	*-- «;» caigan en su sitio. Un comentario «--» acaba en el salto de línea.
	PROTECTED PROCEDURE Code
		LPARAMETERS tcSql
		LOCAL lcSql, lcCode, lnLen, lnI, lcC, lcState
		lcSql = tcSql
		lcCode = ""
		lcState = ""
		lnLen = LEN(lcSql)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcC = SUBSTR(lcSql, lnI, 1)
			DO CASE
				CASE lcState == "'" OR lcState == ["] OR lcState == "`"
					IF lcC == lcState
						IF SUBSTR(lcSql, lnI + 1, 1) == lcState
							lcCode = lcCode + "  "
							lnI = lnI + 2
							LOOP
						ENDIF
						lcState = ""
					ENDIF
					lcCode = lcCode + " "
				CASE lcState == "["
					IF lcC == "]"
						lcState = ""
					ENDIF
					lcCode = lcCode + " "
				CASE lcState == "--"
					IF INLIST(lcC, CHR(13), CHR(10))
						lcState = ""
					ENDIF
					lcCode = lcCode + " "
				CASE lcState == "/*"
					IF lcC == "*" AND SUBSTR(lcSql, lnI + 1, 1) == "/"
						lcCode = lcCode + "  "
						lnI = lnI + 2
						lcState = ""
						LOOP
					ENDIF
					lcCode = lcCode + " "
				CASE lcC == "-" AND SUBSTR(lcSql, lnI + 1, 1) == "-"
					lcState = "--"
					lcCode = lcCode + " "
				CASE lcC == "/" AND SUBSTR(lcSql, lnI + 1, 1) == "*"
					lcState = "/*"
					lcCode = lcCode + "  "
					lnI = lnI + 2
					LOOP
				CASE INLIST(lcC, "'", ["], "`", "[")
					lcState = lcC
					lcCode = lcCode + " "
				CASE INLIST(lcC, CHR(9), CHR(13), CHR(10))
					lcCode = lcCode + " "
				OTHERWISE
					lcCode = lcCode + lcC
			ENDCASE
			lnI = lnI + 1
		ENDDO
		RETURN lcCode
	ENDPROC
ENDDEFINE


*==================================================================
* Los formularios: modeless, sin MESSAGEBOX. Cada botón pone SET TALK OFF
* mientras dura (con el SET TALK ON del IDE, cada asignación saldría en la
* barra de estado). Al cerrarse, se quitan de la lista del módulo.
*==================================================================
DEFINE CLASS DataConnectionForm AS Form
	AutoCenter = .T.
	MaxButton = .F.
	MinButton = .F.
	ShowWindow = 0
	WindowType = 0
	BorderStyle = 2
	oModule = .NULL.
	cConnId = ""
	cConnName = ""
	cKey = ""
	cKind = ""        && explore, query, view, export o connect
	cTitleEn = ""     && su nombre en el log («Explore...», «Query...»)
	cCursors = ""     && los cursores que abrió, separados por comas

	PROCEDURE Init
		LPARAMETERS toModule, toC
		This.oModule = toModule
		This.cConnId = toC.cId
		This.cConnName = toC.cName
		*-- Un Name por ventana y conexión (FoxDockExplore_shop): las tools de
		*-- FoxAgent con formName eligen la que no está delante. Con el de la clase,
		*-- dos Explore se llamarían igual.
		This.cKind = STRTRAN(STRTRAN(LOWER(This.Class), "data", "", 1, 1), "form", "")
		This.Name = "FoxDock" + PROPER(This.cKind) + "_" + ;
			CHRTRAN(toC.cId, CHRTRAN(LOWER(toC.cId), "abcdefghijklmnopqrstuvwxyz0123456789_", ""), REPLICATE("_", 64))
	ENDPROC

	PROCEDURE Destroy
		This.CursorsGone()
		IF VARTYPE(This.oModule) == "O"
			This.oModule.FormGone(This.cKey)
		ENDIF
		This.oModule = .NULL.
	ENDPROC

	*-- Help: la sección de esta ventana en la ayuda de los plugins (PLUGINS), en
	*-- el navegador; el anclaje, el texto del idioma data.help.<cKind>.anchor.
	PROCEDURE ShowHelp
		RETURN This.oModule.oHost.OpenHelp("PLUGINS", This.oModule.T("data.help." + This.cKind + ".anchor"))
	ENDPROC

	PROCEDURE Keep
		LPARAMETERS tcAlias
		IF !("," + LOWER(tcAlias) + "," $ "," + This.cCursors + ",")
			This.cCursors = This.cCursors + IIF(EMPTY(This.cCursors), "", ",") + LOWER(tcAlias)
		ENDIF
	ENDPROC

	*-- Los cursores que abrió (y sus BROWSE con ellos).
	PROCEDURE CloseCursors
		LOCAL lnI, lcA, lnDs
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		FOR lnI = 1 TO GETWORDCOUNT(This.cCursors, ",")
			lcA = GETWORDNUM(This.cCursors, lnI, ",")
			IF USED(lcA)
				USE IN (lcA)
			ENDIF
		ENDFOR
		This.cCursors = ""
		SET DATASESSION TO (lnDs)
	ENDPROC

	*-- toCtl detrás de su etiqueta toLabel, con 8 px de hueco, y acabando donde
	*-- acababa (la ventana no crece): en otro idioma, una etiqueta más larga no
	*-- queda debajo del control. El texto se mide con TXTWIDTH, porque en el
	*-- Init el Width de una etiqueta AutoSize no es el de su texto nuevo. Si ya
	*-- cabía, no se mueve. El Anchor se pone a 0 y se devuelve: el anclaje va
	*-- por la posición de cuando se puso, y sin eso el control volvería a la de
	*-- antes al estirar la ventana.
	PROCEDURE AfterLabel
		LPARAMETERS toLabel, toCtl
		LOCAL lcStyle, lnW, lnRight, lnAnchor
		lcStyle = IIF(toLabel.FontBold, "B", "N")
		lnW = CEILING(TXTWIDTH(STRTRAN(toLabel.Caption, "\<", ""), toLabel.FontName, toLabel.FontSize, lcStyle) * ;
			FONTMETRIC(6, toLabel.FontName, toLabel.FontSize, lcStyle))
		IF toLabel.Left + lnW + 8 <= toCtl.Left
			RETURN
		ENDIF
		lnRight = toCtl.Left + toCtl.Width
		lnAnchor = toCtl.Anchor
		toCtl.Anchor = 0
		toCtl.Left = toLabel.Left + lnW + 8
		toCtl.Width = lnRight - toCtl.Left
		toCtl.Anchor = lnAnchor
	ENDPROC

	*-- Los botones de un grupo, uno detrás de otro, ajustados a su texto: con
	*-- AutoSize y sin tocar su Top, VFP los deja apilados por debajo de un grupo
	*-- de una fila. Si no caben en tnMax, siguen en otra fila; el grupo mide lo
	*-- que ocupan. En la base, para Export... y Script as....
	PROCEDURE LayoutOptions
		LPARAMETERS toG, tnMax
		LOCAL lnI, loB, lnLeft, lnTop, lnRight
		STORE 0 TO lnLeft, lnRight
		lnTop = 5
		FOR lnI = 1 TO toG.ButtonCount
			loB = toG.Buttons(lnI)
			loB.AutoSize = .T.
			IF lnI > 1 AND lnLeft + loB.Width > tnMax
				lnLeft = 0
				lnTop = lnTop + loB.Height + 4
			ENDIF
			loB.Left = lnLeft
			loB.Top = lnTop
			lnRight = MAX(lnRight, lnLeft + loB.Width)
			lnLeft = lnLeft + loB.Width + 16
		ENDFOR
		toG.Width = lnRight + 2
		toG.Height = lnTop + loB.Height + 5
	ENDPROC

	*-- Al cerrarse, los cursores que abrió se van con ella, salvo con su casilla
	*-- «Keep the cursors open when it closes» (chkKeep, en Explore... y
	*-- Query...), que se guarda por ventana. CloseExplore (desconectar, Reload)
	*-- los cierra antes, siempre.
	PROCEDURE CursorsGone
		LOCAL loM
		loM = This.oModule
		IF !PEMSTATUS(This, "chkKeep", 5) OR VARTYPE(loM) # "O"
			RETURN
		ENDIF
		loM.SaveKeepCursors(This.cKind, This.chkKeep.Value)
		DO CASE
			CASE EMPTY(This.cCursors)
			CASE This.chkKeep.Value
				loM.oHost.NotifyKey("data.cursors.kept", This.cConnName, STRTRAN(This.cCursors, ",", ", "))
			OTHERWISE
				loM.oHost.Log("data.connections: " + This.cTitleEn + " of '" + This.cConnId + "' closed its cursors: " + ;
					STRTRAN(This.cCursors, ",", ", "))
				This.CloseCursors()
		ENDCASE
	ENDPROC
ENDDEFINE


*-- Connect... de una conexión que necesita contraseña y no tiene una guardada.
DEFINE CLASS DataConnectForm AS DataConnectionForm
	Width = 420
	Height = 190

	ADD OBJECT lblWhere AS Label WITH Left = 10, Top = 12, Width = 400, Height = 34, WordWrap = .T.
	ADD OBJECT lblPassword AS Label WITH Caption = "\<Password", Left = 10, Top = 58, AutoSize = .T.
	ADD OBJECT txtPassword AS TextBox WITH Left = 90, Top = 54, Width = 320, PasswordChar = "*"
	ADD OBJECT chkRemember AS CheckBox WITH Caption = "\<Remember it (encrypted with your Windows account)", ;
		Left = 90, Top = 84, AutoSize = .T., Value = .F.
	ADD OBJECT lblError AS Label WITH Caption = "", Left = 10, Top = 108, Width = 400, Height = 40, WordWrap = .T., ;
		ForeColor = RGB(170, 0, 0)
	ADD OBJECT cmdHelp AS CommandButton WITH Caption = "\<Help", Left = 10, Top = 152, Width = 90, Height = 28
	ADD OBJECT cmdConnect AS CommandButton WITH Caption = "\<Connect", Left = 220, Top = 152, Width = 90, Height = 28, ;
		Default = .T.
	ADD OBJECT cmdCancel AS CommandButton WITH Caption = "Cancel", Left = 320, Top = 152, Width = 90, Height = 28, ;
		Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, toC
		DODEFAULT(toModule, toC)
		This.Texts()
	ENDPROC

	*-- Los textos, en el idioma de FoxDock, también al cambiarlo con la ventana
	*-- abierta (DataConnections.Retext).
	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM, loC
		loM = This.oModule
		loC = loM.Find(This.cConnId)
		This.Caption = loM.T("data.connect.caption", loC.cName)
		This.lblWhere.Caption = loM.T("data.connect.where", loC.cEngine, IIF(EMPTY(loC.cServer), "", ", " + loC.cServer), ;
			IIF(EMPTY(loC.cDatabase), loM.T("data.connect.noDatabase"), loC.cDatabase), loC.cUser)
		This.lblPassword.Caption = loM.T("data.connect.password")
		This.chkRemember.Caption = loM.T("data.connect.remember")
		This.cmdConnect.Caption = loM.T("data.connect.connect")
		This.cmdCancel.Caption = loM.T("data.connect.cancel")
	ENDPROC

	PROCEDURE cmdConnect.Click
		LOCAL lcTalk, llOk, loM, lcId
		lcTalk = SET("TALK")
		SET TALK OFF
		loM = Thisform.oModule
		lcId = Thisform.cConnId
		Thisform.lblError.Caption = loM.T("data.connect.connecting")
		*-- El cuadro rellena lo tecleado con espacios hasta su ancho: se quitan los
		*-- del final. Una contraseña que acabe en espacio los pierde; los del
		*-- principio se quedan (Format = "T" se llevaría también esos).
		llOk = loM.Connect(lcId, RTRIM(Thisform.txtPassword.Value), Thisform.chkRemember.Value)
		Thisform.txtPassword.Value = ""
		IF llOk
			loM.oHost.NotifyKey("data.conn.connected", Thisform.cConnName)
			Thisform.Release()
		ELSE
			Thisform.lblError.Caption = loM.cLastError
			loM.oHost.NotifyQuoted("data.said", loM.cLastError)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdCancel.Click
		Thisform.txtPassword.Value = ""
		Thisform.Release()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC
ENDDEFINE


*-- Explore...: la ventana de una conexión. Arriba la base (el combo,
*-- deshabilitado en SQLite y Firebird); la lista de tablas y vistas con su
*-- filtro al teclear (contiene, sin distinguir mayúsculas) y la cuenta, y
*-- Columns y Browse de la elegida, con el límite de Query... Lo que dice va
*-- en su cuadro, en la barra de estado y en el log. Los cursores de Columns
*-- y Browse se van al cerrarla, salvo con «Keep the cursors open when it
*-- closes» (CursorsGone, en la base), y siempre si se cierra la conexión
*-- (CloseExplore). ENTER en el filtro lleva a la lista, y el combo de al
*-- lado filtra tablas, vistas o las dos. Se estira (BorderStyle 3,
*-- maximizar) con la lista; las filas de botones y el cuadro de abajo se
*-- quedan pegados abajo. Script as..., al lado de Create view...; la casilla
*-- de los cursores, en su fila.
DEFINE CLASS DataExploreForm AS DataConnectionForm
	lFirstLoad = .T.  && la primera carga de la lista pone el combo en «Tablas»
	Width = 520
	Height = 522
	BorderStyle = 3
	MaxButton = .T.
	MinWidth = 520
	MinHeight = 522
	cEngine = ""
	cTitleEn = "Explore..."
	nTotal = 0        && las tablas y vistas de la base, sin filtro
	nShown = -1       && lo que enseña la lista y las del tipo del combo, para
	nOfKind = 0       && volver a decir la cuenta en otro idioma (-1: sin contar aún)
	DIMENSION aObjects[1, 2]

	ADD OBJECT lblDatabase AS Label WITH Caption = "\<Database", Left = 10, Top = 14, AutoSize = .T.
	ADD OBJECT cboDatabase AS ComboBox WITH Left = 80, Top = 10, Width = 430, Height = 24, Style = 2, Anchor = 11
	ADD OBJECT lblFilter AS Label WITH Caption = "\<Filter", Left = 10, Top = 46, AutoSize = .T.
	ADD OBJECT txtFilter AS TextBox WITH Left = 80, Top = 42, Width = 250, Height = 24, Value = ""
	*-- Tablas, vistas o las dos; la cuenta, debajo, dice las que pasan los dos filtros.
	ADD OBJECT cboKind AS ComboBox WITH Left = 338, Top = 42, Width = 172, Height = 24, Style = 2, Anchor = 9
	ADD OBJECT lblCount AS Label WITH Caption = "", Left = 80, Top = 72, Width = 430, Height = 18, Anchor = 11
	ADD OBJECT lstObjects AS ListBox WITH Left = 10, Top = 94, Width = 500, Height = 210, ColumnCount = 2, ;
		ColumnWidths = "400,70", Anchor = 15
	ADD OBJECT cmdColumns AS CommandButton WITH Caption = "\<Columns", Left = 10, Top = 312, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT cmdBrowse AS CommandButton WITH Caption = "\<Browse", Left = 110, Top = 312, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT lblLimit AS Label WITH Caption = "\<Limit", Left = 214, Top = 318, AutoSize = .T., Anchor = 6
	ADD OBJECT spnLimit AS Spinner WITH Left = 250, Top = 314, Width = 80, Height = 24, Value = 100, ;
		SpinnerLowValue = 0, SpinnerHighValue = 1000000, KeyboardLowValue = 0, KeyboardHighValue = 1000000, Increment = 100, ;
		Anchor = 6
	ADD OBJECT lblNoLimit AS Label WITH Caption = "rows (0 = no limit)", Left = 336, Top = 318, AutoSize = .T., Anchor = 6
	ADD OBJECT cmdExport AS CommandButton WITH Caption = "E\<xport...", Left = 10, Top = 346, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT cmdView AS CommandButton WITH Caption = "Create \<view...", Left = 110, Top = 346, Width = 100, Height = 28, ;
		Anchor = 6
	ADD OBJECT cmdScript AS CommandButton WITH Caption = "Script as...", Left = 220, Top = 346, Width = 100, Height = 28, ;
		Anchor = 6
	*-- To object: las filas de la elegida a una Collection PUBLIC, con el nombre de abajo.
	ADD OBJECT cmdObject AS CommandButton WITH Caption = "To \<object", Left = 330, Top = 346, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT lblObject AS Label WITH Caption = "Variable", Left = 300, Top = 384, AutoSize = .T., Anchor = 6
	ADD OBJECT txtObject AS TextBox WITH Left = 360, Top = 380, Width = 150, Height = 24, Value = "", MaxLength = 128, Anchor = 6
	ADD OBJECT chkKeep AS CheckBox WITH Caption = "Keep the cursors open when it closes", Left = 10, Top = 382, ;
		AutoSize = .T., Value = .F., Anchor = 6
	ADD OBJECT edtSay AS EditBox WITH Left = 10, Top = 404, Width = 500, Height = 74, ReadOnly = .T., ScrollBars = 2, ;
		Value = "", Anchor = 14
	ADD OBJECT cmdHelp AS CommandButton WITH Caption = "\<Help", Left = 10, Top = 486, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT cmdClose AS CommandButton WITH Caption = "Close", Left = 420, Top = 486, Width = 90, Height = 28, Cancel = .T., ;
		Anchor = 12

	PROCEDURE Init
		LPARAMETERS toModule, toC
		LOCAL lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		DODEFAULT(toModule, toC)
		This.cEngine = toC.cEngine
		This.Caption = "FoxDock - " + toC.cName
		This.Texts()
		This.chkKeep.Value = toModule.KeepCursors("explore")
		This.spnLimit.Value = toModule.QueryLimit()
		This.FillDatabases()
		This.LoadObjects()
		toModule.oHost.Log("data.connections: Explore... of '" + This.cConnId + "': database " + ;
			toModule.CurrentDatabase(This.cConnId) + ", " + TRANSFORM(This.nTotal) + " tables and views")
		SET TALK &lcTalk
	ENDPROC

	*-- El combo: las bases del servidor y la actual elegida; en SQLite y
	*-- Firebird, el fichero, deshabilitado.
	PROCEDURE FillDatabases
		LOCAL loM, lcCur, lnN, lcNow, lnDs, llIn
		loM = This.oModule
		lcNow = loM.CurrentDatabase(This.cConnId)
		This.cboDatabase.Clear()
		IF INLIST(This.cEngine, "sqlite", "firebird")
			This.cboDatabase.AddItem(lcNow)
			This.cboDatabase.Value = lcNow
			This.cboDatabase.Enabled = .F.
			RETURN
		ENDIF
		lcCur = "FDD" + SYS(2015)
		lnN = loM.Databases(This.cConnId, lcCur)
		llIn = .F.
		IF lnN < 0
			loM.ExploreSay(This, loM.cLastError)
		ELSE
			lnDs = SET("DATASESSION")
			SET DATASESSION TO 1
			SELECT (lcCur)
			SCAN
				This.cboDatabase.AddItem(ALLTRIM(name))
				llIn = llIn OR LOWER(ALLTRIM(name)) == LOWER(lcNow)
			ENDSCAN
			USE IN (lcCur)
			SET DATASESSION TO (lnDs)
		ENDIF
		*-- La actual, aunque el servidor no la liste.
		IF !llIn AND !EMPTY(lcNow)
			This.cboDatabase.AddItem(lcNow)
		ENDIF
		This.cboDatabase.Value = lcNow
	ENDPROC

	*-- Las tablas y vistas de la base actual, a aObjects, y la lista.
	PROCEDURE LoadObjects
		LOCAL loM, lcCur, lnN, lnDs, llWas
		loM = This.oModule
		lcCur = "FDO" + SYS(2015)
		lnN = loM.TablesAndViews(This.cConnId, lcCur)
		This.nTotal = 0
		DIMENSION This.aObjects[1, 2]
		This.aObjects[1, 1] = ""
		This.aObjects[1, 2] = ""
		IF lnN < 0
			loM.ExploreSay(This, loM.cLastError)
		ELSE
			lnDs = SET("DATASESSION")
			SET DATASESSION TO 1
			IF lnN > 0
				DIMENSION This.aObjects[lnN, 2]
				SELECT (lcCur)
				SCAN
					This.nTotal = This.nTotal + 1
					This.aObjects[This.nTotal, 1] = ALLTRIM(name)
					This.aObjects[This.nTotal, 2] = ALLTRIM(type)
				ENDSCAN
			ENDIF
			USE IN (lcCur)
			SET DATASESSION TO (lnDs)
			IF lnN = 0
				loM.ExploreSayKey(This, "data.explore.empty", loM.CurrentDatabase(This.cConnId))
			ENDIF
		ENDIF
		*-- Con un solo tipo en la base (o ninguno), el combo no filtraría nada. Con
		*-- los dos, «Tablas» al abrir y al pasar a una base que los tiene; si no, lo
		*-- que eligió el usuario.
		llWas = This.cboKind.Enabled AND !This.lFirstLoad
		This.cboKind.Enabled = This.HasBothKinds()
		DO CASE
			CASE !This.cboKind.Enabled
				This.cboKind.ListIndex = 1
			CASE !llWas
				This.cboKind.ListIndex = 2
		ENDCASE
		This.lFirstLoad = .F.
		This.ApplyFilter()
	ENDPROC

	*-- Los textos, en el idioma de FoxDock, también al cambiarlo con la ventana
	*-- abierta, con el tipo elegido en el combo, sin tocar la lista (ni su fila
	*-- elegida) ni el filtro.
	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM, lnKind, lnI
		loM = This.oModule
		This.lblDatabase.Caption = loM.T("data.explore.database")
		This.AfterLabel(This.lblDatabase, This.cboDatabase)
		This.lblFilter.Caption = loM.T("data.explore.filter")
		This.cmdColumns.Caption = loM.T("data.explore.columns")
		This.cmdBrowse.Caption = loM.T("data.explore.browse")
		This.lblLimit.Caption = loM.T("data.explore.limit")
		This.lblNoLimit.Caption = loM.T("data.explore.noLimit")
		This.cmdExport.Caption = loM.T("data.explore.export")
		This.cmdView.Caption = loM.T("data.explore.view")
		This.cmdScript.Caption = loM.T("data.explore.script")
		This.cmdObject.Caption = loM.T("data.object.button")
		This.lblObject.Caption = loM.T("data.object.name")
		This.AfterLabel(This.lblObject, This.txtObject)
		This.cmdClose.Caption = loM.T("data.explore.close")
		This.chkKeep.Caption = loM.T("data.cursors.keep")
		lnKind = This.cboKind.ListIndex
		This.cboKind.Clear()
		This.cboKind.AddItem(loM.T("data.explore.kindAll"))
		This.cboKind.AddItem(loM.T("data.explore.kindTables"))
		This.cboKind.AddItem(loM.T("data.explore.kindViews"))
		This.cboKind.ListIndex = MAX(1, lnKind)
		This.CountText()
		*-- La columna del tipo, en el idioma nuevo, sin rehacer la lista.
		FOR lnI = 1 TO This.lstObjects.ListCount
			This.lstObjects.List(lnI, 2) = This.KindText(This.KindOf(This.lstObjects.List(lnI, 1)))
		ENDFOR
	ENDPROC

	*-- El tipo de la segunda columna, en el idioma de FoxDock; lo que no es
	*-- tabla ni vista, tal cual. aObjects y lo que lee el agente siguen diciendo
	*-- table y view.
	PROCEDURE KindText
		LPARAMETERS tcKind
		DO CASE
			CASE LOWER(ALLTRIM(tcKind)) == "table"
				RETURN This.oModule.T("data.explore.typeTable")
			CASE LOWER(ALLTRIM(tcKind)) == "view"
				RETURN This.oModule.T("data.explore.typeView")
		ENDCASE
		RETURN tcKind
	ENDPROC

	*-- El tipo (table, view) de un objeto de aObjects por su nombre, o "".
	PROCEDURE KindOf
		LPARAMETERS tcName
		LOCAL lnI
		FOR lnI = 1 TO This.nTotal
			IF ALLTRIM(This.aObjects[lnI, 1]) == ALLTRIM(tcName)
				RETURN This.aObjects[lnI, 2]
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- La cuenta de debajo del filtro, de lo que dejó ApplyFilter (según el combo).
	PROCEDURE CountText
		LOCAL lcKind
		IF This.nShown < 0
			RETURN
		ENDIF
		lcKind = ICASE(This.cboKind.ListIndex = 2, "table", This.cboKind.ListIndex = 3, "view", "")
		This.lblCount.Caption = This.oModule.T(ICASE(lcKind == "table", "data.explore.countTables", lcKind == "view", ;
			"data.explore.countViews", "data.explore.count"), This.nShown, This.nOfKind)
	ENDPROC

	*-- Si en aObjects hay tablas y vistas.
	PROCEDURE HasBothKinds
		LOCAL lnI, llTable, llView
		STORE .F. TO llTable, llView
		FOR lnI = 1 TO This.nTotal
			llTable = llTable OR LOWER(This.aObjects[lnI, 2]) == "table"
			llView = llView OR LOWER(This.aObjects[lnI, 2]) == "view"
		ENDFOR
		RETURN llTable AND llView
	ENDPROC

	*-- La lista con las que contienen el filtro, sin distinguir mayúsculas, y son
	*-- del tipo del combo, y la cuenta.
	PROCEDURE ApplyFilter
		LOCAL lcF, lnI, lnShown, lcKind, lnOfKind
		lcF = LOWER(ALLTRIM(TRANSFORM(This.txtFilter.Value)))
		lcKind = ICASE(This.cboKind.ListIndex = 2, "table", This.cboKind.ListIndex = 3, "view", "")
		This.lstObjects.Clear()
		lnShown = 0
		lnOfKind = 0
		FOR lnI = 1 TO This.nTotal
			lnOfKind = lnOfKind + IIF(EMPTY(lcKind) OR LOWER(This.aObjects[lnI, 2]) == lcKind, 1, 0)
			IF (EMPTY(lcF) OR lcF $ LOWER(This.aObjects[lnI, 1])) AND (EMPTY(lcKind) OR LOWER(This.aObjects[lnI, 2]) == lcKind)
				This.lstObjects.AddItem(This.aObjects[lnI, 1])
				lnShown = lnShown + 1
				This.lstObjects.List(lnShown, 2) = This.KindText(This.aObjects[lnI, 2])
			ENDIF
		ENDFOR
		*-- La cuenta, de lo que deja el combo.
		This.nShown = lnShown
		This.nOfKind = lnOfKind
		This.CountText()
	ENDPROC

	*-- La elegida en la lista, o "".
	PROCEDURE Chosen
		IF This.lstObjects.ListIndex < 1
			RETURN ""
		ENDIF
		RETURN ALLTRIM(This.lstObjects.List(This.lstObjects.ListIndex, 1))
	ENDPROC

	*-- Elige tcName en la lista (lo usan los tests). .F. si no está.
	PROCEDURE SelectObject
		LPARAMETERS tcName
		LOCAL lnI
		FOR lnI = 1 TO This.lstObjects.ListCount
			IF LOWER(ALLTRIM(This.lstObjects.List(lnI, 1))) == LOWER(ALLTRIM(tcName))
				This.lstObjects.ListIndex = lnI
				RETURN .T.
			ENDIF
		ENDFOR
		*-- Con «Tablas» de entrada, una vista no está en la lista. Si está en la
		*-- conexión, «Tablas y vistas» sin filtro, y se busca otra vez.
		IF This.cboKind.ListIndex # 1 OR !EMPTY(This.txtFilter.Value)
			FOR lnI = 1 TO This.nTotal
				IF LOWER(ALLTRIM(This.aObjects[lnI, 1])) == LOWER(ALLTRIM(tcName))
					This.cboKind.ListIndex = 1
					This.txtFilter.Value = ""
					This.ApplyFilter()
					RETURN This.SelectObject(tcName)
				ENDIF
			ENDFOR
		ENDIF
		RETURN .F.
	ENDPROC

	*-- Otra base del combo: UseDatabase, y la lista otra vez.
	PROCEDURE ChangeDatabase
		LOCAL loM, lcDb, lcId, lcTalk
		loM = This.oModule
		lcId = This.cConnId
		lcDb = ALLTRIM(TRANSFORM(This.cboDatabase.Value))
		IF EMPTY(lcDb) OR LOWER(lcDb) == LOWER(loM.CurrentDatabase(lcId))
			RETURN
		ENDIF
		lcTalk = SET("TALK")
		SET TALK OFF
		IF loM.UseDatabase(lcId, lcDb)
			This.LoadObjects()
			loM.ExploreSayKey(This, "data.explore.nowIn", This.cConnName, loM.CurrentDatabase(lcId), This.nTotal)
		ELSE
			IF loM.IsConnected(lcId)
				loM.ExploreSay(This, loM.cLastError)
				This.cboDatabase.Value = loM.CurrentDatabase(lcId)
			ELSE
				*-- La conexión se cerró, y esta ventana con ella: solo el aviso.
				loM.oHost.NotifyQuoted("data.said", loM.cLastError)
			ENDIF
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cboDatabase.InteractiveChange
		Thisform.ChangeDatabase()
	ENDPROC

	PROCEDURE txtFilter.InteractiveChange
		Thisform.ApplyFilter()
	ENDPROC

	*-- ENTER lleva el foco a la lista, con la primera fila si no había ninguna
	*-- elegida. NODEFAULT: sin él, el foco se va al control siguiente. ESC sigue
	*-- cerrando.
	PROCEDURE txtFilter.KeyPress
		LPARAMETERS nKeyCode, nShiftAltCtrl
		IF nKeyCode = 13
			NODEFAULT
			IF Thisform.lstObjects.ListCount > 0 AND Thisform.lstObjects.ListIndex < 1
				Thisform.lstObjects.ListIndex = 1
			ENDIF
			Thisform.lstObjects.SetFocus()
		ENDIF
	ENDPROC

	PROCEDURE cboKind.InteractiveChange
		Thisform.ApplyFilter()
	ENDPROC

	PROCEDURE cmdColumns.Click
		LOCAL lcTalk, lcName
		lcTalk = SET("TALK")
		SET TALK OFF
		lcName = Thisform.Chosen()
		IF EMPTY(lcName)
			Thisform.oModule.ExploreSayKey(Thisform, "data.explore.chooseFirst")
		ELSE
			=Thisform.oModule.ExploreColumns(Thisform, lcName)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	*-- Sin nombre, el propuesto (loG10_cl).
	PROCEDURE cmdObject.Click
		LOCAL lcTalk, lcName, lnLimit
		lcTalk = SET("TALK")
		SET TALK OFF
		lcName = Thisform.Chosen()
		lnLimit = MAX(INT(Thisform.spnLimit.Value), 0)
		IF EMPTY(lcName)
			Thisform.oModule.ExploreSayKey(Thisform, "data.explore.chooseFirst")
		ELSE
			IF EMPTY(ALLTRIM(Thisform.txtObject.Value))
				Thisform.txtObject.Value = Thisform.oModule.ObjectVarName(lcName)
			ENDIF
			=Thisform.oModule.ExploreToObject(Thisform, lcName, lnLimit, ALLTRIM(Thisform.txtObject.Value))
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdBrowse.Click
		LOCAL lcTalk, lcName, lnLimit
		lcTalk = SET("TALK")
		SET TALK OFF
		lcName = Thisform.Chosen()
		lnLimit = MAX(INT(Thisform.spnLimit.Value), 0)
		Thisform.oModule.SaveQueryLimit(lnLimit)
		IF EMPTY(lcName)
			Thisform.oModule.ExploreSayKey(Thisform, "data.explore.chooseFirst")
		ELSE
			=Thisform.oModule.ExploreBrowse(Thisform, lcName, lnLimit)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdExport.Click
		LOCAL lcTalk, lcName
		lcTalk = SET("TALK")
		SET TALK OFF
		lcName = Thisform.Chosen()
		IF EMPTY(lcName)
			Thisform.oModule.ExploreSayKey(Thisform, "data.explore.chooseFirst")
		ELSE
			=Thisform.oModule.ExportBar(Thisform, lcName)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdView.Click
		LOCAL lcTalk, lcName
		lcTalk = SET("TALK")
		SET TALK OFF
		lcName = Thisform.Chosen()
		IF EMPTY(lcName)
			Thisform.oModule.ExploreSayKey(Thisform, "data.explore.chooseFirst")
		ELSE
			=Thisform.oModule.ViewBar(Thisform, lcName)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdScript.Click
		LOCAL lcTalk, lcName
		lcTalk = SET("TALK")
		SET TALK OFF
		lcName = Thisform.Chosen()
		IF EMPTY(lcName)
			Thisform.oModule.ExploreSayKey(Thisform, "data.explore.chooseFirst")
		ELSE
			=Thisform.oModule.ScriptBar(Thisform, lcName)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC
ENDDEFINE


*-- Script as... de Explore...: los scripts CREATE, INSERT y UPDATE de la
*-- tabla elegida, sin abrirla. El tipo, el dialecto (para empezar, el del
*-- motor de la conexión; para esta vez: no cambia options.data.script.dialect),
*-- las filas y el destino, el editor o el portapapeles. Lo hace
*-- DataScript.RemoteScript.
DEFINE CLASS DataScriptForm AS DataConnectionForm
	Width = 520
	Height = 286
	cTable = ""
	cDialects = ""    && los ids de los dialectos, en el orden del combo

	ADD OBJECT lblKind AS Label WITH Caption = "Script", Left = 10, Top = 16, AutoSize = .T.
	ADD OBJECT optKind AS OptionGroup WITH Left = 80, Top = 10, Width = 430, Height = 28, ButtonCount = 3, ;
		BorderStyle = 0, Value = 2
	ADD OBJECT lblDialect AS Label WITH Caption = "Dialect", Left = 10, Top = 48, AutoSize = .T.
	ADD OBJECT cboDialect AS ComboBox WITH Left = 80, Top = 44, Width = 200, Height = 24, Style = 2
	ADD OBJECT lblRows AS Label WITH Caption = "Rows", Left = 10, Top = 82, AutoSize = .T.
	ADD OBJECT optRows AS OptionGroup WITH Left = 80, Top = 76, Width = 220, Height = 28, ButtonCount = 2, ;
		BorderStyle = 0, Value = 1
	ADD OBJECT spnRows AS Spinner WITH Left = 300, Top = 78, Width = 80, Height = 24, Value = 100, ;
		SpinnerLowValue = 1, SpinnerHighValue = 100000000, KeyboardLowValue = 1, KeyboardHighValue = 100000000, Increment = 100
	ADD OBJECT optTo AS OptionGroup WITH Left = 80, Top = 110, Width = 430, Height = 28, ButtonCount = 2, ;
		BorderStyle = 0, Value = 1
	ADD OBJECT edtSay AS EditBox WITH Left = 10, Top = 146, Width = 500, Height = 90, ReadOnly = .T., ScrollBars = 2, ;
		Value = ""
	ADD OBJECT cmdScript AS CommandButton WITH Caption = "\<Script", Left = 320, Top = 248, Width = 90, Height = 28, ;
		Default = .T.
	ADD OBJECT cmdClose AS CommandButton WITH Caption = "Close", Left = 420, Top = 248, Width = 90, Height = 28, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, toC, tcTable
		LOCAL loP, loS, lnI, lcCur
		LOCAL ARRAY laD[1]
		DODEFAULT(toModule, toC)
		This.cTable = tcTable
		This.Texts()
		loP = toModule.Plugin()
		loS = IIF(ISNULL(loP), .NULL., loP.Module("script"))
		IF !ISNULL(loS)
			This.cDialects = loS.Dialects()
			lcCur = loS.DialectOf(toC.cEngine)
			FOR lnI = 1 TO ALINES(laD, This.cDialects, 1, ",")
				This.cboDialect.AddItem(loS.DialectName(laD[lnI]))
				IF laD[lnI] == lcCur
					This.cboDialect.ListIndex = lnI
				ENDIF
			ENDFOR
		ENDIF
		This.Kinds()
	ENDPROC

	*-- Las filas, solo para INSERT y UPDATE, y el spinner, solo con «Las
	*-- primeras». Los textos, en el idioma de FoxDock, también al cambiarlo con
	*-- la ventana abierta. Los grupos se recolocan según sus textos nuevos.
	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM
		loM = This.oModule
		This.Caption = loM.T("data.scriptForm.caption", This.cTable, This.cConnName)
		This.lblKind.Caption = loM.T("data.scriptForm.kind")
		This.lblDialect.Caption = loM.T("data.scriptForm.dialect")
		This.lblRows.Caption = loM.T("data.export.rows")
		This.cmdScript.Caption = loM.T("data.scriptForm.doScript")
		This.cmdClose.Caption = loM.T("data.export.close")
		*-- CREATE TABLE, INSERT y UPDATE no se traducen (como en el menú).
		This.optKind.Buttons(1).Caption = "CREATE TABLE"
		This.optKind.Buttons(2).Caption = "INSERT"
		This.optKind.Buttons(3).Caption = "UPDATE"
		This.LayoutOptions(This.optKind, 430)
		This.optRows.Buttons(1).Caption = loM.T("data.export.all")
		This.optRows.Buttons(2).Caption = loM.T("data.export.first")
		This.LayoutOptions(This.optRows, 215)
		This.optTo.Buttons(1).Caption = loM.T("data.scriptForm.toEditor")
		This.optTo.Buttons(2).Caption = loM.T("data.export.toClip")
		This.LayoutOptions(This.optTo, 430)
	ENDPROC

	PROCEDURE Kinds
		This.optRows.Enabled = This.optKind.Value # 1
		This.spnRows.Enabled = This.optKind.Value # 1 AND This.optRows.Value = 2
	ENDPROC

	PROCEDURE optKind.InteractiveChange
		Thisform.Kinds()
	ENDPROC

	PROCEDURE optRows.InteractiveChange
		Thisform.Kinds()
	ENDPROC

	PROCEDURE cmdScript.Click
		LOCAL lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		=Thisform.oModule.ScriptTable(Thisform, Thisform.cTable, ICASE(Thisform.optKind.Value = 1, "create", ;
			Thisform.optKind.Value = 3, "update", "insert"), GETWORDNUM(Thisform.cDialects, MAX(Thisform.cboDialect.ListIndex, 1), ","), ;
			IIF(Thisform.optRows.Value = 2, Thisform.spnRows.Value, 0), IIF(Thisform.optTo.Value = 2, "clip", "file"))
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC
ENDDEFINE


*-- Export... de Explore...: el formato, el fichero y las filas. Lo que dice,
*-- en su cuadro, la barra de estado y el log; ningún diálogo de VFP. Los
*-- botones de cada grupo, ajustados a su texto (LayoutOptions); con JSON,
*-- «Schema only» o «Schema and data» en la fila del separador; y el destino,
*-- un fichero o el portapapeles (JSON y CSV).
DEFINE CLASS DataExportForm AS DataConnectionForm
	Width = 520
	Height = 404
	cTable = ""
	cFileFormat = "dbf"
	nServerTotal = -1 && las filas de la tabla en el servidor (-1: no se supo), para decirlo en otro idioma

	ADD OBJECT lblTotal AS Label WITH Caption = "", Left = 10, Top = 12, Width = 500, Height = 18
	ADD OBJECT lblFormat AS Label WITH Caption = "Format", Left = 10, Top = 42, AutoSize = .T.
	ADD OBJECT optFormat AS OptionGroup WITH Left = 80, Top = 36, Width = 430, Height = 28, ButtonCount = 3, ;
		BorderStyle = 0, Value = 1
	ADD OBJECT lblSep AS Label WITH Caption = "Se\<parator", Left = 10, Top = 76, AutoSize = .T.
	ADD OBJECT cboSep AS ComboBox WITH Left = 80, Top = 72, Width = 130, Height = 24, Style = 2
	ADD OBJECT optEnc AS OptionGroup WITH Left = 220, Top = 70, Width = 290, Height = 28, ButtonCount = 2, ;
		BorderStyle = 0, Value = 1
	*-- Solo con JSON, en el sitio del separador y la codificación (que son del .csv).
	ADD OBJECT optContent AS OptionGroup WITH Left = 80, Top = 70, Width = 430, Height = 28, ButtonCount = 2, ;
		BorderStyle = 0, Value = 2, Visible = .F.
	ADD OBJECT optTo AS OptionGroup WITH Left = 80, Top = 104, Width = 430, Height = 28, ButtonCount = 2, ;
		BorderStyle = 0, Value = 1
	ADD OBJECT lblFolder AS Label WITH Caption = "F\<older", Left = 10, Top = 146, AutoSize = .T.
	ADD OBJECT txtFolder AS TextBox WITH Left = 80, Top = 142, Width = 430, Height = 25, Value = ""
	ADD OBJECT lblFile AS Label WITH Caption = "\<Name", Left = 10, Top = 178, AutoSize = .T.
	ADD OBJECT txtFile AS TextBox WITH Left = 80, Top = 174, Width = 300, Height = 25, Value = ""
	ADD OBJECT chkReplace AS CheckBox WITH Caption = "\<Replace it", Left = 390, Top = 178, AutoSize = .T., Value = .F.
	*-- Abrirlo al acabar (con Windows; el .csv CP1252, en el editor de VFP).
	ADD OBJECT chkOpen AS CheckBox WITH Caption = "Open \<it", Left = 400, Top = 214, AutoSize = .T., Value = .T.
	ADD OBJECT lblRows AS Label WITH Caption = "Rows", Left = 10, Top = 214, AutoSize = .T.
	ADD OBJECT optRows AS OptionGroup WITH Left = 80, Top = 208, Width = 220, Height = 28, ButtonCount = 2, ;
		BorderStyle = 0, Value = 1
	ADD OBJECT spnRows AS Spinner WITH Left = 300, Top = 210, Width = 80, Height = 24, Value = 100, ;
		SpinnerLowValue = 1, SpinnerHighValue = 100000000, KeyboardLowValue = 1, KeyboardHighValue = 100000000, Increment = 100
	ADD OBJECT edtSay AS EditBox WITH Left = 10, Top = 248, Width = 500, Height = 104, ReadOnly = .T., ScrollBars = 2, ;
		Value = ""
	ADD OBJECT cmdHelp AS CommandButton WITH Caption = "\<Help", Left = 10, Top = 364, Width = 90, Height = 28
	ADD OBJECT cmdExport AS CommandButton WITH Caption = "\<Export", Left = 320, Top = 364, Width = 90, Height = 28, ;
		Default = .T.
	ADD OBJECT cmdClose AS CommandButton WITH Caption = "Close", Left = 420, Top = 364, Width = 90, Height = 28, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, toC, tcTable
		LOCAL loP
		DODEFAULT(toModule, toC)
		This.cTable = tcTable
		This.nServerTotal = toModule.ServerCount(toC.cId, tcTable)
		This.Texts()
		loP = toModule.Plugin()
		This.txtFolder.Value = IIF(ISNULL(loP), "", loP.OutDir())
		This.txtFile.Value = tcTable + ".dbf"
		This.Formats()
		This.spnRows.Enabled = This.optRows.Value = 2
	ENDPROC

	*-- Los textos, en el idioma de FoxDock, también al cambiarlo con la ventana
	*-- abierta, con el separador elegido.
	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM, lnSep
		loM = This.oModule
		This.Caption = loM.T("data.export.caption", This.cTable, This.cConnName)
		This.lblFormat.Caption = loM.T("data.export.format")
		This.lblSep.Caption = loM.T("data.export.separator")
		*-- El combo, detrás de su etiqueta (AfterLabel), y acabando donde acababa
		*-- (210, antes de la codificación): así una etiqueta larga, como
		*-- «Trennzeichen», no queda pisada.
		This.AfterLabel(This.lblSep, This.cboSep)
		This.lblFolder.Caption = loM.T("data.export.folder")
		This.lblFile.Caption = loM.T("data.export.name")
		This.chkReplace.Caption = loM.T("data.export.replace")
		This.chkOpen.Caption = loM.T("data.export.open")
		This.lblRows.Caption = loM.T("data.export.rows")
		This.cmdExport.Caption = loM.T("data.export.doExport")
		This.cmdClose.Caption = loM.T("data.export.close")
		This.optFormat.Buttons(1).Caption = loM.T("data.export.dbf")
		This.optFormat.Buttons(2).Caption = loM.T("data.export.json")
		This.optFormat.Buttons(3).Caption = loM.T("data.export.csv")
		This.LayoutOptions(This.optFormat, 430)
		*-- Los textos, en el idioma; lo que se escribe en el CSV va por el índice
		*-- (Export), no por el texto.
		lnSep = This.cboSep.ListIndex
		This.cboSep.Clear()
		This.cboSep.AddItem(loM.T("data.export.sepSemicolon"))
		This.cboSep.AddItem(loM.T("data.export.sepComma"))
		This.cboSep.AddItem(loM.T("data.export.sepTab"))
		This.cboSep.ListIndex = MAX(1, lnSep)
		This.optEnc.Buttons(1).Caption = loM.T("data.export.cp1252")
		This.optEnc.Buttons(2).Caption = loM.T("data.export.utf8bom")
		This.LayoutOptions(This.optEnc, 290)
		This.optContent.Buttons(1).Caption = loM.T("data.export.schemaOnly")
		This.optContent.Buttons(2).Caption = loM.T("data.export.schemaAndData")
		This.LayoutOptions(This.optContent, 430)
		This.optTo.Buttons(1).Caption = loM.T("data.export.toFile")
		This.optTo.Buttons(2).Caption = loM.T("data.export.toClip")
		This.LayoutOptions(This.optTo, 430)
		This.optRows.Buttons(1).Caption = loM.T("data.export.all")
		This.optRows.Buttons(2).Caption = loM.T("data.export.first")
		This.LayoutOptions(This.optRows, 215)
		This.lblTotal.Caption = IIF(This.nServerTotal < 0, loM.T("data.export.totalUnknown", This.cTable), ;
			loM.T("data.export.total", This.cTable, This.nServerTotal))
	ENDPROC

	*-- El separador y la codificación, solo para .csv (y no a la vista con JSON,
	*-- que en su sitio tiene «Schema only / Schema and data»); el portapapeles,
	*-- con JSON y CSV, y con él ni fichero ni codificación; y la extensión del
	*-- nombre.
	PROCEDURE Formats
		LOCAL lcExt, llClip
		lcExt = ICASE(This.optFormat.Value = 2, "json", This.optFormat.Value = 3, "csv", "dbf")
		This.optContent.Visible = lcExt == "json"
		This.lblSep.Visible = !(lcExt == "json")
		This.cboSep.Visible = !(lcExt == "json")
		This.optEnc.Visible = !(lcExt == "json")
		This.optTo.Enabled = !(lcExt == "dbf")
		IF lcExt == "dbf"
			This.optTo.Value = 1
		ENDIF
		llClip = This.optTo.Value = 2
		This.cboSep.Enabled = lcExt == "csv"
		This.optEnc.Enabled = lcExt == "csv" AND !llClip
		This.txtFolder.Enabled = !llClip
		This.txtFile.Enabled = !llClip
		This.chkReplace.Enabled = !llClip
		This.chkOpen.Enabled = !llClip
		IF LOWER(JUSTEXT(ALLTRIM(This.txtFile.Value))) == This.cFileFormat
			This.txtFile.Value = FORCEEXT(ALLTRIM(This.txtFile.Value), lcExt)
		ENDIF
		This.cFileFormat = lcExt
	ENDPROC

	PROCEDURE optFormat.InteractiveChange
		Thisform.Formats()
	ENDPROC

	*-- El spinner, solo con «Las primeras», como en Script as....
	PROCEDURE optRows.InteractiveChange
		Thisform.spnRows.Enabled = Thisform.optRows.Value = 2
	ENDPROC

	PROCEDURE optTo.InteractiveChange
		Thisform.Formats()
	ENDPROC

	PROCEDURE cmdExport.Click
		LOCAL lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		=Thisform.oModule.Export(Thisform, Thisform.cTable, Thisform.cFileFormat, ;
			ADDBS(ALLTRIM(Thisform.txtFolder.Value)) + ALLTRIM(Thisform.txtFile.Value), ;
			IIF(Thisform.optRows.Value = 2, Thisform.spnRows.Value, 0), ;
			ICASE(Thisform.cboSep.ListIndex = 2, ",", Thisform.cboSep.ListIndex = 3, CHR(9), ";"), ;
			IIF(Thisform.optEnc.Value = 2, "utf8bom", "ansi"), Thisform.chkReplace.Value, Thisform.chkOpen.Value, ;
			IIF(Thisform.optTo.Value = 2, "clip", "file"), Thisform.cFileFormat == "json" AND Thisform.optContent.Value = 1)
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC
ENDDEFINE


*-- Create view... de Explore...: el .dbc, el nombre, las columnas, el WHERE y
*-- si es actualizable. Lo que dice, en su cuadro, la barra de estado y el log;
*-- y la línea para abrirla, en el cuadro de abajo.
DEFINE CLASS DataViewForm AS DataConnectionForm
	Width = 560
	Height = 520
	cTable = ""
	lCtrlA = .F.      && el ON KEY LABEL CTRL+A de la lista está puesto
	DIMENSION aCols[1] && las columnas en el orden de la tabla (la lista va en alfabético)
	cMadeView = ""    && la vista que hizo Create en esta ventana (la que abre Open)
	cMadeDbc = ""     && y su .dbc
	lMadePwd = .F.    && si su conexión llevaba contraseña (PWD en la cadena viva): Open la necesita
	cTableKey = ""    && la clave primaria de la tabla, para decirla en otro idioma
	lReplace = .F.    && el nombre es de una vista que ya está en el .dbc: Crear dice Reemplazar

	ADD OBJECT lblDbc AS Label WITH Caption = "\<Database", Left = 10, Top = 14, AutoSize = .T.
	ADD OBJECT cboDbc AS ComboBox WITH Left = 100, Top = 10, Width = 450, Height = 24, Style = 0
	ADD OBJECT lblName AS Label WITH Caption = "View \<name", Left = 10, Top = 46, AutoSize = .T.
	ADD OBJECT txtName AS TextBox WITH Left = 100, Top = 42, Width = 250, Height = 25, Value = ""
	ADD OBJECT lblCols AS Label WITH Caption = "\<Columns", Left = 10, Top = 78, AutoSize = .T.
	ADD OBJECT lstCols AS ListBox WITH Left = 100, Top = 76, Width = 450, Height = 150, MultiSelect = .T.
	*-- Para quien no sabe que CTRL+A las marca todas.
	ADD OBJECT cmdAll AS CommandButton WITH Caption = "All", Left = 10, Top = 100, Width = 80, Height = 24
	ADD OBJECT cmdNone AS CommandButton WITH Caption = "None", Left = 10, Top = 128, Width = 80, Height = 24
	ADD OBJECT lblWhere AS Label WITH Caption = "\<Where", Left = 10, Top = 238, AutoSize = .T.
	ADD OBJECT txtWhere AS TextBox WITH Left = 100, Top = 234, Width = 450, Height = 25, Value = ""
	ADD OBJECT chkUpdatable AS CheckBox WITH Caption = "\<Updatable: TABLEUPDATE() sends the changes to the server", ;
		Left = 100, Top = 268, AutoSize = .T., Value = .F.
	ADD OBJECT lblKey AS Label WITH Caption = "", Left = 100, Top = 290, Width = 450, Height = 18
	ADD OBJECT edtSay AS EditBox WITH Left = 10, Top = 314, Width = 540, Height = 80, ReadOnly = .T., ScrollBars = 2, Value = ""
	ADD OBJECT lblLines AS Label WITH Caption = "To open it from the Command window:", Left = 10, Top = 400, AutoSize = .T.
	ADD OBJECT edtLines AS EditBox WITH Left = 10, Top = 418, Width = 540, Height = 54, ReadOnly = .T., ScrollBars = 2, Value = ""
	*-- Open, apagado hasta que Create hace la vista.
	ADD OBJECT cmdHelp AS CommandButton WITH Caption = "\<Help", Left = 10, Top = 482, Width = 90, Height = 28
	ADD OBJECT cmdOpen AS CommandButton WITH Caption = "\<Open", Left = 260, Top = 482, Width = 90, Height = 28, Enabled = .F.
	ADD OBJECT cmdCreate AS CommandButton WITH Caption = "C\<reate", Left = 360, Top = 482, Width = 90, Height = 28, Default = .T.
	ADD OBJECT cmdClose AS CommandButton WITH Caption = "Close", Left = 460, Top = 482, Width = 90, Height = 28, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, toC, tcTable
		LOCAL lcChoices, lnI, lcCur, lnDs, lcKey, loDb, lnN, laSorted[1]
		DODEFAULT(toModule, toC)
		This.cTable = tcTable
		This.Texts()
		This.aCols[1] = ""
		lcChoices = toModule.DbcChoices(toC.cId)
		FOR lnI = 1 TO GETWORDCOUNT(lcChoices, CHR(13))
			This.cboDbc.AddItem(GETWORDNUM(lcChoices, lnI, CHR(13)))
		ENDFOR
		This.cboDbc.Value = GETWORDNUM(lcChoices, 1, CHR(13))
		This.txtName.Value = "v_" + LOWER(CHRTRAN(tcTable, CHRTRAN(LOWER(tcTable), "abcdefghijklmnopqrstuvwxyz0123456789_", ""), ""))
		*-- Las columnas, todas marcadas; y la clave. La lista, en orden alfabético
		*-- sin distinguir mayúsculas; aCols guarda el de la tabla, que es el de la
		*-- vista (Marked).
		lcCur = "FDV" + SYS(2015)
		IF !EMPTY(toModule.Columns(toC.cId, tcTable, lcCur)) OR This.TableColumns(toModule, toC, tcTable, lcCur)
			lnDs = SET("DATASESSION")
			SET DATASESSION TO 1
			SELECT (lcCur)
			lnN = 0
			SCAN
				lnN = lnN + 1
				DIMENSION This.aCols[lnN]
				This.aCols[lnN] = ALLTRIM(name)
			ENDSCAN
			USE IN (lcCur)
			SET DATASESSION TO (lnDs)
			IF lnN > 0
				DIMENSION laSorted[lnN]
				=ACOPY(This.aCols, laSorted)
				=ASORT(laSorted, 1, -1, 0, 1)
				FOR lnI = 1 TO lnN
					This.lstCols.AddItem(laSorted[lnI])
					This.lstCols.Selected(lnI) = .T.
				ENDFOR
				*-- Arriba, en la primera columna: marcarlas en el bucle deja TopIndex abajo
				*-- del todo. ListIndex 1 no quita ninguna marca.
				This.lstCols.TopIndex = 1
				This.lstCols.ListIndex = 1
			ENDIF
		ENDIF
		loDb = toModule.Live(toC.cId)
		lcKey = IIF(ISNULL(loDb), "", loDb.GetPrimaryKey(tcTable))
		This.chkUpdatable.Enabled = !EMPTY(lcKey)
		*-- Marcada de entrada, y como la dejó el usuario la última vez.
		This.chkUpdatable.Value = toModule.ViewUpdatable()
		This.cTableKey = lcKey
		This.KeyText()
		This.CreateMode(.T.)
	ENDPROC

	*-- Los textos, en el idioma de FoxDock, también al cambiarlo con la ventana
	*-- abierta (las columnas, el nombre y el filtro, como estaban). Los avisos de
	*-- abajo y las líneas no se tocan: ya están dichos.
	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM
		loM = This.oModule
		This.Caption = loM.T("data.view.caption", This.cTable, This.cConnName)
		This.lblDbc.Caption = loM.T("data.view.database")
		This.AfterLabel(This.lblDbc, This.cboDbc)
		This.lblName.Caption = loM.T("data.view.name")
		This.AfterLabel(This.lblName, This.txtName)
		This.lblCols.Caption = loM.T("data.view.columns")
		This.lblWhere.Caption = loM.T("data.view.where")
		This.chkUpdatable.Caption = loM.T("data.view.updatable")
		This.lblLines.Caption = loM.T("data.view.lines")
		This.cmdCreate.Caption = loM.T(IIF(This.lReplace, "data.view.replace", "data.view.create"))
		This.cmdOpen.Caption = loM.T("data.view.open")
		This.cmdClose.Caption = loM.T("data.view.close")
		This.cmdAll.Caption = loM.T("data.view.all")
		This.cmdNone.Caption = loM.T("data.view.none")
		This.KeyText()
	ENDPROC

	PROCEDURE KeyText
		This.lblKey.Caption = IIF(EMPTY(This.cTableKey), This.oModule.T("data.view.noKey", This.cTable), ;
			This.oModule.T("data.view.key", This.cTableKey))
	ENDPROC

	*-- Columns() del módulo busca en las tablas (GetTables); una vista del
	*-- servidor no está ahí: sus columnas, con GetColumns directamente.
	PROCEDURE TableColumns
		LPARAMETERS toModule, toC, tcTable, tcCur
		LOCAL loDb, lnDs, llOk
		loDb = toModule.Live(toC.cId)
		IF ISNULL(loDb)
			RETURN .F.
		ENDIF
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		llOk = toModule.BinaryRead(loDb, "columns", tcTable, tcCur)
		SET DATASESSION TO (lnDs)
		RETURN llOk
	ENDPROC

	*-- Las columnas marcadas, separadas por comas, en el orden de la tabla (la
	*-- lista va en alfabético).
	PROCEDURE Marked
		LOCAL lnI, lnJ, lcOut
		lcOut = ""
		FOR lnI = 1 TO ALEN(This.aCols)
			FOR lnJ = 1 TO This.lstCols.ListCount
				IF This.lstCols.Selected(lnJ) AND This.lstCols.List(lnJ) == This.aCols[lnI]
					lcOut = lcOut + IIF(EMPTY(lcOut), "", ",") + This.aCols[lnI]
				ENDIF
			ENDFOR
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- All y None, y CTRL+A en la lista.
	PROCEDURE MarkAll
		LPARAMETERS tlOn
		LOCAL lnI
		FOR lnI = 1 TO This.lstCols.ListCount
			This.lstCols.Selected(lnI) = tlOn
		ENDFOR
		*-- Marcarlas deja la lista al final: vuelve arriba, y con todas, la primera
		*-- elegida.
		IF This.lstCols.ListCount > 0
			This.lstCols.TopIndex = 1
			IF tlOn
				This.lstCols.ListIndex = 1
			ENDIF
		ENDIF
		This.Changed()
	ENDPROC

	*-- CTRL+A no llega al KeyPress de la lista: se lo queda Edit > Select All del
	*-- IDE. Mientras la lista tiene el foco lo toma un ON KEY LABEL; PUSH KEY
	*-- guarda los que hubiera y POP KEY los repone.
	PROCEDURE CtrlAOn
		IF !This.lCtrlA
			PUSH KEY
			ON KEY LABEL CTRL+A _screen.ActiveForm.MarkAll(.T.)
			This.lCtrlA = .T.
		ENDIF
	ENDPROC

	PROCEDURE CtrlAOff
		IF This.lCtrlA
			POP KEY
			This.lCtrlA = .F.
		ENDIF
	ENDPROC

	PROCEDURE lstCols.GotFocus
		Thisform.CtrlAOn()
	ENDPROC

	PROCEDURE lstCols.LostFocus
		Thisform.CtrlAOff()
	ENDPROC

	PROCEDURE Activate
		IF TYPE("This.ActiveControl.Name") == "C" AND UPPER(This.ActiveControl.Name) == "LSTCOLS"
			This.CtrlAOn()
		ENDIF
	ENDPROC

	PROCEDURE Deactivate
		This.CtrlAOff()
	ENDPROC

	PROCEDURE Destroy
		This.CtrlAOff()
		DODEFAULT()
	ENDPROC

	PROCEDURE cmdAll.Click
		Thisform.MarkAll(.T.)
	ENDPROC

	PROCEDURE cmdNone.Click
		Thisform.MarkAll(.F.)
	ENDPROC

	PROCEDURE cmdOpen.Click
		LOCAL lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		=Thisform.oModule.OpenView(Thisform)
		SET TALK &lcTalk
	ENDPROC

	*-- Apagado tras un Crear bueno; un Click() con él apagado no hace nada.
	PROCEDURE cmdCreate.Click
		LOCAL lcTalk, llMade
		IF !This.Enabled
			RETURN
		ENDIF
		lcTalk = SET("TALK")
		SET TALK OFF
		llMade = Thisform.oModule.CreateView(Thisform, Thisform.cTable, ALLTRIM(TRANSFORM(Thisform.cboDbc.Value)), ;
			ALLTRIM(Thisform.txtName.Value), Thisform.Marked(), ALLTRIM(Thisform.txtWhere.Value), ;
			Thisform.chkUpdatable.Enabled AND Thisform.chkUpdatable.Value, Thisform.lReplace)
		SET TALK &lcTalk
		IF llMade
			This.Enabled = .F.
			Thisform.CreateMode(.F.)
		ENDIF
	ENDPROC

	*-- Crear vuelve en cuanto cambia algo de lo que haría otra vista: el nombre,
	*-- la base, las columnas, el Where o la casilla.
	PROCEDURE Changed
		This.cmdCreate.Enabled = .T.
		This.CreateMode(.T.)
	ENDPROC

	*-- Con el nombre de una vista que ya está en el .dbc, Crear dice Reemplazar
	*-- (así se rehace una vista, por ejemplo una hecha sin Actualizable), y con
	*-- tlSay el panel lo explica antes de pulsar.
	PROCEDURE CreateMode
		LPARAMETERS tlSay
		LOCAL lcView, lcDbc
		lcView = LOWER(ALLTRIM(This.txtName.Value))
		lcDbc = ALLTRIM(TRANSFORM(This.cboDbc.Value))
		This.lReplace = This.oModule.DbcHas(lcDbc, lcView) == "view"
		This.cmdCreate.Caption = This.oModule.T(IIF(This.lReplace, "data.view.replace", "data.view.create"))
		IF tlSay AND This.lReplace
			This.oModule.ExploreSayKey(This, "data.view.willReplace", lcView, JUSTFNAME(lcDbc))
		ENDIF
	ENDPROC

	PROCEDURE txtName.InteractiveChange
		Thisform.Changed()
	ENDPROC

	PROCEDURE cboDbc.InteractiveChange
		Thisform.Changed()
	ENDPROC

	PROCEDURE txtWhere.InteractiveChange
		Thisform.Changed()
	ENDPROC

	PROCEDURE lstCols.InteractiveChange
		Thisform.Changed()
	ENDPROC

	PROCEDURE chkUpdatable.InteractiveChange
		Thisform.oModule.SaveViewUpdatable(This.Value)
		Thisform.Changed()
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC
ENDDEFINE


*-- Query...: un SELECT en un editbox, el límite de filas y Run; el
*-- resultado, en un BROWSE. Se estira con el cuadro de SQL; lo de abajo,
*-- pegado abajo.
DEFINE CLASS DataQueryForm AS DataConnectionForm
	Width = 560
	Height = 360
	BorderStyle = 3
	MaxButton = .T.
	MinWidth = 560
	MinHeight = 326
	cTitleEn = "Query..."
	cResult = ""      && el cursor del último Run que salió bien

	ADD OBJECT edtSql AS EditBox WITH Left = 10, Top = 10, Width = 540, Height = 200, FontName = "Courier New", ;
		FontSize = 10, Value = "SELECT ", Anchor = 15
	ADD OBJECT lblError AS Label WITH Caption = "", Left = 10, Top = 216, Width = 540, Height = 40, WordWrap = .T., ;
		ForeColor = RGB(170, 0, 0), Anchor = 14
	ADD OBJECT lblLimit AS Label WITH Caption = "\<Limit", Left = 10, Top = 268, AutoSize = .T., Anchor = 6
	ADD OBJECT spnLimit AS Spinner WITH Left = 50, Top = 264, Width = 80, Height = 24, Value = 100, ;
		SpinnerLowValue = 0, SpinnerHighValue = 1000000, KeyboardLowValue = 0, KeyboardHighValue = 1000000, Increment = 100, ;
		Anchor = 6
	ADD OBJECT lblNoLimit AS Label WITH Caption = "rows (0 = no limit)", Left = 136, Top = 268, AutoSize = .T., Anchor = 6
	*-- Help va debajo: abajo a la izquierda están el límite y Keep.
	ADD OBJECT cmdHelp AS CommandButton WITH Caption = "\<Help", Left = 10, Top = 328, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT cmdRun AS CommandButton WITH Caption = "\<Run", Left = 360, Top = 262, Width = 90, Height = 28, Anchor = 12
	ADD OBJECT cmdClose AS CommandButton WITH Caption = "Close", Left = 460, Top = 262, Width = 90, Height = 28, Cancel = .T., ;
		Anchor = 12
	*-- El cursor de Run se va al cerrarla, salvo con esto.
	ADD OBJECT chkKeep AS CheckBox WITH Caption = "Keep the cursors open when it closes", Left = 10, Top = 298, ;
		AutoSize = .T., Value = .F., Anchor = 6
	*-- To object: el resultado en pantalla a una Collection PUBLIC, con el nombre de al lado.
	ADD OBJECT lblObject AS Label WITH Caption = "Variable", Left = 250, Top = 300, AutoSize = .T., Anchor = 6
	ADD OBJECT txtObject AS TextBox WITH Left = 300, Top = 296, Width = 150, Height = 24, Value = "", MaxLength = 128, Anchor = 6
	ADD OBJECT cmdObject AS CommandButton WITH Caption = "To \<object", Left = 460, Top = 294, Width = 90, Height = 28, Anchor = 12

	PROCEDURE Init
		LPARAMETERS toModule, toC
		DODEFAULT(toModule, toC)
		This.Texts()
		This.chkKeep.Value = toModule.KeepCursors("query")
		This.spnLimit.Value = toModule.QueryLimit()
	ENDPROC

	*-- Los textos, en el idioma de FoxDock, también al cambiarlo con la ventana
	*-- abierta (el SQL escrito se queda).
	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM, loC
		loM = This.oModule
		loC = loM.Find(This.cConnId)
		This.Caption = loM.T("data.query.caption", loC.cName, loC.cEngine)
		This.chkKeep.Caption = loM.T("data.cursors.keep")
		This.lblLimit.Caption = loM.T("data.query.limit")
		This.lblNoLimit.Caption = loM.T("data.query.noLimit")
		This.cmdRun.Caption = loM.T("data.query.run")
		This.cmdClose.Caption = loM.T("data.query.close")
		This.cmdObject.Caption = loM.T("data.object.button")
		This.lblObject.Caption = loM.T("data.object.name")
		This.AfterLabel(This.lblObject, This.txtObject)
	ENDPROC

	PROCEDURE cmdRun.Click
		LOCAL lcTalk, loM, lnLimit
		lcTalk = SET("TALK")
		SET TALK OFF
		loM = Thisform.oModule
		lnLimit = MAX(INT(Thisform.spnLimit.Value), 0)
		loM.SaveQueryLimit(lnLimit)
		IF loM.RunQuery(Thisform.cConnId, Thisform.edtSql.Value, lnLimit)
			Thisform.Keep(loM.cLastCursor)
			Thisform.cResult = loM.cLastCursor
			Thisform.lblError.Caption = loM.T("data.query.rows", loM.nLastRows, IIF(loM.lLastTruncated, loM.T("data.conn.firstN", lnLimit), ""))
		ELSE
			Thisform.lblError.Caption = loM.cLastError
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	*-- Sin nombre, el propuesto a partir del cursor.
	PROCEDURE cmdObject.Click
		LOCAL lcTalk, loM
		lcTalk = SET("TALK")
		SET TALK OFF
		loM = Thisform.oModule
		IF EMPTY(ALLTRIM(Thisform.txtObject.Value))
			Thisform.txtObject.Value = loM.ObjectVarName(Thisform.cResult)
		ENDIF
		=loM.ToObject(Thisform, Thisform.cResult, ALLTRIM(Thisform.txtObject.Value), Thisform.cResult)
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC
ENDDEFINE


*==================================================================
* Las dos ventanas de las conexiones. No son de una conexión: no parten de
* DataConnectionForm (su Init pide una), sino de DataConnsForm, con lo que
* necesitan del módulo (oModule, cKey, FormGone) y cConnId vacío, para
* FormOf y CloseExplore. Modeless, sin MESSAGEBOX.
*==================================================================
DEFINE CLASS DataConnsForm AS Form
	AutoCenter = .T.
	BorderStyle = 2
	MaxButton = .F.
	MinButton = .F.
	ShowWindow = 0
	WindowType = 0
	oModule = .NULL.
	cKey = ""
	cConnId = ""
	cKind = "connections"

	PROCEDURE Init
		LPARAMETERS toModule, toC
		This.oModule = toModule
	ENDPROC

	PROCEDURE Destroy
		IF VARTYPE(This.oModule) == "O"
			This.oModule.FormGone(This.cKey)
		ENDIF
		This.oModule = .NULL.
	ENDPROC

	*-- Se cierra y el módulo la olvida en el acto: un Release desde un método de
	*-- la propia ventana (Save) la deja en oForms hasta que se suelta, y un
	*-- New... justo detrás la encontraría a medio cerrar («LOF is not an object»).
	PROCEDURE CloseWindow
		IF VARTYPE(This.oModule) == "O"
			This.oModule.FormGone(This.cKey)
		ENDIF
		This.Release()
	ENDPROC

	*-- La sección de las conexiones en la ayuda de los plugins, en el navegador.
	PROCEDURE ShowHelp
		RETURN This.oModule.oHost.OpenHelp("PLUGINS", This.oModule.T("data.help.connections.anchor"))
	ENDPROC
ENDDEFINE


*-- FoxDock - Connections: la lista de las conexiones de los dos ficheros.
DEFINE CLASS DataConnectionsForm AS DataConnsForm
	Width = 560
	Height = 334
	*-- Se estira, como Explore...: la lista crece y los botones siguen abajo.
	BorderStyle = 3
	cPending = ""     && el id que espera «Yes, delete»

	ADD OBJECT lstConns AS ListBox WITH Anchor = 15, Left = 10, Top = 10, Width = 540, Height = 200, ColumnCount = 5, ;
		ColumnWidths = "110,180,80,70,80"
	ADD OBJECT cmdNew AS CommandButton WITH Anchor = 6, Caption = "\<New...", Left = 10, Top = 220, Width = 95, Height = 28
	ADD OBJECT cmdEdit AS CommandButton WITH Anchor = 6, Caption = "\<Edit...", Left = 110, Top = 220, Width = 95, Height = 28
	ADD OBJECT cmdDelete AS CommandButton WITH Anchor = 6, Caption = "\<Delete", Left = 210, Top = 220, Width = 95, Height = 28
	ADD OBJECT cmdOpenFile AS CommandButton WITH Anchor = 12, Caption = "\<Open the file...", Left = 400, Top = 220, Width = 150, Height = 28
	ADD OBJECT lblSay AS Label WITH Anchor = 6, Caption = "", Left = 10, Top = 256, Width = 330, Height = 32, WordWrap = .T.
	ADD OBJECT cmdYesDelete AS CommandButton WITH Anchor = 12, Caption = "\<Yes, delete", Left = 350, Top = 256, Width = 95, Height = 28, ;
		Visible = .F.
	ADD OBJECT cmdNoDelete AS CommandButton WITH Anchor = 12, Caption = "Cancel", Left = 455, Top = 256, Width = 95, Height = 28, Visible = .F.
	ADD OBJECT cmdHelp AS CommandButton WITH Anchor = 6, Caption = "\<Help", Left = 10, Top = 296, Width = 95, Height = 28
	ADD OBJECT cmdClose AS CommandButton WITH Anchor = 12, Caption = "\<Close", Left = 455, Top = 296, Width = 95, Height = 28, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, toC
		DODEFAULT(toModule, toC)
		*-- Un Name fijo, para las tools de FoxAgent con formName.
		This.Name = "FoxDockConnections"
		This.MinWidth = This.Width
		This.MinHeight = This.Height
		This.Texts()
		This.Fill()
	ENDPROC

	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM
		loM = This.oModule
		This.Caption = loM.T("data.conns.caption")
		This.cmdNew.Caption = loM.T("data.conns.new")
		This.cmdEdit.Caption = loM.T("data.conns.edit")
		This.cmdDelete.Caption = loM.T("data.conns.delete")
		This.cmdOpenFile.Caption = loM.T("data.conns.openFile")
		This.cmdYesDelete.Caption = loM.T("data.conns.yesDelete")
		This.cmdNoDelete.Caption = loM.T("data.conns.noDelete")
		This.cmdHelp.Caption = loM.T("data.conns.help")
		This.cmdClose.Caption = loM.T("data.conns.close")
	ENDPROC

	*-- Una fila por conexión, en el orden de oList: id, name, engine, dónde y si
	*-- está conectada. La elegida antes sigue elegida.
	PROCEDURE Fill
		LOCAL loM, loC, lcWas, lnN
		loM = This.oModule
		lcWas = This.SelectedId()
		This.lstConns.Clear()
		FOR EACH loC IN loM.oList FOXOBJECT
			This.lstConns.AddItem(loC.cId)
			lnN = This.lstConns.ListCount
			This.lstConns.List(lnN, 2) = loC.cName
			This.lstConns.List(lnN, 3) = loC.cEngine
			This.lstConns.List(lnN, 4) = loM.T(IIF(loC.cOrigin == "project", "data.conns.whereProject", "data.conns.whereUser"))
			This.lstConns.List(lnN, 5) = IIF(loM.IsConnected(loC.cId), loM.T("data.conns.connected"), "")
			IF loC.cId == lcWas
				This.lstConns.ListIndex = lnN
			ENDIF
		ENDFOR
		This.HideConfirm()
	ENDPROC

	PROCEDURE SelectedId
		LOCAL lnI
		lnI = This.lstConns.ListIndex
		RETURN IIF(lnI > 0 AND lnI <= This.lstConns.ListCount, ALLTRIM(This.lstConns.List(lnI, 1)), "")
	ENDPROC

	PROCEDURE Say
		LPARAMETERS tcKey, tv1, tv2
		This.lblSay.Caption = This.oModule.T(tcKey, tv1, tv2)
		This.oModule.ExploreSayKey(.NULL., tcKey, tv1, tv2)
	ENDPROC

	PROCEDURE HideConfirm
		This.cPending = ""
		This.cmdYesDelete.Visible = .F.
		This.cmdNoDelete.Visible = .F.
	ENDPROC

	PROCEDURE cmdNew.Click
		=ThisForm.oModule.OpenEdit("")
	ENDPROC

	PROCEDURE cmdEdit.Click
		ThisForm.EditChosen()
	ENDPROC

	PROCEDURE lstConns.DblClick
		ThisForm.EditChosen()
	ENDPROC

	PROCEDURE EditChosen
		LOCAL lcId
		lcId = This.SelectedId()
		IF EMPTY(lcId)
			This.Say("data.conns.chooseOne")
			RETURN .F.
		ENDIF
		=This.oModule.OpenEdit(lcId)
		RETURN .T.
	ENDPROC

	*-- Delete pregunta aquí, en la ventana: el nombre y «Yes, delete» al lado de Cancel.
	PROCEDURE cmdDelete.Click
		LOCAL lcId, loC
		lcId = ThisForm.SelectedId()
		IF EMPTY(lcId)
			ThisForm.Say("data.conns.chooseOne")
			RETURN
		ENDIF
		loC = ThisForm.oModule.Find(lcId)
		ThisForm.cPending = lcId
		ThisForm.lblSay.Caption = ThisForm.oModule.T("data.conns.confirmDelete", loC.cName, JUSTFNAME(JUSTPATH(loC.cFile)) + "\" + JUSTFNAME(loC.cFile))
		ThisForm.cmdYesDelete.Visible = .T.
		ThisForm.cmdNoDelete.Visible = .T.
	ENDPROC

	PROCEDURE cmdYesDelete.Click
		LOCAL lcId, lcWhy, loM
		loM = ThisForm.oModule
		lcId = ThisForm.cPending
		ThisForm.HideConfirm()
		lcWhy = loM.DeleteConnection(lcId)
		IF EMPTY(lcWhy)
			ThisForm.lblSay.Caption = ""
		ELSE
			ThisForm.Say(lcWhy, loM.cWhy1, loM.cWhy2)
		ENDIF
	ENDPROC

	PROCEDURE cmdNoDelete.Click
		ThisForm.HideConfirm()
		ThisForm.lblSay.Caption = ""
	ENDPROC

	PROCEDURE cmdOpenFile.Click
		ThisForm.oModule.OpenFileBar()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC

	PROCEDURE cmdClose.Click
		ThisForm.CloseWindow()
	ENDPROC
ENDDEFINE


*-- FoxDock - Connection: New... y Edit... de una conexión. Ningún campo de
*-- contraseña: la pide Connect...
DEFINE CLASS DataConnectionEditForm AS DataConnsForm
	Width = 450
	Height = 440
	cMode = "new"
	cEditId = ""
	cEditFile = ""
	cSnapshot = ""
	cPrevEngine = ""

	ADD OBJECT lblWhere AS Label WITH Caption = "Where", Left = 10, Top = 14, AutoSize = .T.
	ADD OBJECT optWhere AS OptionGroup WITH Left = 125, Top = 4, Width = 315, Height = 30, ButtonCount = 2, BorderStyle = 0, Value = 2
	ADD OBJECT lblFile AS Label WITH Caption = "", Left = 130, Top = 14, Width = 310, Height = 17, Visible = .F.
	ADD OBJECT lblId AS Label WITH Caption = "\<Id", Left = 10, Top = 44, AutoSize = .T.
	ADD OBJECT txtId AS TextBox WITH Left = 130, Top = 40, Width = 200, Height = 25, MaxLength = 64, Value = ""
	ADD OBJECT lblIdShown AS Label WITH Caption = "", Left = 130, Top = 44, Width = 310, Height = 17, Visible = .F.
	ADD OBJECT lblName AS Label WITH Caption = "\<Name", Left = 10, Top = 74, AutoSize = .T.
	ADD OBJECT txtName AS TextBox WITH Left = 130, Top = 70, Width = 310, Height = 25, MaxLength = 200, Value = ""
	ADD OBJECT lblEngine AS Label WITH Caption = "\<Engine", Left = 10, Top = 104, AutoSize = .T.
	ADD OBJECT cboEngine AS ComboBox WITH Left = 130, Top = 100, Width = 150, Height = 25, Style = 2
	ADD OBJECT lblServer AS Label WITH Caption = "Se\<rver", Left = 10, Top = 134, AutoSize = .T.
	ADD OBJECT txtServer AS TextBox WITH Left = 130, Top = 130, Width = 310, Height = 25, MaxLength = 200, Value = ""
	ADD OBJECT lblPort AS Label WITH Caption = "\<Port", Left = 10, Top = 164, AutoSize = .T.
	ADD OBJECT txtPort AS TextBox WITH Left = 130, Top = 160, Width = 80, Height = 25, Value = 0, InputMask = "99999"
	ADD OBJECT lblDatabase AS Label WITH Caption = "\<Database", Left = 10, Top = 194, AutoSize = .T.
	ADD OBJECT txtDatabase AS TextBox WITH Left = 130, Top = 190, Width = 276, Height = 25, MaxLength = 254, Value = ""
	ADD OBJECT cmdPick AS CommandButton WITH Caption = "...", Left = 412, Top = 190, Width = 28, Height = 25
	ADD OBJECT lblUser AS Label WITH Caption = "\<User", Left = 10, Top = 224, AutoSize = .T.
	ADD OBJECT txtUser AS TextBox WITH Left = 130, Top = 220, Width = 200, Height = 25, MaxLength = 128, Value = ""
	ADD OBJECT lblDriver AS Label WITH Caption = "Dri\<ver", Left = 10, Top = 254, AutoSize = .T.
	ADD OBJECT txtDriver AS TextBox WITH Left = 130, Top = 250, Width = 310, Height = 25, MaxLength = 128, Value = ""
	ADD OBJECT chkWindowsAuth AS CheckBox WITH Caption = "\<Windows authentication", Left = 130, Top = 282, AutoSize = .T., Value = .F.
	ADD OBJECT chkAllowWrite AS CheckBox WITH Caption = "\<Allow writing", Left = 130, Top = 304, AutoSize = .T., Value = .F.
	ADD OBJECT chkAgentCanRead AS CheckBox WITH Caption = "The agen\<t can read it", Left = 130, Top = 326, AutoSize = .T., Value = .F.
	ADD OBJECT lblError AS Label WITH Caption = "", Left = 10, Top = 352, Width = 430, Height = 36, WordWrap = .T., ;
		ForeColor = RGB(170, 0, 0)
	ADD OBJECT cmdHelp AS CommandButton WITH Caption = "\<Help", Left = 10, Top = 400, Width = 95, Height = 28
	ADD OBJECT cmdSave AS CommandButton WITH Caption = "\<Save", Left = 240, Top = 400, Width = 95, Height = 28
	ADD OBJECT cmdCancel AS CommandButton WITH Caption = "Cancel", Left = 345, Top = 400, Width = 95, Height = 28, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, toC
		LOCAL lnI
		DODEFAULT(toModule, toC)
		This.Name = "FoxDockConnection"
		FOR lnI = 1 TO GETWORDCOUNT(DC_ENGINES, ",")
			This.cboEngine.AddItem(GETWORDNUM(DC_ENGINES, lnI, ","))
		ENDFOR
		This.Texts()
		This.LoadConn(toC)
	ENDPROC

	PROCEDURE Texts
		IF PEMSTATUS(This, "cmdHelp", 5)
			This.cmdHelp.Caption = This.oModule.T("data.conns.help")
		ENDIF
		LOCAL loM, loB1, loB2
		loM = This.oModule
		This.Caption = loM.T("data.connEdit.caption")
		This.lblWhere.Caption = loM.T("data.connEdit.where")
		This.optWhere.Buttons(1).Caption = loM.T("data.connEdit.inProject")
		This.optWhere.Buttons(2).Caption = loM.T("data.connEdit.inUser")
		This.lblId.Caption = loM.T("data.connEdit.id")
		This.lblName.Caption = loM.T("data.connEdit.name")
		This.lblEngine.Caption = loM.T("data.connEdit.engine")
		This.lblServer.Caption = loM.T("data.connEdit.server")
		This.lblPort.Caption = loM.T("data.connEdit.port")
		This.lblDatabase.Caption = loM.T("data.connEdit.database")
		This.lblUser.Caption = loM.T("data.connEdit.user")
		This.lblDriver.Caption = loM.T("data.connEdit.driver")
		This.chkWindowsAuth.Caption = loM.T("data.connEdit.windowsAuth")
		This.chkAllowWrite.Caption = loM.T("data.connEdit.allowWrite")
		This.chkAgentCanRead.Caption = loM.T("data.connEdit.agentCanRead")
		This.cmdHelp.Caption = loM.T("data.conns.help")
		This.cmdSave.Caption = loM.T("data.connEdit.save")
		This.cmdCancel.Caption = loM.T("data.connEdit.cancel")
		*-- Los dos botones del grupo, uno detrás de otro (con AutoSize, VFP los
		*-- apilaría).
		loB1 = This.optWhere.Buttons(1)
		loB2 = This.optWhere.Buttons(2)
		loB1.AutoSize = .T.
		loB2.AutoSize = .T.
		loB1.Left = 5
		loB1.Top = 5
		loB2.Left = loB1.Left + loB1.Width + 16
		loB2.Top = 5
	ENDPROC

	*-- New (toC .NULL.) o Edit de toC.
	PROCEDURE LoadConn
		LPARAMETERS toC
		LOCAL loM, llNew, llProject
		loM = This.oModule
		llNew = ISNULL(toC)
		This.cMode = IIF(llNew, "new", "edit")
		This.optWhere.Visible = llNew
		This.txtId.Visible = llNew
		This.lblFile.Visible = !llNew
		This.lblIdShown.Visible = !llNew
		IF llNew
			llProject = !EMPTY(loM.ProjectFile())
			This.optWhere.Buttons(1).Enabled = llProject
			This.optWhere.Value = IIF(llProject, 1, 2)
			This.cEditId = ""
			This.cEditFile = ""
			This.txtId.Value = ""
			This.txtName.Value = ""
			This.cboEngine.Value = "sqlserver"
			This.txtServer.Value = ""
			This.txtPort.Value = 0
			This.txtDatabase.Value = ""
			This.txtUser.Value = ""
			This.txtDriver.Value = loM.DefaultDriver("sqlserver")
			This.chkWindowsAuth.Value = .F.
			This.chkAllowWrite.Value = .F.
			This.chkAgentCanRead.Value = .F.
		ELSE
			This.cEditId = toC.cId
			This.cEditFile = toC.cFile
			This.lblFile.Caption = toC.cFile
			This.lblIdShown.Caption = toC.cId
			This.txtName.Value = toC.cName
			This.cboEngine.Value = toC.cEngine
			This.txtServer.Value = toC.cServer
			This.txtPort.Value = toC.nPort
			This.txtDatabase.Value = toC.cDatabase
			This.txtUser.Value = toC.cUser
			This.txtDriver.Value = toC.cDriver
			This.chkWindowsAuth.Value = toC.lWindowsAuth
			This.chkAllowWrite.Value = toC.lAllowWrite
			This.chkAgentCanRead.Value = toC.lAgentCanRead
		ENDIF
		This.cPrevEngine = ALLTRIM(This.cboEngine.Value)
		This.lblError.Caption = ""
		This.AuthChanged()
		This.cmdPick.Enabled = INLIST(This.cPrevEngine, "sqlite", "firebird")
		This.cSnapshot = This.FieldsText()
	ENDPROC

	PROCEDURE FieldsText
		RETURN ALLTRIM(This.txtId.Value) + "|" + ALLTRIM(This.txtName.Value) + "|" + ALLTRIM(This.cboEngine.Value) + "|" + ;
			ALLTRIM(This.txtServer.Value) + "|" + TRANSFORM(This.txtPort.Value) + "|" + ALLTRIM(This.txtDatabase.Value) + "|" + ;
			ALLTRIM(This.txtUser.Value) + "|" + ALLTRIM(This.txtDriver.Value) + "|" + TRANSFORM(This.chkWindowsAuth.Value) + ;
			TRANSFORM(This.chkAllowWrite.Value) + TRANSFORM(This.chkAgentCanRead.Value)
	ENDPROC

	PROCEDURE IsDirty
		RETURN !(This.FieldsText() == This.cSnapshot)
	ENDPROC

	*-- Al cambiar el motor: el driver, el del motor si estaba vacío o era el del
	*-- motor de antes; y «...» solo para los de fichero (sqlite, firebird).
	PROCEDURE EngineChanged
		LOCAL lcNew, loM
		loM = This.oModule
		lcNew = ALLTRIM(This.cboEngine.Value)
		IF EMPTY(ALLTRIM(This.txtDriver.Value)) OR ALLTRIM(This.txtDriver.Value) == loM.DefaultDriver(This.cPrevEngine)
			This.txtDriver.Value = loM.DefaultDriver(lcNew)
		ENDIF
		This.cPrevEngine = lcNew
		This.cmdPick.Enabled = INLIST(lcNew, "sqlite", "firebird")
	ENDPROC

	PROCEDURE AuthChanged
		This.txtUser.Enabled = !This.chkWindowsAuth.Value
	ENDPROC

	PROCEDURE cboEngine.InteractiveChange
		ThisForm.EngineChanged()
	ENDPROC

	PROCEDURE chkWindowsAuth.InteractiveChange
		ThisForm.AuthChanged()
	ENDPROC

	*-- Solo para un clic del usuario (ninguna tool lo pulsa: GETFILE abre un
	*-- diálogo): el fichero de la base.
	PROCEDURE cmdPick.Click
		LOCAL lcFile
		lcFile = GETFILE("", "", "", 0, ThisForm.lblDatabase.Caption)
		IF !EMPTY(lcFile)
			ThisForm.txtDatabase.Value = lcFile
		ENDIF
	ENDPROC

	*-- La conexión de los campos, con las propiedades de las de Make.
	PROCEDURE Conn
		LOCAL loO
		loO = CREATEOBJECT("Empty")
		ADDPROPERTY(loO, "cId", IIF(This.cMode == "new", LOWER(ALLTRIM(This.txtId.Value)), This.cEditId))
		ADDPROPERTY(loO, "cName", ALLTRIM(This.txtName.Value))
		ADDPROPERTY(loO, "cEngine", LOWER(ALLTRIM(This.cboEngine.Value)))
		ADDPROPERTY(loO, "cServer", ALLTRIM(This.txtServer.Value))
		ADDPROPERTY(loO, "nPort", INT(VAL(TRANSFORM(This.txtPort.Value))))
		ADDPROPERTY(loO, "cDatabase", ALLTRIM(This.txtDatabase.Value))
		ADDPROPERTY(loO, "cUser", ALLTRIM(This.txtUser.Value))
		ADDPROPERTY(loO, "cDriver", ALLTRIM(This.txtDriver.Value))
		ADDPROPERTY(loO, "lWindowsAuth", This.chkWindowsAuth.Value)
		ADDPROPERTY(loO, "lAllowWrite", This.chkAllowWrite.Value)
		ADDPROPERTY(loO, "lAgentCanRead", This.chkAgentCanRead.Value)
		RETURN loO
	ENDPROC

	PROCEDURE TargetFile
		IF This.cMode == "edit"
			RETURN This.cEditFile
		ENDIF
		RETURN IIF(This.optWhere.Value = 1, This.oModule.ProjectFile(), This.oModule.UserFile())
	ENDPROC

	PROCEDURE Say
		LPARAMETERS tcKey, tv1, tv2
		This.lblError.Caption = This.oModule.T(tcKey, tv1, tv2)
		This.oModule.ExploreSayKey(.NULL., tcKey, tv1, tv2)
	ENDPROC

	PROCEDURE Save
		LOCAL lcWhy, loM, lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		loM = This.oModule
		lcWhy = loM.StoreConnection(This.Conn(), This.TargetFile(), This.cMode == "new")
		SET TALK &lcTalk
		IF EMPTY(lcWhy)
			This.CloseWindow()
			RETURN .T.
		ENDIF
		This.Say(lcWhy, loM.cWhy1, loM.cWhy2)
		RETURN .F.
	ENDPROC

	PROCEDURE cmdSave.Click
		=ThisForm.Save()
	ENDPROC

	PROCEDURE cmdCancel.Click
		ThisForm.CloseWindow()
	ENDPROC

	PROCEDURE cmdHelp.Click
		=ThisForm.ShowHelp()
	ENDPROC
ENDDEFINE
