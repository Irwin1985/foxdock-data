*==================================================================
* DataAi.prg: el módulo «ai» del paquete «data» de FoxDock, AIXL dentro del
* IDE. La detección, la barra apagada, el proveedor y la tool
* ide_data_ai_status; y cinco operaciones con una misma ventana
* (DataAiClassifyForm, que cambia según cKind) y un mismo RunOp: Classify
* column..., Extract (SCHEMA: una columna por clave), Anonymize, Filter (marca
* aixl_keep, no borra; con la casilla, un cursor ai_<nombre>_kept) y Ask (una
* pregunta sobre el conjunto: sin bloques, el modelo lee los primeros 4.000
* caracteres), con sus tools ide_data_ai_classify, _extract, _anonymize,
* _filter y _ask.
*
* LOS PROVEEDORES: quien tiene cuenta en varios pasa de uno a otro (cuando se
* le acaba el crédito de uno, por ejemplo) sin configurar nada:
*   - una lista con nombre, proveedor, modelo, servidor local y de dónde sale la
*     clave, en <carpeta de datos>\ai-providers.json (un array JSON de objetos
*     planos, como connections.json; sin claves). La ventana es Manage
*     providers... (DataAiProvidersForm, abajo);
*   - la clave, de dos maneras: guardada cifrada con la cuenta de Windows (DPAPI,
*     DataDpapi de DataConnections, en secrets\ai-<id>.cred) o leída de una
*     variable de entorno (del proceso, del usuario o del equipo, en cada uso),
*     con el nombre que le dio el usuario (no se propone ninguno: cada uno
*     llama a su variable como quiere). Nunca en claro
*     en un fichero;
*   - uno en uso (options.data.ai.provider), y el submenú «Provider: <nombre>» los
*     lista con la marca en el que está en uso: un clic y se cambia. Nunca se cambia
*     solo: si el proveedor se queda sin crédito, la operación falla con lo que dijo,
*     y es el usuario quien elige otro.
*   - en uso: AIXL_CONFIGURE_FROM_FILE de <carpeta de datos>\ai\session.json, que
*     lleva proveedor, modelo y servidor local y NUNCA la clave, y después
*     AIXL_CONFIGURE con la clave, en memoria (Configure conserva el endpoint que
*     dejó el fichero: AixlHost.prg); y AIXL_ACTIVATE con la licencia de
*     options.data.ai.license;
*   - sin ningún proveedor (ni el doble de options.data.ai.mock, ni un
*     aixl.config.json con proveedor), las cinco operaciones están apagadas y sus
*     tools contestan NO_PROVIDER. Mock mode no tiene barra (unas respuestas
*     inventadas confunden): queda en la opción, para las pruebas.
* La clave no pasa por el log, la barra de estado, el agente ni ninguna propiedad
* del módulo: de una guardada, la ventana solo dice cuánto mide.
*
* UNA OPERACIÓN:
*   - la tabla de trabajo es la de DataTable (el alias seleccionado en la sesión
*     1, o un .dbf). Si ISREADONLY() la da por solo lectura, o es un .dbf, se
*     trabaja sobre una copia ai_<nombre> READWRITE de sus filas visibles en la
*     sesión 1: nunca se escribe en una tabla del usuario, y el original queda
*     como estaba;
*   - la frase del coste se escribe justo antes de Run con el ProviderName del
*     objeto vivo: un proveedor «mock...» es el doble.
*   - el lote va por AIXL_RUN_BATCH con el script que haría AIXL_CLASSIFY (que no
*     admite callback), SET ESCAPE OFF durante el lote (con ON, un Esc es el
*     modal «INTERRUPTED» de VFP) y repuesto, el módulo ocupado (lBusy:
*     ide_data_ai_classify e ide_data_from_json sobre ese alias contestan
*     AI_BUSY), el avance en _VFP.StatusBar y en la ventana, y Esc (INKEY 27 en
*     el callback) para al acabar el bloque en curso: lo hecho se queda, .NULL.
*     en el resto (RUN_CANCELLED);
*   - al acabar, BROWSE del resultado (con el _screen a la vista), AIXL_STATS y
*     los avisos a la barra de estado y al log, ai_errors si AIXL_ERRORS trae
*     filas, y Last run.
*
* AIXL ES APARTE Y DE PAGO: FoxDock no copia ni lleva nada de AIXL (ni
* aixl.prg, ni sus DLL, ni la licencia). Usa el AIXL instalado en la máquina,
* si lo hay, y si no lo dice (la barra apagada).
*
* LA DETECCIÓN (Locate, al cargar el módulo, en 0 a 1 ms): nunca
* crea el objeto COM al arrancar el IDE (289 a 347 ms, carga .NET).
*   1. HKCR\AIXL.Host\CLSID -> HKCR\CLSID\{...}\InProcServer32 (la vista de 32
*      bits, la de VFP) -> la carpeta de esa DLL -> aixl.prg ahí. Es lo que
*      deja register.cmd del zip de AIXL.
*   2. Si ahí no está: options.data.ai.aixlDir (la carpeta de aixl.prg).
*   3. Si tampoco: la barra apagada lo dice.
* Los estados (cState) y la barra apagada de cada uno:
*   ready          AIXL está; las barras del submenú
*   not_installed  no hay AIXL.Host en el registro (caso 1)
*   no_library     está registrado pero no se encuentra su aixl.prg (caso 2),
*                  por ejemplo, la DLL de una build de desarrollo sin
*                  aixl.prg al lado
*   elevated       el IDE corre como administrador y no ve un AIXL registrado
*                  por usuario: "HOST_ELEVATED" de aixl.prg (caso 3). Solo se
*                  sabe al crear el objeto, en Ensure()
*   failed         el resto, con el código de aixl.prg ("DOTNET_RUNTIME_MISSING",
*                  "HOST_IS_64BIT", "COM_FAILED"...) o una versión menor que
*                  1.1.3 (caso 4)
* Cuando Ensure() cambia el estado, el menú se rehace (oHost.RefreshMenu, como
* Connections con el estado de una conexión).
*
* EL PRIMER USO (Ensure): aixl.prg se copia a la caché de código de este motor
* (<carpeta de datos>\fxp\<motor>\aixl\, la de los plugins) y se carga de
* allí con SET PROCEDURE (y se mantiene visible: DataPlugin.EnsureProcedures).
* Nunca se compila en la carpeta de AIXL, que es del usuario y puede ser de solo
* lectura o tener en uso el aixl.FXP de otro motor (VFP 9
* con VFPA abierto). aixl.prg no lee nada de su carpeta: crea el objeto por su
* ProgId (el registro), y su ruta solo la enseña AIXL_HEALTH. Si no se carga o no
* corre, el estado es failed con el código AIXL_LOAD_FAILED, y nada llama a sus
* funciones. Después AIXL_VERSION() (crea el objeto), 1.1.3
* o más (tres números), y la sesión (ApplySession): el doble con
* options.data.ai.mock, el proveedor en uso de la lista, o el aixl.config.json
* que haya. Lo que diga AIXL va
* con su código entre comillas y su texto: FoxDock no inventa diagnósticos.
*
* UNA SOLA SESIÓN DE AIXL POR IDE, LA DEL USUARIO: aixl.prg
* guarda el objeto y el último error en _SCREEN, y lo que el usuario haga desde
* la ventana de comandos (AIXL_USE_MOCK, AIXL_CONFIGURE..., AIXL_RELEASE) es la
* misma sesión que la del módulo. El módulo no guarda ni repone nada: lo que
* enseña (Provider) lo lee del objeto vivo
* (ProviderName) cuando lo hay, y no de lo que pidió.
*
* Las opciones (config.json, "options": { "data": { "ai": { ... } } }):
*   enabled  .F. apaga el módulo: ni sus barras ni sus tools (por defecto .T.)
*   aixlDir  la carpeta de aixl.prg, si el registro no lleva a ella
*   config   la ruta de un aixl.config.json (relativa: a la carpeta de datos de
*            FoxDock); vacía, el aixl.config.json de la carpeta de aixl.prg. Solo
*            cuenta sin un proveedor en uso de la lista
*   provider el id del proveedor en uso (lo escriben Manage providers... y el
*            submenú Provider)
*   license  la ruta del fichero de la licencia de AIXL (Manage providers...)
*   mock     .T.: el doble de AIXL (por defecto .F.); FOXDOCK_AI_MOCK=on lo
*            fuerza. Para las pruebas: no tiene barra
*   blockRows     las filas por bloque de una operación (200; de 1 a 1000)
*   agentMaxRows  las filas que el agente puede mandar en una llamada (200)
* Los ganchos de pruebas (nunca en un IDE de trabajo):
*   _screen.cFoxDockAiLocate   "none" (sin AIXL.Host) o "dll=<ruta>" (el
*                              InProcServer32 que daría el registro)
*   _screen.cFoxDockAiVersion  la versión que daría el objeto
*   _screen.cAixlProgIdOverride, el de aixl.prg: un ProgId que no existe
*==================================================================

#DEFINE CRLF CHR(13) + CHR(10)
#DEFINE AI_CLSID_KEY "AIXL.Host\CLSID"
#DEFINE AI_MIN_VERSION "1.1.3"
*-- La ficha de AIXL en el portal; mientras no la haya, la raíz del sitio.
#DEFINE AI_PRODUCT_URL "https://irwinrodriguez.dev/"
#DEFINE AI_HKCR -2147483648
#DEFINE AI_KEY_READ 131097
#DEFINE AI_BLOCK_ROWS 200
#DEFINE AI_AGENT_MAX_ROWS 200
#DEFINE AI_MAX_ROWS 1000

DEFINE CLASS DataAi AS Custom
	cId = "ai"
	oHost = .NULL.
	cState = ""        && ready, not_installed, no_library, elevated, failed
	cDetail = ""       && el porqué, en inglés (el log y la tool)
	cCode = ""         && el código de aixl.prg en elevated y failed
	cDllPath = ""      && el InProcServer32 de AIXL.Host
	cAixlDir = ""      && la carpeta de aixl.prg
	cFoundBy = ""      && registry o aixlDir
	cVersion = ""      && la del objeto, desde Ensure()
	lEnsured = .F.
	lMockWanted = .F.  && el doble que pidió el usuario (options.data.ai.mock o FOXDOCK_AI_MOCK; sin barra)
	cConfigFile = ""   && el aixl.config.json que se usa (la ruta, nunca su contenido)
	cProvider = ""     && del aixl.config.json, leído por el módulo (nunca la clave)
	cModel = ""
	cConfigNote = ""   && "no provider configured", o el código y el texto de AIXL
	oLastRun = .NULL.  && nRows, nTokens, nSeconds de la última operación
	lBusy = .F.        && un lote corriendo (AI_BUSY)
	cBusyAlias = ""    && el alias del lote
	nDone = 0          && el avance del lote, del callback (FdAiProgress)
	nTotal = 0
	nBlock = 0
	nBlocks = 0
	lAgentRun = .F.    && el lote es de la tool: sin Esc
	lCancelled = .F.
	oForm = .NULL.     && la ventana que lanzó el lote (el avance)
	oForms = .NULL.    && las ventanas abiertas (Retext, al apagar)
	cLastBrowse = ""   && lo que se enseñó (o se habría enseñado con el _screen oculto) al acabar
	cLastNotice = ""   && la última línea de la operación (la que va a la barra de estado)
	cEscapeInRun = ""  && SET("ESCAPE") que vio el callback (las pruebas: OFF durante el lote)
	nLastKey = 0       && la tecla que vio el callback (para las pruebas)
	lStopAsked = .F.   && Esc en la ventana durante el lote (KeyPress, con KeyPreview)
	cBusyKind = ""     && la operación del lote (BusyText)
	oProviders = .NULL. && la lista de proveedores (ai-providers.json), por id
	cFileProvider = "" && el del aixl.config.json, que solo cuenta sin un proveedor en uso
	cFileModel = ""
	cKeyWhy = ""       && por qué no hay clave (en inglés; nunca la clave)
	cLoadError = ""    && por qué aixl.prg no se cargó o no corrió (el error de VFP)

	PROCEDURE Init
		LPARAMETERS toHost
		This.oHost = toHost
		This.oForms = CREATEOBJECT("Collection")
		This.lMockWanted = This.oHost.Options.Get("data", "ai.mock", .F.) OR LOWER(GETENV("FOXDOCK_AI_MOCK")) == "on"
		This.oProviders = CREATEOBJECT("Collection")
		This.Locate()
		This.LoadProviders()
		This.SyncCurrent()
	ENDPROC

	*-- El paquete, por el host (ninguna referencia circular).
	PROCEDURE Plugin
		RETURN This.oHost.PluginById("data")
	ENDPROC

	*--------------------------------------------------------------
	* La detección. Sin crear nada.
	*--------------------------------------------------------------
	PROCEDURE Locate
		LOCAL lcClsid, lcDll, lcDir, lcOpt, lcHook
		This.cState = ""
		This.cDetail = ""
		This.cCode = ""
		This.cDllPath = ""
		This.cAixlDir = ""
		This.cFoundBy = ""
		This.cVersion = ""
		This.lEnsured = .F.
		lcHook = IIF(PEMSTATUS(_screen, "cFoxDockAiLocate", 5), TRANSFORM(_screen.cFoxDockAiLocate), "")
		DO CASE
			CASE lcHook == "none"
				lcDll = ""
			CASE LEFT(lcHook, 4) == "dll="
				lcDll = SUBSTR(lcHook, 5)
			OTHERWISE
				lcClsid = This.RegDefault(AI_CLSID_KEY)
				lcDll = IIF(LEFT(lcClsid, 1) == "{", This.RegDefault("CLSID\" + lcClsid + "\InProcServer32"), "")
		ENDCASE
		IF EMPTY(lcDll)
			This.SetState("not_installed", "AIXL.Host is not registered on this machine")
			This.ReadConfig()
			RETURN This.cState
		ENDIF
		This.cDllPath = lcDll
		lcDir = ADDBS(JUSTPATH(lcDll))
		IF FILE(lcDir + "aixl.prg")
			This.cAixlDir = lcDir
			This.cFoundBy = "registry"
		ELSE
			lcOpt = TRANSFORM(This.oHost.Options.Get("data", "ai.aixlDir", ""))
			IF !EMPTY(lcOpt) AND FILE(ADDBS(lcOpt) + "aixl.prg")
				This.cAixlDir = ADDBS(lcOpt)
				This.cFoundBy = "aixlDir"
			ENDIF
		ENDIF
		IF EMPTY(This.cAixlDir)
			This.SetState("no_library", "AIXL.Host is registered (" + lcDll + ") but aixl.prg is not next to it" + ;
				IIF(EMPTY(This.oHost.Options.Get("data", "ai.aixlDir", "")), "", ", nor in options.data.ai.aixlDir"))
		ELSE
			This.SetState("ready", "aixl.prg in " + This.cAixlDir + " (" + This.cFoundBy + ")")
		ENDIF
		This.ReadConfig()
		RETURN This.cState
	ENDPROC

	PROTECTED PROCEDURE SetState
		LPARAMETERS tcState, tcDetail, tcCode
		This.cState = tcState
		This.cDetail = tcDetail
		This.cCode = EVL(tcCode, "")
		This.oHost.Log("data.ai: " + tcState + "; " + tcDetail)
	ENDPROC

	*-- El valor por defecto de una clave de HKCR (vista de 32 bits: la de VFP), o "".
	PROTECTED PROCEDURE RegDefault
		LPARAMETERS tcKey
		LOCAL lnKey, lnType, lcData, lnLen, lnRc
		DECLARE INTEGER RegOpenKeyEx IN advapi32 AS FdAiRegOpen INTEGER hKey, STRING cSubKey, INTEGER nOptions, INTEGER nSam, INTEGER @nResult
		DECLARE INTEGER RegQueryValueEx IN advapi32 AS FdAiRegQuery INTEGER hKey, STRING cName, INTEGER nReserved, INTEGER @nType, STRING @cData, INTEGER @nLen
		DECLARE INTEGER RegCloseKey IN advapi32 AS FdAiRegClose INTEGER hKey
		lnKey = 0
		IF FdAiRegOpen(AI_HKCR, tcKey, 0, AI_KEY_READ, @lnKey) != 0
			RETURN ""
		ENDIF
		lnType = 0
		lcData = SPACE(1024)
		lnLen = 1024
		lnRc = FdAiRegQuery(lnKey, "", 0, @lnType, @lcData, @lnLen)
		=FdAiRegClose(lnKey)
		RETURN IIF(lnRc = 0, LEFT(lcData, MAX(lnLen - 1, 0)), "")
	ENDPROC

	*-- El aixl.config.json: la ruta y, leídos por el módulo, proveedor y modelo.
	*-- Nunca la clave ni la licencia: no se guardan ni se dicen.
	PROCEDURE ReadConfig
		LOCAL lcOpt, lcFile, loC, loErr
		This.cConfigFile = ""
		This.cFileProvider = ""
		This.cFileModel = ""
		lcOpt = TRANSFORM(This.oHost.Options.Get("data", "ai.config", ""))
		DO CASE
			CASE !EMPTY(lcOpt)
				lcFile = IIF(":" $ lcOpt OR LEFT(lcOpt, 2) == "\\", lcOpt, This.oHost.DataDir + lcOpt)
			CASE !EMPTY(This.cAixlDir)
				lcFile = This.cAixlDir + "aixl.config.json"
			OTHERWISE
				lcFile = ""
		ENDCASE
		IF EMPTY(lcFile) OR !FILE(lcFile)
			IF !EMPTY(lcOpt)
				This.oHost.LogWarn("data.ai: options.data.ai.config is " + lcOpt + ", and there is no such file")
			ENDIF
			RETURN .F.
		ENDIF
		This.cConfigFile = lcFile
		TRY
			loC = This.oHost.oJson.Parse(FILETOSTR(lcFile))
			This.cFileProvider = LOWER(TRANSFORM(This.oHost.oJson.Get(loC, "provider", "")))
			This.cFileModel = TRANSFORM(This.oHost.oJson.Get(loC, "modelName", ""))
		CATCH TO loErr
			This.oHost.LogWarn("data.ai: " + lcFile + " could not be read: " + loErr.Message)
		ENDTRY
		This.SyncCurrent()
		RETURN .T.
	ENDPROC

	*--------------------------------------------------------------
	* El primer uso: aixl.prg, el objeto, la versión y la sesión.
	*--------------------------------------------------------------
	PROCEDURE Ensure
		LOCAL lcVer, lcState0, lcCode, llLoaded, llRan, loErr
		IF !INLIST(This.cState, "ready")
			RETURN .F.
		ENDIF
		llLoaded = This.EnsureProcedure()
		*-- Una vez hecho, no se repite: si el usuario suelta el objeto (AIXL_RELEASE), aixl.prg crea
		*-- otro en la siguiente llamada, y nace con el doble. El módulo no repone la sesión:
		*-- lo que enseña lo lee del objeto vivo.
		IF This.lEnsured
			RETURN .T.
		ENDIF
		lcState0 = This.cState
		*-- Sin aixl.prg cargado no se llama a AIXL_VERSION() (las tools darían el error 1 crudo), y un
		*-- aixl.prg que no corre se queda en failed con su error.
		lcVer = ""
		llRan = .F.
		IF llLoaded
			TRY
				lcVer = AIXL_VERSION()
				llRan = .T.
			CATCH TO loErr
				This.cLoadError = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
			ENDTRY
		ENDIF
		IF PEMSTATUS(_screen, "cFoxDockAiVersion", 5) AND !EMPTY(_screen.cFoxDockAiVersion) AND !EMPTY(lcVer)
			lcVer = _screen.cFoxDockAiVersion
		ENDIF
		DO CASE
			CASE !llRan
				This.SetState("failed", "aixl.prg could not be " + IIF(llLoaded, "run", "loaded") + ": " + EVL(This.cLoadError, "?"), ;
					"AIXL_LOAD_FAILED")
			CASE EMPTY(lcVer)
				lcCode = AIXL_LAST_ERROR_CODE()
				This.SetState(IIF(lcCode == "HOST_ELEVATED", "elevated", "failed"), ;
					'AIXL did not start: "' + lcCode + '" ' + AIXL_LAST_ERROR(), lcCode)
			CASE !This.VersionAtLeast(lcVer, AI_MIN_VERSION)
				This.cVersion = lcVer
				This.SetState("failed", "AIXL " + lcVer + " found; " + AI_MIN_VERSION + " or later is needed", "AIXL_TOO_OLD")
			OTHERWISE
				This.cVersion = lcVer
				This.lEnsured = .T.
				This.ApplySession()
				This.oHost.Log("data.ai: AIXL " + lcVer + " ready (" + This.SessionText() + ")")
		ENDCASE
		IF !(This.cState == lcState0)
			This.oHost.RefreshMenu()
		ENDIF
		RETURN This.lEnsured
	ENDPROC

	*-- aixl.prg en SET PROCEDURE (CLOSE ALL y CLEAR ALL lo vacían).
	*-- De la caché de código de este motor, nunca de la carpeta de AIXL. La copia se
	*-- rehace cuando cambia el aixl.prg de AIXL (su tamaño y su fecha), y su .fxp viejo se borra (una copia
	*-- conserva la fecha del original: podría parecer más vieja que el .fxp). .T. si aixl.prg está cargado.
	*-- Un aixl cargado que no es el de esta caché (el usuario lo cargó él) se usa tal cual. El de esta caché, de un
	*-- montaje anterior (FdUnload y el Unload del host no sueltan SET PROCEDURE), solo si aixl.prg no
	*-- cambió desde que se copió; si cambió, se suelta y se copia otra vez.
	PROCEDURE EnsureProcedure
		LOCAL loErr, lcDst, lcSrc, lcStamp, lcPrint, lcSafety, lcLoaded
		LOCAL ARRAY laF[1]
		IF EMPTY(This.cAixlDir) OR !INLIST(This.cState, "ready", "failed", "elevated") OR This.cCode == "AIXL_LOAD_FAILED"
			RETURN .F.
		ENDIF
		lcSrc = This.cAixlDir + "aixl.prg"
		lcDst = This.CodeDir()
		lcStamp = lcDst + ".aixl-print"
		lcPrint = IIF(ADIR(laF, lcSrc) = 1, TRANSFORM(laF[1, 2]) + " " + DTOS(laF[1, 3]) + " " + laF[1, 4], "")
		lcLoaded = This.LoadedAixl()
		DO CASE
			CASE EMPTY(lcLoaded)
			CASE EMPTY(lcDst) OR !(UPPER(ADDBS(JUSTPATH(lcLoaded))) == UPPER(lcDst))
				RETURN .T.
			CASE FILE(lcStamp) AND FILETOSTR(lcStamp) == lcPrint
				RETURN .T.
			OTHERWISE
				TRY
					RELEASE PROCEDURE (lcLoaded)
				CATCH TO loErr
					This.oHost.LogWarn("data.ai: " + lcLoaded + " not released: " + loErr.Message)
				ENDTRY
		ENDCASE
		This.cLoadError = ""
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		TRY
			IF EMPTY(lcDst)
				ERROR "FoxDock has no code folder for this engine"
			ENDIF
			IF EMPTY(lcPrint)
				ERROR "File '" + lcSrc + "' does not exist."
			ENDIF
			IF !FILE(lcDst + "aixl.prg") OR !FILE(lcStamp) OR !(FILETOSTR(lcStamp) == lcPrint)
				This.oHost.MakeDirs(lcDst)
				IF FILE(lcDst + "aixl.fxp")
					ERASE (lcDst + "aixl.fxp")
				ENDIF
				COPY FILE (lcSrc) TO (lcDst + "aixl.prg")
				=STRTOFILE(lcPrint, lcStamp)
				This.oHost.Log("data.ai: aixl.prg copied to " + lcDst + " (it compiles there, never in " + This.cAixlDir + ")")
			ENDIF
			SET PROCEDURE TO (lcDst + "aixl.prg") ADDITIVE
		CATCH TO loErr
			This.cLoadError = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
			This.oHost.LogWarn("data.ai: aixl.prg not loaded from " + lcDst + ": " + This.cLoadError)
		ENDTRY
		SET SAFETY &lcSafety
		RETURN EMPTY(This.cLoadError)
	ENDPROC

	*-- La caché de AIXL de este motor: <carpeta de datos>\fxp\<motor>\aixl\ ("" sin caché).
	PROCEDURE CodeDir
		RETURN IIF(EMPTY(This.oHost.cCodeDir), "", This.oHost.cCodeDir + "aixl\")
	ENDPROC

	*-- La ruta del aixl (.prg o .fxp) que hay en SET PROCEDURE, o "". SET("PROCEDURE") no repite la carpeta de
	*-- una entrada cuando es la de la anterior: se hereda.
	PROCEDURE LoadedAixl
		LOCAL lnI, lcItem, lcDir
		LOCAL ARRAY laP[1]
		lcDir = ""
		FOR lnI = 1 TO ALINES(laP, CHRTRAN(SET("PROCEDURE"), ",", CHR(13)), 1)
			lcItem = CHRTRAN(laP[lnI], '"', "")
			IF !EMPTY(JUSTPATH(lcItem))
				lcDir = ADDBS(JUSTPATH(lcItem))
			ENDIF
			IF UPPER(JUSTSTEM(lcItem)) == "AIXL" AND INLIST(UPPER(JUSTEXT(lcItem)), "PRG", "FXP")
				RETURN IIF(EMPTY(JUSTPATH(lcItem)), lcDir + lcItem, lcItem)
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- ¿Hay un objeto de AIXL vivo en esta sesión? (el del usuario o el nuestro: es el mismo).
	PROCEDURE HostAlive
		RETURN TYPE("_SCREEN.oAixlHost") == "O" AND !ISNULL(_SCREEN.oAixlHost)
	ENDPROC

	*-- La sesión que el usuario pidió: el doble (la opción), el proveedor en uso de
	*-- la lista, o el aixl.config.json.
	PROTECTED PROCEDURE ApplySession
		LOCAL loE
		This.cConfigNote = ""
		IF This.lMockWanted
			IF !AIXL_USE_MOCK()
				This.cConfigNote = '"' + AIXL_LAST_ERROR_CODE() + '" ' + AIXL_LAST_ERROR()
			ENDIF
			RETURN
		ENDIF
		loE = This.ActiveEntry()
		IF !ISNULL(loE)
			This.ApplyEntry(loE)
			RETURN
		ENDIF
		This.ReadConfig()
		IF EMPTY(This.cConfigFile)
			This.cConfigNote = "no provider configured"
			*-- Un objeto nuevo de AIXL nace con el doble: sin fichero, sigue con él. Uno
			*-- vivo vuelve a él: la clave de un proveedor borrado no se queda en la sesión.
			IF This.HostAlive()
				=AIXL_USE_MOCK()
			ENDIF
			RETURN
		ENDIF
		IF !AIXL_CONFIGURE_FROM_FILE(This.cConfigFile)
			This.cConfigNote = '"' + AIXL_LAST_ERROR_CODE() + '" ' + AIXL_LAST_ERROR()
			This.oHost.LogWarn("data.ai: " + This.cConfigFile + ": " + This.cConfigNote)
		ENDIF
	ENDPROC

	*-- ¿Es el doble? Lo dice el ProviderName del objeto vivo; sin objeto, lo pedido.
	PROCEDURE IsMock
		LOCAL lcP, loErr
		IF This.HostAlive()
			lcP = ""
			TRY
				lcP = LOWER(TRANSFORM(_SCREEN.oAixlHost.ProviderName))
			CATCH TO loErr
			ENDTRY
			RETURN LEFT(lcP, 4) == "mock"
		ENDIF
		RETURN This.lMockWanted
	ENDPROC

	*-- El proveedor en uso: el del objeto vivo; sin objeto, el del aixl.config.json.
	PROCEDURE ProviderNow
		LOCAL lcP, loErr
		IF This.HostAlive()
			lcP = ""
			TRY
				lcP = LOWER(TRANSFORM(_SCREEN.oAixlHost.ProviderName))
			CATCH TO loErr
			ENDTRY
			RETURN lcP
		ENDIF
		RETURN IIF(This.lMockWanted, "mock", This.cProvider)
	ENDPROC

	PROCEDURE SessionText
		LOCAL lcP
		lcP = This.ProviderNow()
		DO CASE
			CASE LEFT(lcP, 4) == "mock"
				RETURN lcP + ": nothing is sent"
			CASE EMPTY(lcP)
				RETURN EVL(This.cConfigNote, "no provider configured")
			OTHERWISE
				RETURN lcP + IIF(EMPTY(This.cModel), "", " (" + This.cModel + ")") + IIF(EMPTY(This.cConfigNote), "", "; " + This.cConfigNote)
		ENDCASE
	ENDPROC

	*-- «1.1.3» contra «1.1.10»: tres números, no texto.
	PROCEDURE VersionAtLeast
		LPARAMETERS tcHave, tcNeed
		LOCAL lnI, lnH, lnN
		FOR lnI = 1 TO 3
			lnH = VAL(GETWORDNUM(tcHave, lnI, "."))
			lnN = VAL(GETWORDNUM(tcNeed, lnI, "."))
			IF lnH != lnN
				RETURN lnH > lnN
			ENDIF
		ENDFOR
		RETURN .T.
	ENDPROC

	*--------------------------------------------------------------
	* El menú: Data > AI.
	*--------------------------------------------------------------
	PROCEDURE FillMenu
		LPARAMETERS tcPopup, tnBar
		LOCAL loP, lcA, lcMsg, llOff, lcOff
		loP = This.Plugin()
		lcA = tcPopup + "AI"
		tnBar = loP.DefineSubmenu(tcPopup, tnBar + 1, This.T("data.ai.menu"), lcA)
		IF This.cState == "ready"
			*-- Las cinco operaciones arriba, apagadas sin proveedor; un
			*-- separador; el submenú del proveedor y Last run.
			llOff = !This.IsConfigured()
			lcOff = This.T("data.ai.needsProvider")
			loP.DefineBar(lcA, 1, This.T("data.ai.classify"), "AiOp", "classify", IIF(llOff, lcOff, This.T("data.ai.classify.message")), llOff)
			loP.DefineBar(lcA, 2, This.T("data.ai.extract"), "AiOp", "extract", IIF(llOff, lcOff, This.T("data.ai.extract.message")), llOff)
			loP.DefineBar(lcA, 3, This.T("data.ai.anonymize"), "AiOp", "anonymize", IIF(llOff, lcOff, This.T("data.ai.anonymize.message")), llOff)
			loP.DefineBar(lcA, 4, This.T("data.ai.filter"), "AiOp", "filter", IIF(llOff, lcOff, This.T("data.ai.filter.message")), llOff)
			loP.DefineBar(lcA, 5, This.T("data.ai.ask"), "AiOp", "ask", IIF(llOff, lcOff, This.T("data.ai.ask.message")), llOff)
			loP.DefineBar(lcA, 6, "", "")
			This.FillProviderMenu(lcA, 7)
			loP.DefineBar(lcA, 8, This.LastRunCaption(), "AiStatus", "", "", .T.)
		ELSE
			*-- El MESSAGE de una barra no admite la frase larga con la ruta del caso 2 (DEFINE BAR
			*-- falla y el submenú se queda vacío): recortada; entera, al pulsarla.
			lcMsg = This.HelpText()
			loP.DefineBar(lcA, 1, This.T("data.ai.case." + This.cState), "AiHelp", "", ;
				IIF(LEN(lcMsg) > 200, LEFT(lcMsg, 197) + "...", lcMsg))
		ENDIF
		RETURN tnBar
	ENDPROC

	*-- «Provider: <el de la sesión>»: un submenú con los de la lista (la marca en el
	*-- que está en uso), un separador y Manage providers...
	PROCEDURE FillProviderMenu
		LPARAMETERS tcPopup, tnBar
		LOCAL loP, lcS, lnI, loE, lnB, lcCmd, lcActive
		loP = This.Plugin()
		lcS = tcPopup + "P"
		loP.DefineSubmenu(tcPopup, tnBar, This.ProviderCaption(), lcS)
		lcActive = This.ActiveId()
		lnB = 0
		FOR lnI = 1 TO This.oProviders.Count
			loE = This.oProviders.Item(lnI)
			lnB = lnB + 1
			loP.DefineBar(lcS, lnB, loE.cName, "AiUse", loE.cId, ;
				loE.cProvider + IIF(EMPTY(loE.cModel), "", " (" + loE.cModel + ")"))
			lcCmd = "SET MARK OF BAR " + TRANSFORM(lnB) + " OF " + lcS + " TO " + IIF(loE.cId == lcActive, ".T.", ".F.")
			&lcCmd
		ENDFOR
		IF lnB > 0
			lnB = lnB + 1
			loP.DefineBar(lcS, lnB, "", "")
		ENDIF
		loP.DefineBar(lcS, lnB + 1, This.T("data.ai.providers"), "AiProviders", "", This.T("data.ai.providers.message"))
		RETURN tnBar
	ENDPROC

	*-- El de la sesión: el doble, el nombre del que está en uso, el del
	*-- aixl.config.json o ninguno. Del objeto vivo cuando lo hay (el usuario puede
	*-- haber cambiado la sesión desde la ventana de comandos).
	PROCEDURE ProviderCaption
		LOCAL lcP, loE
		lcP = This.ProviderNow()
		loE = This.ActiveEntry()
		DO CASE
			CASE !This.IsConfigured() AND !(LEFT(lcP, 4) == "mock" AND This.lMockWanted)
				RETURN This.T("data.ai.provider", This.T("data.ai.provider.none"))
			CASE LEFT(lcP, 4) == "mock"
				RETURN This.T("data.ai.provider", This.T("data.ai.provider.mock"))
			CASE !ISNULL(loE) AND (lcP == loE.cProvider OR !This.HostAlive())
				RETURN This.T("data.ai.provider", loE.cName)
			CASE EMPTY(lcP)
				RETURN This.T("data.ai.provider", This.T("data.ai.provider.none"))
			OTHERWISE
				RETURN This.T("data.ai.provider", lcP + IIF(EMPTY(This.cModel), "", " (" + This.cModel + ")"))
		ENDCASE
	ENDPROC

	PROCEDURE LastRunCaption
		IF ISNULL(This.oLastRun)
			RETURN This.T("data.ai.lastRun", This.T("data.ai.lastRun.none"))
		ENDIF
		RETURN This.T("data.ai.lastRun", This.T("data.ai.lastRun.text", This.oLastRun.nRows, This.oLastRun.nTokens, ;
			TRANSFORM(This.oLastRun.nSeconds)))
	ENDPROC

	*-- La frase larga de la barra apagada (la barra de estado y el log).
	PROCEDURE HelpText
		RETURN ICASE(This.cState == "not_installed", This.T("data.ai.help.not_installed", AI_MIN_VERSION), ;
			This.cState == "no_library", This.T("data.ai.help.no_library", This.cDllPath), ;
			This.cState == "elevated", This.T("data.ai.help.elevated"), ;
			This.cCode == "AIXL_TOO_OLD", This.T("data.ai.help.old", This.cVersion, AI_MIN_VERSION), ;
			This.T("data.ai.help.failed", This.oHost.Quoted(This.cDetail)))
	ENDPROC

	PROCEDURE HelpTextEn
		RETURN ICASE(This.cState == "not_installed", This.oHost.TranslateEn("data.ai.help.not_installed", AI_MIN_VERSION), ;
			This.cState == "no_library", This.oHost.TranslateEn("data.ai.help.no_library", This.cDllPath), ;
			This.cState == "elevated", This.oHost.TranslateEn("data.ai.help.elevated"), ;
			This.cCode == "AIXL_TOO_OLD", This.oHost.TranslateEn("data.ai.help.old", This.cVersion, AI_MIN_VERSION), ;
			This.oHost.TranslateEn("data.ai.help.failed", This.cDetail))
	ENDPROC

	*-- Pública: la usan las ventanas del módulo (DataAiClassifyForm.Texts).
	PROCEDURE T
		LPARAMETERS tcKey, tv1, tv2, tv3, tv4, tv5, tv6
		RETURN This.oHost.Translate(tcKey, tv1, tv2, tv3, tv4, tv5, tv6)
	ENDPROC

	*-- Las ventanas abiertas vuelven a poner sus textos (el host llama a
	*-- BuildMenu al cambiar de idioma). Una que falla no para a las demás.
	PROCEDURE Retext
		LOCAL loF, loErr
		FOR EACH loF IN This.oForms FOXOBJECT
			TRY
				loF.Texts()
			CATCH TO loErr
				This.oHost.LogWarn("data.ai: the texts of " + loF.Name + " could not be put again: " + loErr.Message)
			ENDTRY
		ENDFOR
	ENDPROC

	PROCEDURE FormGone
		LPARAMETERS tcKey
		IF !EMPTY(tcKey) AND This.oForms.GetKey(tcKey) > 0
			This.oForms.Remove(tcKey)
		ENDIF
	ENDPROC

	*-- Al desmontar: las ventanas se sueltan.
	PROCEDURE CloseAll
		LOCAL lnI, loF
		FOR lnI = This.oForms.Count TO 1 STEP -1
			loF = This.oForms.Item(lnI)
			loF.Release()
		ENDFOR
		This.oForms = CREATEOBJECT("Collection")
	ENDPROC

	*--------------------------------------------------------------
	* Las barras.
	*--------------------------------------------------------------
	*-- La barra apagada: lo que hace falta, en la barra de estado y en el log, y la ficha de AIXL.
	PROCEDURE Help
		LOCAL loP
		This.oHost.Notify(This.HelpText(), "data.ai: " + This.HelpTextEn())
		loP = This.Plugin()
		=loP.OpenWithWindows(AI_PRODUCT_URL)
		RETURN .F.
	ENDPROC

	*--------------------------------------------------------------
	* Los proveedores. Ver la cabecera.
	*--------------------------------------------------------------
	*-- ¿Hay con qué trabajar? El doble de la opción, uno en uso de la lista o un
	*-- aixl.config.json con un proveedor. No mira el objeto vivo: uno nuevo nace
	*-- con el doble, y eso no es tener un proveedor.
	PROCEDURE IsConfigured
		RETURN This.lMockWanted OR !ISNULL(This.ActiveEntry()) OR ;
			(!EMPTY(This.cFileProvider) AND !(LEFT(This.cFileProvider, 4) == "mock"))
	ENDPROC

	*-- Proveedor y modelo de ahora (los captions, la frase del coste, la tool).
	PROCEDURE SyncCurrent
		LOCAL loE
		loE = This.ActiveEntry()
		IF ISNULL(loE)
			This.cProvider = This.cFileProvider
			This.cModel = This.cFileModel
		ELSE
			This.cProvider = loE.cProvider
			This.cModel = loE.cModel
		ENDIF
	ENDPROC

	PROCEDURE ProvidersFile
		RETURN This.oHost.DataDir + "ai-providers.json"
	ENDPROC

	PROCEDURE SecretFile
		LPARAMETERS tcId
		RETURN This.oHost.DataDir + "secrets\ai-" + LOWER(tcId) + ".cred"
	ENDPROC

	PROCEDURE ActiveId
		RETURN LOWER(ALLTRIM(TRANSFORM(This.oHost.Options.Get("data", "ai.provider", ""))))
	ENDPROC

	PROCEDURE ActiveEntry
		LOCAL lcId
		lcId = This.ActiveId()
		IF EMPTY(lcId) OR VARTYPE(This.oProviders) # "O" OR This.oProviders.GetKey(lcId) = 0
			RETURN .NULL.
		ENDIF
		RETURN This.oProviders.Item(lcId)
	ENDPROC

	*-- ai-providers.json: un array de objetos planos (id, name, provider, model,
	*-- endpoint, keySource: windows o environment, keyVariable). Uno sin id o sin
	*-- proveedor se queda fuera, y el log lo dice.
	PROCEDURE LoadProviders
		LOCAL lcFile, lcText, loJ, loObjs, loC, loE, lnI
		This.oProviders = CREATEOBJECT("Collection")
		lcFile = This.ProvidersFile()
		IF !FILE(lcFile)
			RETURN 0
		ENDIF
		lcText = FILETOSTR(lcFile)
		lcText = STRCONV(IIF(LEFT(lcText, 3) == CHR(0xEF) + CHR(0xBB) + CHR(0xBF), SUBSTR(lcText, 4), lcText), 11)
		loJ = This.oHost.oJson
		loObjs = loJ.Split(lcText)
		FOR lnI = 1 TO loObjs.Count
			loC = loJ.Parse(loObjs.Item(lnI))
			loE = This.NewEntry(LOWER(This.CStr(loJ.Get(loC, "id", ""))), This.CStr(loJ.Get(loC, "name", "")), ;
				LOWER(This.CStr(loJ.Get(loC, "provider", ""))), This.CStr(loJ.Get(loC, "model", "")), ;
				This.CStr(loJ.Get(loC, "endpoint", "")), LOWER(This.CStr(loJ.Get(loC, "keysource", "windows"))), ;
				This.CStr(loJ.Get(loC, "keyvariable", "")))
			IF EMPTY(loE.cId) OR EMPTY(loE.cProvider) OR This.oProviders.GetKey(loE.cId) > 0
				This.oHost.LogWarn("data.ai: provider " + TRANSFORM(lnI) + " of " + lcFile + " is left out (no id, no provider, or an id seen before)")
				LOOP
			ENDIF
			This.oProviders.Add(loE, loE.cId)
		ENDFOR
		*-- Por una variable: VFP no encadena sobre lo que devuelve un método.
		loE = This.ActiveEntry()
		This.oHost.Log("data.ai: " + TRANSFORM(This.oProviders.Count) + " provider(s) in " + lcFile + ;
			IIF(ISNULL(loE), "", "; in use: " + loE.cName))
		RETURN This.oProviders.Count
	ENDPROC

	PROCEDURE NewEntry
		LPARAMETERS tcId, tcName, tcProvider, tcModel, tcEndpoint, tcKeySource, tcKeyVariable
		LOCAL loE
		loE = CREATEOBJECT("Empty")
		ADDPROPERTY(loE, "cId", tcId)
		ADDPROPERTY(loE, "cName", EVL(tcName, tcId))
		ADDPROPERTY(loE, "cProvider", tcProvider)
		ADDPROPERTY(loE, "cModel", tcModel)
		ADDPROPERTY(loE, "cEndpoint", tcEndpoint)
		ADDPROPERTY(loE, "cKeySource", IIF(tcKeySource == "environment", "environment", "windows"))
		ADDPROPERTY(loE, "cKeyVariable", tcKeyVariable)
		RETURN loE
	ENDPROC

	*-- Escribe ai-providers.json (UTF-8, sin claves). "" o el porqué.
	PROTECTED PROCEDURE WriteProviders
		LOCAL lcOut, lnI, loE, loJ, lcSafety, lcErr, loErr
		loJ = This.oHost.oJson
		lcOut = ""
		FOR lnI = 1 TO This.oProviders.Count
			loE = This.oProviders.Item(lnI)
			lcOut = lcOut + IIF(EMPTY(lcOut), "", "," + CRLF) + "  { " + ;
				'"id": ' + loJ.Quote(loE.cId) + ', "name": ' + loJ.Quote(loE.cName) + ;
				', "provider": ' + loJ.Quote(loE.cProvider) + ', "model": ' + loJ.Quote(loE.cModel) + ;
				', "endpoint": ' + loJ.Quote(loE.cEndpoint) + ', "keySource": ' + loJ.Quote(loE.cKeySource) + ;
				', "keyVariable": ' + loJ.Quote(loE.cKeyVariable) + " }"
		ENDFOR
		lcErr = ""
		*-- STRTOFILE pregunta con SET SAFETY ON.
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		TRY
			=STRTOFILE(STRCONV("[" + CRLF + lcOut + IIF(EMPTY(lcOut), "", CRLF) + "]" + CRLF, 9), This.ProvidersFile())
		CATCH TO loErr
			lcErr = loErr.Message
		FINALLY
			SET SAFETY &lcSafety
		ENDTRY
		RETURN lcErr
	ENDPROC

	*-- El id de un nombre nuevo: letras y números en minúsculas, guiones, y único.
	PROCEDURE IdFor
		LPARAMETERS tcName
		LOCAL lcId, lnI, lcC, lcOut, lnN
		lcOut = ""
		lcId = LOWER(ALLTRIM(tcName))
		FOR lnI = 1 TO LEN(lcId)
			lcC = SUBSTR(lcId, lnI, 1)
			lcOut = lcOut + IIF(BETWEEN(lcC, "a", "z") OR BETWEEN(lcC, "0", "9"), lcC, IIF(RIGHT(lcOut, 1) == "-", "", "-"))
		ENDFOR
		lcOut = LEFT(CHRTRAN(ALLTRIM(CHRTRAN(lcOut, "-", " ")), " ", "-"), 30)
		lcOut = EVL(lcOut, "provider")
		lcId = lcOut
		lnN = 1
		DO WHILE This.oProviders.GetKey(lcId) > 0
			lnN = lnN + 1
			lcId = lcOut + "-" + TRANSFORM(lnN)
		ENDDO
		RETURN lcId
	ENDPROC

	*-- La variable de entorno, como la vería el usuario: la del proceso, y si no la
	*-- de su usuario o la del equipo (el registro, en el momento: una creada con VFP
	*-- abierto también se ve).
	PROCEDURE EnvValue
		LPARAMETERS tcName
		RETURN IIF(EMPTY(tcName), "", This.EnvFrom(ALLTRIM(tcName)))
	ENDPROC

	PROTECTED PROCEDURE EnvFrom
		LPARAMETERS tcName
		LOCAL loW, lcV, lnI, loErr
		lcV = ""
		TRY
			loW = CREATEOBJECT("WScript.Shell")
			FOR lnI = 1 TO 3
				lcV = loW.Environment(GETWORDNUM("PROCESS,USER,SYSTEM", lnI, ",")).Item(tcName)
				IF !EMPTY(lcV)
					EXIT
				ENDIF
			ENDFOR
		CATCH TO loErr
			lcV = ""
		ENDTRY
		IF EMPTY(lcV)
			lcV = GETENV(tcName)
		ENDIF
		RETURN ALLTRIM(lcV, 1, " ", CHR(9), CHR(13), CHR(10))
	ENDPROC

	*-- La clave de un proveedor, o "" (y por qué, en inglés, en cKeyWhy).
	PROCEDURE KeyOf
		LPARAMETERS toE
		LOCAL loD, lcK, loP
		This.cKeyWhy = ""
		IF toE.cKeySource == "environment"
			lcK = This.EnvValue(toE.cKeyVariable)
			IF EMPTY(lcK)
				This.cKeyWhy = "the environment variable " + toE.cKeyVariable + " is not defined, neither for this process, your user nor the machine"
			ENDIF
			RETURN lcK
		ENDIF
		IF !FILE(This.SecretFile(toE.cId))
			This.cKeyWhy = "no key is saved for " + toE.cName
			RETURN ""
		ENDIF
		loP = This.Plugin()
		loD = NEWOBJECT("DataDpapi", loP.CodeFile("DataConnections.prg"))
		lcK = loD.Unprotect(FILETOSTR(This.SecretFile(toE.cId)))
		IF EMPTY(lcK)
			This.cKeyWhy = "the saved key of " + toE.cName + " could not be decrypted (CryptUnprotectData, error " + ;
				TRANSFORM(loD.nLastError) + "): it was saved by another Windows user, or on another machine"
		ENDIF
		RETURN lcK
	ENDPROC

	*-- Lo que la ventana enseña de la clave: cuánto mide, nunca cuál es.
	PROCEDURE KeyLength
		LPARAMETERS toE
		RETURN LEN(This.KeyOf(toE))
	ENDPROC

	*-- Uno de la lista, en la sesión de AIXL: proveedor, modelo y servidor local por
	*-- un fichero sin clave, la clave en memoria y la licencia.
	PROTECTED PROCEDURE ApplyEntry
		LPARAMETERS toE
		LOCAL lcKey, lcFile, lcSafety, loJ, lcErr, loErr, lcLic, lcDir
		loJ = This.oHost.oJson
		lcKey = This.KeyOf(toE)
		IF EMPTY(lcKey)
			This.cConfigNote = This.cKeyWhy
			This.oHost.LogWarn("data.ai: " + toE.cName + ": " + This.cKeyWhy)
			RETURN .F.
		ENDIF
		lcFile = This.oHost.DataDir + "ai\session.json"
		lcErr = ""
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		TRY
			lcDir = JUSTPATH(lcFile)
			IF !DIRECTORY(lcDir, 1)
				MKDIR (lcDir)
			ENDIF
			=STRTOFILE(STRCONV('{ "provider": ' + loJ.Quote(toE.cProvider) + ', "modelName": ' + loJ.Quote(toE.cModel) + ;
				', "endpoint": ' + loJ.Quote(toE.cEndpoint) + ' }' + CRLF, 9), lcFile)
		CATCH TO loErr
			lcErr = loErr.Message
		FINALLY
			SET SAFETY &lcSafety
		ENDTRY
		DO CASE
			CASE !EMPTY(lcErr)
				This.cConfigNote = lcFile + " could not be written: " + lcErr
			CASE !AIXL_CONFIGURE_FROM_FILE(lcFile) OR !AIXL_CONFIGURE(toE.cProvider, lcKey, toE.cModel)
				This.cConfigNote = '"' + AIXL_LAST_ERROR_CODE() + '" ' + AIXL_LAST_ERROR()
		ENDCASE
		lcKey = ""
		IF EMPTY(This.cConfigNote)
			lcLic = This.LicenseText()
			IF !EMPTY(lcLic) AND !AIXL_ACTIVATE(lcLic)
				This.cConfigNote = '"' + AIXL_LAST_ERROR_CODE() + '" ' + AIXL_LAST_ERROR()
			ENDIF
		ENDIF
		IF !EMPTY(This.cConfigNote)
			This.oHost.LogWarn("data.ai: " + toE.cName + ": " + This.cConfigNote)
			RETURN .F.
		ENDIF
		This.oHost.Log("data.ai: in use: " + toE.cName + " (" + toE.cProvider + IIF(EMPTY(toE.cModel), "", ", " + toE.cModel) + ;
			IIF(EMPTY(toE.cEndpoint), "", ", " + toE.cEndpoint) + "; key from " + ;
			IIF(toE.cKeySource == "environment", "the environment variable " + toE.cKeyVariable, "Windows (DPAPI)") + ")")
		RETURN .T.
	ENDPROC

	*-- La licencia: el fichero de options.data.ai.license, sin las líneas de
	*-- comentario (# ...) que llevan las de cortesía. "" si no hay.
	PROCEDURE LicenseText
		LOCAL lcFile, lcOut, lnI
		LOCAL ARRAY laL[1]
		lcFile = This.LicenseFile()
		IF EMPTY(lcFile) OR !FILE(lcFile)
			RETURN ""
		ENDIF
		lcOut = ""
		FOR lnI = 1 TO ALINES(laL, FILETOSTR(lcFile), 1)
			IF !EMPTY(laL[lnI]) AND !(LEFT(laL[lnI], 1) == "#")
				lcOut = lcOut + laL[lnI]
			ENDIF
		ENDFOR
		RETURN lcOut
	ENDPROC

	PROCEDURE LicenseFile
		RETURN ALLTRIM(TRANSFORM(This.oHost.Options.Get("data", "ai.license", "")))
	ENDPROC

	*-- La licencia de la ventana: la ruta de un fichero, o el texto entero (se
	*-- guarda en <carpeta de datos>\aixl.lic). "" o el porqué (en el idioma).
	PROCEDURE SaveLicense
		LPARAMETERS tcText
		LOCAL lcText, lcFile, lcSafety
		lcText = ALLTRIM(EVL(tcText, ""), 1, " ", CHR(9), CHR(13), CHR(10))
		DO CASE
			CASE EMPTY(lcText) OR lcText == This.LicenseFile()
				RETURN ""
			CASE LEFT(lcText, 3) == "eyJ"
				lcFile = This.oHost.DataDir + "aixl.lic"
				lcSafety = SET("SAFETY")
				SET SAFETY OFF
				=STRTOFILE(lcText, lcFile)
				SET SAFETY &lcSafety
			CASE FILE(lcText)
				lcFile = FULLPATH(lcText)
			OTHERWISE
				RETURN This.T("data.ai.providers.noLicense", lcText)
		ENDCASE
		This.oHost.Options.Set("data", "ai.license", lcFile)
		This.oHost.Log("data.ai: the AIXL licence is " + lcFile)
		RETURN ""
	ENDPROC

	*-- Guarda uno (toD: cId vacío si es nuevo, cName, cProvider, cModel, cEndpoint,
	*-- cKeySource, cKey, cKeyVariable). "" (y toD.cId) o el porqué, en el idioma.
	*-- El primero que se guarda queda en uso; uno en uso se vuelve a aplicar.
	PROCEDURE SaveEntry
		LPARAMETERS toD
		LOCAL loE, lnI, lcName, lcErr, llNew, loDp, lcBlob, lcSafety, lcKey, loP, lcDir
		This.cLastNotice = ""
		IF This.lBusy
			RETURN This.T("data.ai.providers.busy")
		ENDIF
		lcName = ALLTRIM(toD.cName)
		lcKey = CHRTRAN(toD.cKey, " " + CHR(9) + CHR(13) + CHR(10), "")
		toD.cKeyVariable = UPPER(ALLTRIM(toD.cKeyVariable))
		llNew = EMPTY(toD.cId) OR This.oProviders.GetKey(toD.cId) = 0
		DO CASE
			CASE EMPTY(lcName)
				RETURN This.T("data.ai.providers.noName")
			CASE '"' $ lcName OR "[" $ lcName OR "]" $ lcName OR "\" $ lcName
				RETURN This.T("data.ai.providers.badName")
			CASE EMPTY(toD.cProvider)
				RETURN This.T("data.ai.providers.noProvider")
			CASE toD.cKeySource == "environment" AND EMPTY(toD.cKeyVariable)
				RETURN This.T("data.ai.providers.noVariable")
			CASE toD.cKeySource == "windows" AND EMPTY(lcKey) AND (llNew OR !FILE(This.SecretFile(toD.cId)))
				RETURN This.T("data.ai.providers.noKey", toD.cProvider)
		ENDCASE
		FOR lnI = 1 TO This.oProviders.Count
			loE = This.oProviders.Item(lnI)
			IF LOWER(loE.cName) == LOWER(lcName) AND !(loE.cId == toD.cId)
				RETURN This.T("data.ai.providers.nameTaken", lcName)
			ENDIF
		ENDFOR
		IF llNew
			toD.cId = This.IdFor(lcName)
		ENDIF
		*-- La clave, cifrada con la cuenta de Windows; con la variable, la guardada se borra.
		IF toD.cKeySource == "windows" AND !EMPTY(lcKey)
			loP = This.Plugin()
			loDp = NEWOBJECT("DataDpapi", loP.CodeFile("DataConnections.prg"))
			lcBlob = loDp.Protect(lcKey)
			IF EMPTY(lcBlob)
				RETURN This.T("data.ai.providers.notEncrypted", loDp.nLastError)
			ENDIF
			*-- MKDIR no admite la expresión entera en el nombre: por una variable.
			lcDir = JUSTPATH(This.SecretFile(toD.cId))
			IF !DIRECTORY(lcDir, 1)
				MKDIR (lcDir)
			ENDIF
			lcSafety = SET("SAFETY")
			SET SAFETY OFF
			=STRTOFILE(lcBlob, This.SecretFile(toD.cId))
			SET SAFETY &lcSafety
		ENDIF
		IF toD.cKeySource == "environment" AND FILE(This.SecretFile(toD.cId))
			ERASE (This.SecretFile(toD.cId))
		ENDIF
		lcKey = ""
		loE = This.NewEntry(toD.cId, lcName, LOWER(toD.cProvider), ALLTRIM(toD.cModel), ALLTRIM(toD.cEndpoint), toD.cKeySource, ;
			IIF(toD.cKeySource == "environment", toD.cKeyVariable, ""))
		IF This.oProviders.GetKey(toD.cId) > 0
			This.oProviders.Remove(toD.cId)
		ENDIF
		This.oProviders.Add(loE, toD.cId)
		lcErr = This.WriteProviders()
		IF !EMPTY(lcErr)
			RETURN This.T("data.ai.settings.notWritten", This.ProvidersFile(), lcErr)
		ENDIF
		This.oHost.Log("data.ai: provider " + lcName + " saved (" + loE.cProvider + "; key from " + ;
			IIF(loE.cKeySource == "environment", "the environment variable " + loE.cKeyVariable, "Windows (DPAPI)") + ")")
		This.cLastNotice = This.T("data.ai.providers.saved", lcName)
		IF This.oProviders.Count = 1 OR This.ActiveId() == toD.cId
			RETURN This.UseProvider(toD.cId)
		ENDIF
		This.oHost.RefreshMenu()
		RETURN ""
	ENDPROC

	*-- Borra uno y su clave guardada. Si era el que estaba en uso, no queda ninguno en
	*-- uso: FoxDock nunca cambia de proveedor por su cuenta. Las operaciones se
	*-- apagan hasta que el usuario elige otro, y el aviso lo dice.
	PROCEDURE DeleteEntry
		LPARAMETERS tcId
		LOCAL lcName, llActive, lcErr
		This.cLastNotice = ""
		IF This.oProviders.GetKey(tcId) = 0
			RETURN ""
		ENDIF
		IF This.lBusy
			RETURN This.T("data.ai.providers.busy")
		ENDIF
		lcName = This.oProviders.Item(tcId).cName
		llActive = (This.ActiveId() == tcId)
		This.oProviders.Remove(tcId)
		IF FILE(This.SecretFile(tcId))
			ERASE (This.SecretFile(tcId))
		ENDIF
		lcErr = This.WriteProviders()
		IF !EMPTY(lcErr)
			RETURN This.T("data.ai.settings.notWritten", This.ProvidersFile(), lcErr)
		ENDIF
		This.oHost.Log("data.ai: provider " + lcName + " deleted")
		This.cLastNotice = This.T("data.ai.providers.deleted", lcName)
		IF llActive
			This.oHost.Options.Set("data", "ai.provider", "")
			This.SyncCurrent()
			IF This.lEnsured
				This.ApplySession()
			ENDIF
			This.cLastNotice = This.T("data.ai.providers.deletedInUse", lcName)
			This.oHost.Notify(This.cLastNotice, "data.ai: " + This.oHost.TranslateEn("data.ai.providers.deletedInUse", lcName))
		ENDIF
		This.oHost.RefreshMenu()
		RETURN ""
	ENDPROC

	*-- La barra de un proveedor del submenú, y Use this one de la ventana: en uso
	*-- desde ya. Nunca se cambia solo. "" o el porqué, en el idioma.
	PROCEDURE UseProvider
		LPARAMETERS tcId
		LOCAL loE, lcMsg, lcWhat
		tcId = LOWER(ALLTRIM(EVL(tcId, "")))
		IF This.oProviders.GetKey(tcId) = 0
			RETURN This.T("data.ai.providers.noSuch", tcId)
		ENDIF
		IF This.lBusy
			RETURN This.T("data.ai.providers.busy")
		ENDIF
		loE = This.oProviders.Item(tcId)
		lcWhat = loE.cName + " (" + loE.cProvider + IIF(EMPTY(loE.cModel), "", ", " + loE.cModel) + ")"
		*-- Sin su clave no se pone en uso: el menú marcaría uno y AIXL seguiría con otro.
		IF EMPTY(This.KeyOf(loE))
			lcMsg = This.T("data.ai.providers.failed", lcWhat, This.cKeyWhy)
			This.oHost.Notify(lcMsg, This.oHost.TranslateEn("data.ai.providers.failed", lcWhat, This.cKeyWhy))
			This.cLastNotice = IIF(EMPTY(This.cLastNotice), "", This.cLastNotice + " ") + lcMsg
			RETURN lcMsg
		ENDIF
		IF !(This.ActiveId() == tcId)
			This.oHost.Options.Set("data", "ai.provider", tcId)
		ENDIF
		This.SyncCurrent()
		This.cConfigNote = ""
		IF This.cState == "ready"
			IF This.lEnsured
				This.ApplySession()
			ELSE
				=This.Ensure()
			ENDIF
		ENDIF
		This.oHost.RefreshMenu()
		IF !EMPTY(This.cConfigNote)
			lcMsg = This.T("data.ai.providers.failed", lcWhat, This.cConfigNote)
			This.oHost.Notify(lcMsg, This.oHost.TranslateEn("data.ai.providers.failed", lcWhat, This.cConfigNote))
			This.cLastNotice = lcMsg
			RETURN lcMsg
		ENDIF
		*-- Con el doble puesto, queda elegido pero no se envía nada.
		lcMsg = This.T(IIF(This.lMockWanted, "data.ai.providers.usingMock", "data.ai.providers.using"), lcWhat)
		This.oHost.Notify(lcMsg, This.oHost.TranslateEn(IIF(This.lMockWanted, "data.ai.providers.usingMock", "data.ai.providers.using"), lcWhat))
		This.cLastNotice = IIF(EMPTY(This.cLastNotice), "", This.cLastNotice + " ") + lcMsg
		RETURN ""
	ENDPROC

	*-- La barra: la ventana, una sola (si ya está abierta, se trae delante).
	PROCEDURE OpenProviders
		LOCAL loF
		IF This.oForms.GetKey("providers") > 0
			loF = This.oForms.Item("providers")
			loF.Show()
			RETURN loF
		ENDIF
		loF = NEWOBJECT("DataAiProvidersForm", This.CodeFile(), "", This)
		loF.cKey = "providers"
		This.oForms.Add(loF, loF.cKey)
		loF.Show()
		RETURN loF
	ENDPROC

	*-- Los modelos de cada proveedor para la ventana, separados por comas: quien
	*-- configura un proveedor no suele saberlos. El primero es el que pone el SDK
	*-- de AIXL cuando modelName va vacío, el probado; los demás salen del catálogo
	*-- del proveedor, sin el smoke de AIXL (su manual, § 4.1).
	*-- De Monica, que no expone /v1/models, los que respondieron uno a uno. El
	*-- combo deja escribir otro.
	PROCEDURE ModelsFor
		LPARAMETERS tcProvider
		DO CASE
			CASE tcProvider == "deepseek"
				RETURN "deepseek-chat,deepseek-reasoner"
			CASE tcProvider == "openai"
				RETURN "gpt-5.6-sol,gpt-6-astra,gpt-5,gpt-4.1,gpt-4o-mini,o4-mini"
			CASE tcProvider == "anthropic"
				RETURN "claude-sonnet-5,claude-sonnet-5-5,claude-opus-5-5,claude-haiku-5-5,claude-opus-5"
			CASE tcProvider == "gemini"
				RETURN "gemini-3.8-flash,gemini-3.1-pro-preview,gemini-2.5-flash"
			CASE tcProvider == "groq"
				RETURN "openai/gpt-oss-120b,openai/gpt-oss-20b"
			CASE tcProvider == "monica"
				RETURN "gpt-5,gpt-4.1,gpt-4o,gpt-4o-mini,o4-mini,gemini-2.5-flash"
		ENDCASE
		RETURN ""
	ENDPROC

	PROTECTED PROCEDURE CStr
		LPARAMETERS tvValue
		RETURN IIF(VARTYPE(tvValue) == "C", tvValue, "")
	ENDPROC

	*--------------------------------------------------------------
	* Para el agente.
	*--------------------------------------------------------------
	*-- ide_data_ai_status siempre, también sin AIXL; las de
	*-- operación, solo con AIXL listo.
	PROCEDURE GetAgentTools
		LPARAMETERS toTools
		toTools.Add(CREATEOBJECT("IdeDataAiStatusTool"))
		IF This.cState == "ready"
			toTools.Add(CREATEOBJECT("IdeDataAiClassifyTool"))
			toTools.Add(CREATEOBJECT("IdeDataAiExtractTool"))
			toTools.Add(CREATEOBJECT("IdeDataAiAnonymizeTool"))
			toTools.Add(CREATEOBJECT("IdeDataAiFilterTool"))
			toTools.Add(CREATEOBJECT("IdeDataAiAskTool"))
			RETURN 6
		ENDIF
		RETURN 1
	ENDPROC

	*-- ide_data_ai_status, como objeto (la tool lo pasa a JSON). Crea el objeto
	*-- de AIXL si hace falta (Ensure). Nunca la clave ni la licencia.
	PROCEDURE ToolStatus
		LOCAL loJ, loD, loE
		IF This.cState == "ready"
			=This.Ensure()
		ENDIF
		loJ = This.oHost.oJson
		loD = loJ.MakeObject()
		loJ.Put(loD, "installed", !(This.cState == "not_installed"))
		loJ.Put(loD, "state", This.cState)
		loJ.Put(loD, "detail", This.cDetail)
		loJ.Put(loD, "code", IIF(EMPTY(This.cCode), .NULL., This.cCode))
		loJ.Put(loD, "aixlDir", IIF(EMPTY(This.cAixlDir), .NULL., This.cAixlDir))
		loJ.Put(loD, "foundBy", IIF(EMPTY(This.cFoundBy), .NULL., This.cFoundBy))
		loJ.Put(loD, "version", IIF(EMPTY(This.cVersion), .NULL., This.cVersion))
		*-- Sin proveedor, el objeto nace con el doble, pero las
		*-- operaciones no van a ninguna parte (NO_PROVIDER): ni mock ni proveedor, como dice el menú.
		loJ.Put(loD, "mock", IIF(This.cState == "ready", This.IsConfigured() AND This.IsMock(), .NULL.))
		*-- Proveedor y modelo, solo con AIXL listo: sin él no hay sesión, aunque haya un aixl.config.json.
		loJ.Put(loD, "provider", IIF(!(This.cState == "ready") OR !This.IsConfigured() OR EMPTY(This.ProviderNow()), .NULL., This.ProviderNow()))
		loJ.Put(loD, "model", IIF(!(This.cState == "ready") OR !This.IsConfigured() OR EMPTY(This.cModel) OR This.IsMock(), .NULL., This.cModel))
		loJ.Put(loD, "configFile", IIF(EMPTY(This.cConfigFile), .NULL., This.cConfigFile))
		loJ.Put(loD, "configNote", IIF(EMPTY(This.cConfigNote), .NULL., This.cConfigNote))
		*-- Los proveedores: si hay con qué trabajar, el de la lista en uso y de
		*-- dónde sale su clave (windows o environment). Nunca la clave ni la variable.
		loE = This.ActiveEntry()
		loJ.Put(loD, "configured", This.IsConfigured())
		loJ.Put(loD, "providerName", IIF(ISNULL(loE), .NULL., loE.cName))
		loJ.Put(loD, "keySource", IIF(ISNULL(loE), .NULL., loE.cKeySource))
		IF ISNULL(This.oLastRun)
			loJ.Put(loD, "lastRun", .NULL.)
		ELSE
			loJ.Put(loD, "lastRun", loJ.ToObject('{"rows": ' + TRANSFORM(This.oLastRun.nRows) + ', "tokens": ' + ;
				TRANSFORM(This.oLastRun.nTokens) + ', "seconds": ' + TRANSFORM(This.oLastRun.nSeconds) + '}'))
		ENDIF
		loJ.Put(loD, "busy", IIF(This.lBusy, This.BusyText(), .NULL.))
		RETURN loD
	ENDPROC

	*--------------------------------------------------------------
	* Las operaciones.
	*--------------------------------------------------------------
	PROCEDURE OpenClassify
		RETURN This.OpenOp("classify")
	ENDPROC

	*-- La barra: la tabla de trabajo (DataTable: el alias seleccionado en la
	*-- sesión 1, o un .dbf por GETFILE) y la ventana de la operación tcKind
	*-- (classify, extract, anonymize, filter, ask). Devuelve la ventana.
	PROCEDURE OpenOp
		LPARAMETERS tcKind
		LOCAL loT, loF, lcSource, lcName, lcCols, llDbf, loErr, llNeedsText
		tcKind = LOWER(EVL(tcKind, "classify"))
		llNeedsText = INLIST(tcKind, "classify", "extract", "anonymize")
		IF !This.Ensure()
			=This.Help()
			RETURN .NULL.
		ENDIF
		IF !This.IsConfigured()
			This.oHost.Notify(This.T("data.ai.needsProvider"), This.oHost.TranslateEn("data.ai.needsProvider"))
			RETURN .NULL.
		ENDIF
		loT = CREATEOBJECT("DataTable")
		lcSource = ""
		TRY
			IF loT.Open("", .T.)
				lcSource = loT.cSource
				lcName = loT.cName
				llDbf = loT.lOpened
				lcCols = This.TextColumns(loT.cAlias)
			ELSE
				IF !EMPTY(loT.cError)
					This.oHost.NotifyQuoted("data.said", loT.cError)
				ENDIF
			ENDIF
		CATCH TO loErr
			This.oHost.LogFault("data.ai: " + tcKind + " could not open the table: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message)
		FINALLY
			loT.Close()
		ENDTRY
		IF EMPTY(lcSource)
			RETURN .NULL.
		ENDIF
		IF EMPTY(lcCols) AND llNeedsText
			This.oHost.Notify(This.T("data.ai.classify.noColumn", lcName), This.oHost.TranslateEn("data.ai.classify.noColumn", lcName))
			RETURN .NULL.
		ENDIF
		loF = NEWOBJECT("DataAiClassifyForm", This.CodeFile(), "", This, lcSource, lcName, llDbf, lcCols, tcKind)
		loF.cKey = SYS(2015)
		This.oForms.Add(loF, loF.cKey)
		loF.Show()
		RETURN loF
	ENDPROC

	*-- Este .prg (NEWOBJECT de la ventana).
	PROCEDURE CodeFile
		LOCAL loP
		loP = This.Plugin()
		RETURN loP.CodeFile("DataAi.prg")
	ENDPROC

	*-- Los alias abiertos en la sesión de datos 1 que la ventana ofrece (todos, no
	*-- solo el seleccionado), en minúsculas y separados por comas, en el orden de sus áreas. Con tlText
	*-- (classify, extract, anonymize), solo los que tienen columnas de texto o memo.
	*-- Fuera los que abre FoxDock por un momento (FDD..., DataTable).
	PROCEDURE OpenAliases
		LPARAMETERS tlText
		LOCAL lnN, lnI, lcA, lcOut
		LOCAL ARRAY laU[1]
		*-- AUSED con la sesión 1; por el número de área, que no cambia.
		lnN = AUSED(laU, 1)
		IF lnN > 1
			=ASORT(laU, 2)
		ENDIF
		lcOut = ""
		FOR lnI = 1 TO lnN
			lcA = LOWER(laU[lnI, 1])
			IF LEFT(lcA, 3) == "fdd" OR (tlText AND EMPTY(This.TextColumns(lcA)))
				LOOP
			ENDIF
			lcOut = lcOut + IIF(EMPTY(lcOut), "", ",") + lcA
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- Las columnas de texto y memo de un alias de la sesión 1, separadas por comas.
	PROCEDURE TextColumns
		LPARAMETERS tcAlias
		LOCAL lnN, lnI, lcOut, lnDs
		LOCAL ARRAY laF[1]
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lcOut = ""
		lnN = AFIELDS(laF, tcAlias)
		FOR lnI = 1 TO lnN
			IF INLIST(laF[lnI, 2], "C", "V", "M")
				lcOut = lcOut + IIF(EMPTY(lcOut), "", ",") + LOWER(laF[lnI, 1])
			ENDIF
		ENDFOR
		SET DATASESSION TO (lnDs)
		RETURN lcOut
	ENDPROC

	*-- El destino que se propone: ai_<columna> recortado a seis en Classify, para
	*-- que <destino>_con y <destino>_rea quepan en diez (AIXL recorta los nombres
	*-- a diez y avisa); ai_<columna> a diez en Anonymize, que deja una sola
	*-- columna; y ax_<columna> a seis en Extract, que deja <destino>_<clave>
	*-- (ax_not_pri, ax_not_dep), recortado a diez como los demás. Con ai_, Extract
	*-- propondría el destino de Classify y lo pisaría sin avisar.
	PROCEDURE DefaultInto
		LPARAMETERS tcColumn, tcKind
		DO CASE
			CASE LOWER(EVL(tcKind, "classify")) == "anonymize"
				RETURN LEFT("ai_" + LOWER(ALLTRIM(tcColumn)), 10)
			CASE LOWER(EVL(tcKind, "classify")) == "extract"
				RETURN LEFT("ax_" + LOWER(ALLTRIM(tcColumn)), 6)
		ENDCASE
		RETURN LEFT("ai_" + LOWER(ALLTRIM(tcColumn)), 6)
	ENDPROC

	*-- Los campos de un alias, en minúscula y separados por comas.
	PROCEDURE FieldList
		LPARAMETERS tcAlias
		LOCAL lnN, lnI, lcOut
		LOCAL ARRAY laF[1]
		lcOut = ""
		IF EMPTY(tcAlias) OR !USED(tcAlias)
			RETURN ""
		ENDIF
		lnN = AFIELDS(laF, tcAlias)
		FOR lnI = 1 TO lnN
			lcOut = lcOut + IIF(lnI = 1, "", ",") + LOWER(laF[lnI, 1])
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- Los nombres que quedarán en el cursor (AIXL los recorta a diez), según
	*-- la operación: classify, <destino>, <destino>_confidence y _reason;
	*-- extract, <destino> y <destino>_<clave> de cada clave (sin esquema, las que
	*-- elija el modelo: "*"); anonymize, <destino>; filter, aixl_keep.
	PROCEDURE FinalNames
		LPARAMETERS tcInto, tcKind, tcSchema
		LOCAL lcI, lcOut, lnK
		lcI = LOWER(ALLTRIM(tcInto))
		DO CASE
			CASE LOWER(EVL(tcKind, "classify")) == "extract"
				lcOut = LEFT(lcI, 10)
				IF EMPTY(tcSchema)
					RETURN lcOut + ",*"
				ENDIF
				FOR lnK = 1 TO GETWORDCOUNT(tcSchema, ",")
					lcOut = lcOut + "," + LEFT(lcI + "_" + LOWER(ALLTRIM(GETWORDNUM(tcSchema, lnK, ","))), 10)
				ENDFOR
				RETURN lcOut
			CASE LOWER(EVL(tcKind, "classify")) == "anonymize"
				RETURN LEFT(lcI, 10)
			CASE LOWER(EVL(tcKind, "classify")) == "filter"
				RETURN "aixl_keep"
			CASE LOWER(EVL(tcKind, "classify")) == "ask"
				RETURN ""
		ENDCASE
		RETURN LEFT(lcI, 10) + "," + LEFT(lcI + "_confidence", 10) + "," + LEFT(lcI + "_reason", 10)
	ENDPROC

	*-- ¿Se recortan los nombres? (el destino de más de seis, o una clave larga).
	PROCEDURE NamesCut
		LPARAMETERS tcInto, tcKind, tcSchema
		LOCAL lnK
		IF LOWER(EVL(tcKind, "classify")) == "extract"
			FOR lnK = 1 TO GETWORDCOUNT(EVL(tcSchema, ""), ",")
				IF LEN(ALLTRIM(tcInto) + "_" + ALLTRIM(GETWORDNUM(tcSchema, lnK, ","))) > 10
					RETURN .T.
				ENDIF
			ENDFOR
			RETURN LEN(ALLTRIM(tcInto)) > 10
		ENDIF
		RETURN LEN(ALLTRIM(tcInto)) > IIF(LOWER(EVL(tcKind, "classify")) == "anonymize", 10, 6)
	ENDPROC

	*-- Dos nombres iguales después del recorte (extract: dos claves que a diez
	*-- coinciden). AIXL renombraría la segunda (ai_not_de2): la ventana se niega
	*-- antes de Run, para que el usuario vea los nombres que quedarán.
	PROCEDURE NamesClash
		LPARAMETERS tcNames
		LOCAL lnI, lcSeen, lcN
		lcSeen = ","
		FOR lnI = 1 TO GETWORDCOUNT(tcNames, ",")
			lcN = GETWORDNUM(tcNames, lnI, ",")
			IF lcN == "*"
				LOOP
			ENDIF
			IF "," + lcN + "," $ lcSeen
				RETURN lcN
			ENDIF
			lcSeen = lcSeen + lcN + ","
		ENDFOR
		RETURN ""
	ENDPROC

	*-- La frase del coste, leída del objeto vivo, justo antes de Run.
	PROCEDURE CostText
		LPARAMETERS tnRows, tcWhat, tcKind
		LOCAL lcP, lcT
		lcP = This.ProviderNow()
		IF LEFT(lcP, 4) == "mock"
			lcT = This.T("data.ai.classify.costMock")
		ELSE
			lcT = This.T("data.ai.classify.cost", tnRows, tcWhat, lcP + IIF(EMPTY(This.cModel), "", " (" + This.cModel + ")"))
		ENDIF
		*-- Ask: el aviso de que el modelo solo lee los primeros 4.000 caracteres (manual de AIXL, § 5).
		IF LOWER(EVL(tcKind, "")) == "ask"
			lcT = lcT + " " + This.T("data.ai.ask.only4000")
		ENDIF
		RETURN lcT
	ENDPROC

	PROCEDURE BusyText
		RETURN "a" + ICASE(This.cBusyKind == "extract", "n extraction", This.cBusyKind == "anonymize", "n anonymization", ;
			This.cBusyKind == "filter", " filter", This.cBusyKind == "ask", " question", " classification") + ;
			" is running on " + This.cBusyAlias + " (" + TRANSFORM(This.nDone) + " of " + ;
			TRANSFORM(This.nTotal) + " rows, block " + TRANSFORM(This.nBlock) + "/" + TRANSFORM(This.nBlocks) + ")"
	ENDPROC

	*-- Las filas visibles de un alias de la sesión 1 (filtro y SET DELETED, como
	*-- AIXL), sin mover el puntero.
	PROCEDURE VisibleRows
		LPARAMETERS tcAlias
		LOCAL lnDs, lnSel, lnRec, lnN
		lnDs = SET("DATASESSION")
		SET DATASESSION TO 1
		lnSel = SELECT(0)
		SELECT (tcAlias)
		lnRec = RECNO()
		COUNT TO lnN
		IF BETWEEN(lnRec, 1, RECCOUNT())
			GO lnRec
		ENDIF
		SELECT (lnSel)
		SET DATASESSION TO (lnDs)
		RETURN lnN
	ENDPROC

	*-- Classify: RunOp con cKind "classify".
	PROCEDURE Classify
		LPARAMETERS toP
		IF !PEMSTATUS(toP, "cKind", 5)
			ADDPROPERTY(toP, "cKind", "classify")
		ENDIF
		RETURN This.RunOp(toP)
	ENDPROC

	*-- Una operación, para la ventana y para la tool. toP: cKind (classify,
	*-- extract, anonymize, filter, ask), cTable, cColumn, cInto, cInstruction
	*-- (la instrucción; en filter, el prompt; en ask, la pregunta), cLabels (en
	*-- classify, las etiquetas; en extract, el esquema), cColumns (filter y ask:
	*-- las que ve el modelo), lNewCursor (filter), nBlock, lAgent, nLimit (la
	*-- tool: las filas que puede mandar). Devuelve un Empty: lOk, cCode,
	*-- cMessage, nRows, nFailed, nTokensIn, nTokensOut, nSeconds, cColumns,
	*-- cCopy, cWarnings, nErrors, cErrorsJson (las 20 primeras), lCancelled,
	*-- cWork, nVisible, cKind, cAnswer, lTruncated, nKept y cKept.
	PROCEDURE RunOp
		LPARAMETERS toP
		LOCAL lcBefore, lcAdded, lnF, lcF
		LOCAL loR, loT, lcWork, lcCol, lcInto, lnVisible, lcFilter, lcScript, lcEscape, lnT0, llOk, lnDs, loErr, lcWhat
		LOCAL lnBlock, lcCode, lcKind, lcCols, lcBad, lnI, lcNames, lcClash, lcNew, llText
		LOCAL ARRAY laF[1]
		loR = This.NewResult()
		lcKind = LOWER(EVL(IIF(PEMSTATUS(toP, "cKind", 5), toP.cKind, ""), "classify"))
		loR.cKind = lcKind
		IF This.lBusy
			RETURN This.Refuse(loR, "AI_BUSY", This.BusyText())
		ENDIF
		IF !This.Ensure()
			RETURN This.Refuse(loR, "AI_NOT_READY", This.HelpTextEn())
		ENDIF
		IF !This.IsConfigured()
			RETURN This.Refuse(loR, "NO_PROVIDER", This.oHost.TranslateEn("data.ai.needsProvider"))
		ENDIF
		lcCols = LOWER(CHRTRAN(IIF(PEMSTATUS(toP, "cColumns", 5), toP.cColumns, ""), " ", ""))
		lcEscape = ""
		lnDs = SET("DATASESSION")
		loT = CREATEOBJECT("DataTable")
		TRY
			IF !loT.Open(toP.cTable, .F.)
				This.Refuse(loR, "NO_TABLE", loT.cError)
			ELSE
				SET DATASESSION TO 1
				llText = INLIST(lcKind, "classify", "extract", "anonymize")
				lcCol = LOWER(ALLTRIM(toP.cColumn))
				lcInto = LOWER(ALLTRIM(EVL(toP.cInto, This.DefaultInto(lcCol, lcKind))))
				lcBad = ""
				FOR lnI = 1 TO GETWORDCOUNT(lcCols, ",")
					IF TYPE(loT.cAlias + "." + GETWORDNUM(lcCols, lnI, ",")) == "U"
						lcBad = lcBad + IIF(EMPTY(lcBad), "", ", ") + GETWORDNUM(lcCols, lnI, ",")
					ENDIF
				ENDFOR
				lcNames = This.FinalNames(lcInto, lcKind, IIF(lcKind == "extract", toP.cLabels, ""))
				lcClash = IIF(lcKind == "extract", This.NamesClash(lcNames), "")
				DO CASE
					CASE llText AND !("," + lcCol + "," $ "," + This.TextColumns(loT.cAlias) + ",")
						This.Refuse(loR, "NO_COLUMN", "'" + toP.cColumn + "' is not a text or memo column of " + loT.cName + ;
							" (text and memo columns: " + This.TextColumns(loT.cAlias) + ")")
					CASE !EMPTY(lcBad)
						This.Refuse(loR, "NO_COLUMN", loT.cName + " has no column " + lcBad)
					CASE !llText AND EMPTY(ALLTRIM(toP.cInstruction))
						This.Refuse(loR, "NO_PROMPT", IIF(lcKind == "ask", "Ask needs a question.", "Filter needs the prompt: which rows pass."))
					CASE !EMPTY(lcClash)
						This.Refuse(loR, "SCHEMA_CLASH", "Two keys of the schema give the same column at ten characters: " + lcClash + ;
							". Shorten them, or give a shorter destination.")
					OTHERWISE
						lnVisible = This.VisibleRows(loT.cAlias)
						loR.nVisible = lnVisible
						IF toP.lAgent AND lnVisible > toP.nLimit
							This.Refuse(loR, "TOO_MANY_ROWS", loT.cName + " has " + TRANSFORM(lnVisible) + " visible rows, and this call " + ;
								"may send " + TRANSFORM(toP.nLimit) + " at most (maxRows, and options.data.ai.agentMaxRows " + ;
								TRANSFORM(This.AgentMaxRows()) + " in config.json, which only the programmer raises). Filter " + ;
								"the table in the IDE (SET FILTER) or pass a smaller one.")
						ELSE
							*-- Solo lectura, o una tabla: una copia ai_<nombre> READWRITE con las filas visibles.
							*-- Ask no escribe nada: no necesita copia (AIXL_ASK lee un cursor de solo lectura).
							lcWork = loT.cAlias
							IF lcKind # "ask" AND This.NeedsCopy(loT)
								lcWork = This.CopyName(loT.cName)
								IF USED(lcWork)
									USE IN (lcWork)
								ENDIF
								lcFilter = FILTER(loT.cAlias)
								*-- Un SELECT * FROM t INTO CURSOR c sin más es un filtro sobre t
								*-- (un cursor «reempaquetado»), y otro SELECT sobre c da el error 1815.
								*-- Entonces la copia va fila a fila (CopyByRows), con el mismo FILTER().
								TRY
									IF EMPTY(lcFilter)
										SELECT * FROM (loT.cAlias) INTO CURSOR (lcWork) READWRITE
									ELSE
										SELECT * FROM (loT.cAlias) WHERE &lcFilter INTO CURSOR (lcWork) READWRITE
									ENDIF
								CATCH TO loErr WHEN loErr.ErrorNo = 1815
									This.CopyByRows(loT.cAlias, lcWork)
								ENDTRY
								loR.cCopy = lcWork
							ENDIF
							loR.cWork = LOWER(lcWork)
							loR.cColumns = lcNames
							lcScript = This.Script(lcKind, lcInto, lcCol, toP.cInstruction, toP.cLabels, lcCols)
							lnBlock = MIN(MAX(INT(EVL(toP.nBlock, This.BlockRows())), 1), AI_MAX_ROWS)
							lcWhat = loT.cName + IIF(llText, "." + lcCol, IIF(EMPTY(lcCols), "", "." + lcCols))
							lcNew = IIF(lcKind == "filter" AND PEMSTATUS(toP, "lNewCursor", 5) AND toP.lNewCursor, ;
								This.CopyName(loT.cName) + "_kept", "")
							This.oHost.Log("data.ai: " + lcKind + " " + lcWhat + IIF(EMPTY(loR.cCopy), "", " (on the copy " + lcWork + ")") + ;
								IIF(llText, " into " + lcInto, "") + ", " + TRANSFORM(lnVisible) + " rows" + ;
								IIF(lcKind == "ask", "", " by blocks of " + TRANSFORM(lnBlock)) + ;
								"; " + This.SessionText() + IIF(toP.lAgent, "; asked by the agent", ""))
							*-- El lote: ocupado, SET ESCAPE OFF (y repuesto en el FINALLY), el avance por FdAiProgress.
							lcBefore = "," + This.FieldList(lcWork) + ","
							lcEscape = SET("ESCAPE")
							SET ESCAPE OFF
							This.lBusy = .T.
							This.cBusyAlias = LOWER(lcWork)
							This.cBusyKind = lcKind
							This.lAgentRun = toP.lAgent
							This.lCancelled = .F.
							This.lStopAsked = .F.
							STORE 0 TO This.nDone, This.nBlock, This.nBlocks
							This.nTotal = lnVisible
							lnT0 = SECONDS()
							IF lcKind == "ask"
								*-- Una pregunta sobre el conjunto: sin bloques, sin Esc, sin avance (manual § 5).
								loR.cAnswer = AIXL_ASK(lcWork, toP.cInstruction, lcCols)
								llOk = !EMPTY(loR.cAnswer)
							ELSE
								llOk = AIXL_RUN_BATCH(lcWork, lcScript, lnBlock, "FdAiProgress()")
							ENDIF
							loR.nSeconds = ROUND(SECONDS() - lnT0, 1)
							*-- Las columnas que añadió, del cursor (sin esquema, las claves de Extraer
							*-- las elige el modelo); si no añadió ninguna (escribió encima), las previstas.
							lcAdded = ""
							FOR lnF = 1 TO GETWORDCOUNT(This.FieldList(lcWork), ",")
								lcF = GETWORDNUM(This.FieldList(lcWork), lnF, ",")
								IF !("," + lcF + "," $ lcBefore)
									lcAdded = lcAdded + IIF(EMPTY(lcAdded), "", ",") + lcF
								ENDIF
							ENDFOR
							IF !EMPTY(lcAdded)
								loR.cColumns = lcAdded
							ENDIF
							lcCode = AIXL_LAST_ERROR_CODE()
							loR.lOk = llOk
							loR.cCode = IIF(llOk, "", lcCode)
							loR.cMessage = IIF(llOk, "", AIXL_LAST_ERROR())
							loR.lCancelled = (lcCode == "RUN_CANCELLED")
							This.Results(loR, lcWhat, lcInto, lcNew)
						ENDIF
				ENDCASE
			ENDIF
		CATCH TO loErr
			This.Refuse(loR, "FAILED", PROPER(lcKind) + " failed: " + TRANSFORM(loErr.ErrorNo) + " " + loErr.Message)
			This.oHost.LogFault("data.ai: " + loR.cMessage)
		FINALLY
			*-- Todo vuelve también cuando AIXL o el código fallan a mitad.
			IF !EMPTY(lcEscape)
				SET ESCAPE &lcEscape
			ENDIF
			This.lBusy = .F.
			This.cBusyAlias = ""
			This.cBusyKind = ""
			This.lAgentRun = .F.
			This.oForm = .NULL.
			SET DATASESSION TO 1
			IF !toP.lAgent AND lcKind # "ask"
				DO CASE
					CASE !EMPTY(loR.cKept) AND USED(loR.cKept)
						This.Browse(loR.cKept)
					CASE !EMPTY(loR.cWork) AND USED(loR.cWork)
						This.Browse(loR.cWork)
				ENDCASE
			ENDIF
			loT.Close()
			SET DATASESSION TO (lnDs)
		ENDTRY
		RETURN loR
	ENDPROC

	*-- El script de cada operación, como lo arma aixl.prg (AIXL_CLASSIFY,
	*-- AIXL_EXTRACT, AIXL_ANONYMIZE, AIXL_FILTER) con sus mismas funciones.
	PROCEDURE Script
		LPARAMETERS tcKind, tcInto, tcCol, tcInstruction, tcLabels, tcCols
		LOCAL lcS
		DO CASE
			CASE tcKind == "filter"
				lcS = "AI_FILTER " + AIXL_STR(tcInstruction)
				IF !EMPTY(tcCols)
					lcS = lcS + " FROM (" + AIXL_LISTA_IDENT(tcCols) + ")"
				ENDIF
				RETURN lcS
			CASE tcKind == "ask"
				RETURN ""
		ENDCASE
		lcS = ICASE(tcKind == "extract", "AI_EXTRACT ", tcKind == "anonymize", "AI_ANONYMIZE ", "AI_CLASSIFY ") + ;
			AIXL_IDENT(tcInto) + " FROM " + AIXL_IDENT(tcCol)
		IF !EMPTY(tcInstruction)
			lcS = lcS + " TYPE " + AIXL_STR(tcInstruction)
		ENDIF
		IF !EMPTY(tcLabels)
			DO CASE
				CASE tcKind == "classify"
					lcS = lcS + " LABELS (" + AIXL_LISTA_STR(tcLabels) + ")"
				CASE tcKind == "extract"
					lcS = lcS + " SCHEMA (" + AIXL_LISTA_IDENT(tcLabels) + ")"
			ENDCASE
		ENDIF
		RETURN lcS
	ENDPROC

	PROTECTED PROCEDURE NewResult
		LOCAL loR
		loR = CREATEOBJECT("Empty")
		ADDPROPERTY(loR, "lOk", .F.)
		ADDPROPERTY(loR, "cCode", "")
		ADDPROPERTY(loR, "cMessage", "")
		ADDPROPERTY(loR, "lRefused", .F.)
		ADDPROPERTY(loR, "nVisible", 0)
		ADDPROPERTY(loR, "nRows", 0)
		ADDPROPERTY(loR, "nFailed", 0)
		ADDPROPERTY(loR, "nTokensIn", 0)
		ADDPROPERTY(loR, "nTokensOut", 0)
		ADDPROPERTY(loR, "nSeconds", 0)
		ADDPROPERTY(loR, "cColumns", "")
		ADDPROPERTY(loR, "cCopy", "")
		ADDPROPERTY(loR, "cWork", "")
		ADDPROPERTY(loR, "cWarnings", "")
		ADDPROPERTY(loR, "nErrors", 0)
		ADDPROPERTY(loR, "cErrorsJson", "[]")
		ADDPROPERTY(loR, "lCancelled", .F.)
		ADDPROPERTY(loR, "cKind", "classify")
		ADDPROPERTY(loR, "cAnswer", "")
		ADDPROPERTY(loR, "lTruncated", .F.)
		ADDPROPERTY(loR, "nKept", 0)
		ADDPROPERTY(loR, "cKept", "")
		RETURN loR
	ENDPROC

	*-- Una negativa antes de mandar nada: nada se ha pagado.
	PROTECTED PROCEDURE Refuse
		LPARAMETERS toR, tcCode, tcMessage
		toR.lOk = .F.
		toR.lRefused = .T.
		toR.cCode = tcCode
		toR.cMessage = tcMessage
		This.cLastNotice = This.T("data.ai.classify.failed", This.oHost.Quoted(tcCode + ": " + tcMessage))
		This.oHost.Notify(This.cLastNotice, "data.ai: " + tcCode + ": " + tcMessage)
		RETURN toR
	ENDPROC

	*-- Lo que dejó AIXL: AIXL_STATS, AIXL_WARNINGS, AIXL_ERRORS (ai_errors), la
	*-- barra de estado, el log y Last run.
	PROTECTED PROCEDURE Results
		LPARAMETERS toR, tcWhat, tcInto, tcNewCursor
		LOCAL lnErrs, lcList, lnK, loJ, loE
		LOCAL ARRAY laK[1]
		=AIXL_STATS("ai_stats")
		SELECT ai_stats
		toR.nRows = filas - fallidas
		toR.nFailed = fallidas
		toR.nTokensIn = tokens_in
		toR.nTokensOut = tokens_out
		USE IN ai_stats
		IF AIXL_WARNINGS("ai_warnings") > 0
			lcList = ""
			SELECT ai_warnings
			SCAN
				lcList = lcList + IIF(EMPTY(lcList), "", CHR(10)) + ALLTRIM(codigo) + ": " + ALLTRIM(mensaje)
			ENDSCAN
			toR.cWarnings = lcList
		ENDIF
		IF USED("ai_warnings")
			USE IN ai_warnings
		ENDIF
		*-- Ask, el aviso de los 4.000 caracteres; Filter, las que pasan (y el cursor nuevo).
		toR.lTruncated = "INPUT_TRUNCATED" $ toR.cWarnings
		IF toR.cKind == "filter" AND USED(toR.cWork) AND TYPE(toR.cWork + ".aixl_keep") == "L"
			SELECT COUNT(*) FROM (toR.cWork) WHERE NVL(aixl_keep, .F.) INTO ARRAY laK
			toR.nKept = laK[1]
			IF !EMPTY(tcNewCursor)
				IF USED(tcNewCursor)
					USE IN (tcNewCursor)
				ENDIF
				SELECT * FROM (toR.cWork) WHERE NVL(aixl_keep, .F.) INTO CURSOR (tcNewCursor) READWRITE
				toR.cKept = LOWER(tcNewCursor)
			ENDIF
		ENDIF
		lnErrs = AIXL_ERRORS("ai_errors")
		toR.nErrors = lnErrs
		IF lnErrs > 0
			loJ = This.oHost.oJson
			lcList = ""
			lnK = 0
			SELECT ai_errors
			SCAN WHILE lnK < 20
				lnK = lnK + 1
				loE = loJ.MakeObject()
				loJ.Put(loE, "code", ALLTRIM(codigo))
				loJ.Put(loE, "row", linea)
				loJ.Put(loE, "message", ALLTRIM(mensaje))
				lcList = lcList + IIF(lnK = 1, "", ",") + loJ.Stringify(loE)
			ENDSCAN
			toR.cErrorsJson = "[" + lcList + "]"
			GO TOP IN ai_errors
		ELSE
			USE IN ai_errors
		ENDIF
		DO CASE
			CASE toR.lCancelled
				This.cLastNotice = This.T("data.ai.classify.stopped", This.nBlock, This.nDone, MAX(This.nTotal - This.nDone, 0))
				This.oHost.Notify(This.cLastNotice, "data.ai: " + This.oHost.TranslateEn("data.ai.classify.stopped", This.nBlock, This.nDone, ;
					MAX(This.nTotal - This.nDone, 0)))
			CASE !toR.lOk AND toR.nRows = 0
				*-- Un .F. sin filas (NO_DATA, LICENSE_*, PROVIDER_*...): su código y su texto.
				This.cLastNotice = This.T("data.ai.classify.failed", This.oHost.Quoted(toR.cCode + ": " + toR.cMessage))
				This.oHost.Notify(This.cLastNotice, "data.ai: " + toR.cCode + ": " + toR.cMessage)
			CASE toR.cKind == "filter"
				This.cLastNotice = This.T("data.ai.filter.done", tcWhat, toR.nKept, toR.nRows + toR.nFailed, ;
					TRANSFORM(toR.nTokensIn) + " / " + TRANSFORM(toR.nTokensOut), TRANSFORM(toR.nSeconds))
				This.oHost.Notify(This.cLastNotice, "data.ai: " + This.oHost.TranslateEn("data.ai.filter.done", tcWhat, toR.nKept, ;
					toR.nRows + toR.nFailed, TRANSFORM(toR.nTokensIn) + " / " + TRANSFORM(toR.nTokensOut), TRANSFORM(toR.nSeconds)) + ;
					IIF(EMPTY(toR.cKept), "", "; the rows that pass are also in " + toR.cKept))
			CASE toR.cKind == "ask"
				This.cLastNotice = This.T("data.ai.ask.done", tcWhat, TRANSFORM(toR.nTokensIn) + " / " + TRANSFORM(toR.nTokensOut), ;
					TRANSFORM(toR.nSeconds)) + IIF(toR.lTruncated, " " + This.T("data.ai.ask.truncated"), "")
				This.oHost.Notify(This.cLastNotice, "data.ai: " + This.oHost.TranslateEn("data.ai.ask.done", tcWhat, ;
					TRANSFORM(toR.nTokensIn) + " / " + TRANSFORM(toR.nTokensOut), TRANSFORM(toR.nSeconds)) + ;
					IIF(toR.lTruncated, " " + This.oHost.TranslateEn("data.ai.ask.truncated"), ""))
				This.oHost.Log("data.ai: the answer: " + toR.cAnswer)
			OTHERWISE
				This.cLastNotice = This.T("data.ai." + toR.cKind + ".done", tcWhat, tcInto, toR.nRows, toR.nFailed, ;
					TRANSFORM(toR.nTokensIn) + " / " + TRANSFORM(toR.nTokensOut), TRANSFORM(toR.nSeconds))
				This.oHost.Notify(This.cLastNotice, "data.ai: " + This.oHost.TranslateEn("data.ai." + toR.cKind + ".done", tcWhat, tcInto, ;
					toR.nRows, toR.nFailed, TRANSFORM(toR.nTokensIn) + " / " + TRANSFORM(toR.nTokensOut), TRANSFORM(toR.nSeconds)) + ;
					IIF(toR.lOk, "", '; "' + toR.cCode + '" ' + toR.cMessage))
		ENDCASE
		*-- La barra de estado acaba con el resultado, no con el último
		*-- «N of M rows» del callback (Notify solo pone el WAIT WINDOW).
		_VFP.StatusBar = This.cLastNotice
		IF !EMPTY(toR.cWarnings)
			This.oHost.Log("data.ai: warnings: " + STRTRAN(toR.cWarnings, CHR(10), "; "))
		ENDIF
		IF toR.nErrors > 0
			This.oHost.Log("data.ai: " + TRANSFORM(toR.nErrors) + " row error(s), in the cursor ai_errors")
		ENDIF
		*-- Last run del submenú.
		This.oLastRun = CREATEOBJECT("Empty")
		ADDPROPERTY(This.oLastRun, "nRows", toR.nRows)
		ADDPROPERTY(This.oLastRun, "nTokens", toR.nTokensIn + toR.nTokensOut)
		ADDPROPERTY(This.oLastRun, "nSeconds", toR.nSeconds)
		This.oHost.RefreshMenu()
	ENDPROC

	*-- Con el _screen a la vista, BROWSE (como Connections); oculto, se apunta.
	PROCEDURE Browse
		LPARAMETERS tcAlias
		*-- Filter con la casilla: se enseña el cursor nuevo (las que pasan).
		This.cLastBrowse = LOWER(tcAlias)
		IF _screen.Visible
			SELECT (tcAlias)
			GO TOP
			BROWSE NOWAIT NOMODIFY NOAPPEND NODELETE NORMAL IN SCREEN
			IF USED("ai_errors") AND RECCOUNT("ai_errors") > 0
				SELECT ai_errors
				BROWSE NOWAIT NOMODIFY NOAPPEND NODELETE NORMAL IN SCREEN
			ENDIF
		ENDIF
	ENDPROC

	*-- ¿Se trabaja sobre una copia? Un cursor de solo lectura (ISREADONLY), y
	*-- toda tabla: la abierta por DataTable y la que el usuario tiene abierta,
	*-- aunque sea escribible (DBF() es su .dbf; el de un cursor es un .tmp):
	*-- nunca se escribe en una tabla del usuario.
	PROCEDURE NeedsCopy
		LPARAMETERS toT
		RETURN toT.lOpened OR ISREADONLY(toT.cAlias) OR UPPER(JUSTEXT(DBF(toT.cAlias))) == "DBF"
	ENDPROC

	*-- La copia de un cursor que no admite otro SELECT (error 1815): su
	*-- estructura sin reglas ni autoincrementos, y sus filas visibles (SCAN respeta
	*-- FILTER() y SET DELETED), una a una. El puntero del original vuelve a su sitio.
	PROCEDURE CopyByRows
		LPARAMETERS tcFrom, tcTo
		LOCAL lnN, lnI, lnK, lnRec, loRow
		LOCAL ARRAY laF[1]
		lnN = AFIELDS(laF, tcFrom)
		FOR lnI = 1 TO lnN
			FOR lnK = 7 TO 16
				laF[lnI, lnK] = ""
			ENDFOR
			laF[lnI, 17] = 0
			laF[lnI, 18] = 0
		ENDFOR
		lnRec = RECNO(tcFrom)
		CREATE CURSOR (tcTo) FROM ARRAY laF
		SELECT (tcFrom)
		SCAN
			SCATTER MEMO NAME loRow
			INSERT INTO (tcTo) FROM NAME loRow
		ENDSCAN
		IF BETWEEN(lnRec, 1, RECCOUNT(tcFrom))
			GO lnRec IN (tcFrom)
		ENDIF
		SELECT (tcTo)
		GO TOP
	ENDPROC

	*-- ai_<nombre>, con lo que no sea letra, dígito o _ cambiado por _.
	PROCEDURE CopyName
		LPARAMETERS tcName
		RETURN "ai_" + CHRTRAN(LOWER(tcName), CHRTRAN(LOWER(tcName), "abcdefghijklmnopqrstuvwxyz0123456789_", ""), REPLICATE("_", 64))
	ENDPROC

	*-- El alto que pide el texto de una etiqueta con WordWrap a un ancho (el suyo, si no se
	*-- da): DrawText con DT_CALCRECT, DT_WORDBREAK y DT_NOPREFIX en un DC de memoria, con su
	*-- letra. No pinta nada, y vale con la ventana oculta (AutoSize solo crece a la vista).
	PROCEDURE WrapHeight
		LPARAMETERS toL, tnWidth
		LOCAL lnDc, lnFont, lnOld, lcRect, lnH
		IF EMPTY(toL.Caption)
			RETURN 0
		ENDIF
		DECLARE INTEGER CreateCompatibleDC IN gdi32 AS FdAiCreateDC INTEGER hdc
		DECLARE INTEGER DeleteDC IN gdi32 AS FdAiDeleteDC INTEGER hdc
		DECLARE INTEGER GetDeviceCaps IN gdi32 AS FdAiCaps INTEGER hdc, INTEGER nIndex
		DECLARE INTEGER CreateFont IN gdi32 AS FdAiFont INTEGER nHeight, INTEGER nWidth, INTEGER nEsc, INTEGER nOrient, ;
			INTEGER nWeight, INTEGER nItalic, INTEGER nUnder, INTEGER nStrike, INTEGER nCharSet, INTEGER nOutPrec, ;
			INTEGER nClipPrec, INTEGER nQuality, INTEGER nPitch, STRING cFace
		DECLARE INTEGER SelectObject IN gdi32 AS FdAiSelect INTEGER hdc, INTEGER hObj
		DECLARE INTEGER DeleteObject IN gdi32 AS FdAiDeleteObj INTEGER hObj
		DECLARE INTEGER DrawText IN user32 AS FdAiDrawText INTEGER hdc, STRING cText, INTEGER nCount, STRING @cRect, INTEGER nFormat
		lnDc = FdAiCreateDC(0)
		lnFont = FdAiFont(-ROUND(toL.FontSize * FdAiCaps(lnDc, 90) / 72, 0), 0, 0, 0, IIF(toL.FontBold, 700, 400), ;
			IIF(toL.FontItalic, 1, 0), 0, 0, 1, 0, 0, 0, 0, toL.FontName)
		lnOld = FdAiSelect(lnDc, lnFont)
		lcRect = BINTOC(0, "4RS") + BINTOC(0, "4RS") + BINTOC(EVL(tnWidth, toL.Width), "4RS") + BINTOC(0, "4RS")
		lnH = FdAiDrawText(lnDc, toL.Caption, LEN(toL.Caption), @lcRect, 0x400 + 0x10 + 0x800)
		=FdAiSelect(lnDc, lnOld)
		=FdAiDeleteObj(lnFont)
		=FdAiDeleteDC(lnDc)
		RETURN lnH
	ENDPROC

	PROCEDURE BlockRows
		LOCAL lnB
		lnB = INT(VAL(TRANSFORM(This.oHost.Options.Get("data", "ai.blockRows", AI_BLOCK_ROWS))))
		RETURN IIF(BETWEEN(lnB, 1, AI_MAX_ROWS), lnB, AI_BLOCK_ROWS)
	ENDPROC

	PROCEDURE AgentMaxRows
		LOCAL lnB
		lnB = INT(VAL(TRANSFORM(This.oHost.Options.Get("data", "ai.agentMaxRows", AI_AGENT_MAX_ROWS))))
		RETURN IIF(lnB >= 1, lnB, AI_AGENT_MAX_ROWS)
	ENDPROC

	*-- El callback del lote (FdAiProgress, abajo): el avance a la barra de
	*-- estado y a la ventana, DOEVENTS, y Esc para al acabar el bloque.
	PROCEDURE Progress
		LPARAMETERS tnDone, tnTotal, tnBlock, tnBlocks
		LOCAL lcText, lnKey
		This.nDone = tnDone
		This.nTotal = tnTotal
		This.nBlock = tnBlock
		This.nBlocks = tnBlocks
		This.cEscapeInRun = SET("ESCAPE")
		lcText = This.T("data.ai.classify.progress", tnDone, tnTotal, tnBlock, tnBlocks)
		_VFP.StatusBar = lcText
		IF VARTYPE(This.oForm) == "O"
			This.oForm.lblState.Caption = lcText
		ENDIF
		DOEVENTS
		IF This.lAgentRun
			RETURN .T.
		ENDIF
		*-- El Esc llega por dos caminos: en el búfer de teclado (INKEY), o, si un
		*-- DOEVENTS lo reparte antes, a la ventana que tiene el foco, que lo apunta en lStopAsked.
		lnKey = INKEY()
		This.nLastKey = MAX(This.nLastKey, lnKey)
		IF lnKey = 27 OR This.lStopAsked
			This.lCancelled = .T.
			RETURN .F.
		ENDIF
		RETURN .T.
	ENDPROC
ENDDEFINE


*------------------------------------------------------------------
* El callback de AIXL_RUN_BATCH: una expresión que AIXL evalúa tras cada
* bloque, con nHechas, nTotal, nBloque y nBloques a la vista (PRIVATE de
* aixl.prg). Una función y no un método: VFP no encadena sobre lo que
* devuelve un método.
*------------------------------------------------------------------
FUNCTION FdAiProgress
	LOCAL loP, loM
	IF TYPE("_screen.oFoxDock") # "O"
		RETURN .T.
	ENDIF
	loP = _screen.oFoxDock.PluginById("data")
	IF ISNULL(loP)
		RETURN .T.
	ENDIF
	loM = loP.Module("ai")
	IF ISNULL(loM)
		RETURN .T.
	ENDIF
	RETURN loM.Progress(nHechas, nTotal, nBloque, nBloques)
ENDFUNC


*------------------------------------------------------------------
* Las ventanas de las operaciones (forma del host, modeless, en el _screen):
* una sola clase, que enseña los campos de su operación (cKind). Se llama
* DataAiClassifyForm porque nació con Classify; sirve a las cinco.
*   classify   columna, destino, instrucción, etiquetas, filas por bloque
*   extract    columna, destino, instrucción, esquema, filas por bloque
*   anonymize  columna, destino, instrucción (qué se quita), filas por bloque
*   filter     el prompt, las columnas que ve el modelo, la casilla del cursor
*              nuevo, filas por bloque
*   ask        la pregunta, las columnas que ve el modelo, y la respuesta en un
*              EditBox de solo lectura (sin bloques)
*------------------------------------------------------------------
DEFINE CLASS DataAiClassifyForm AS Form
	Width = 520
	Height = 400
	AutoCenter = .T.
	BorderStyle = 2
	MaxButton = .F.
	MinButton = .F.
	ShowWindow = 0
	WindowType = 0
	*-- El Esc del lote lo ve la ventana antes que sus controles (KeyPress).
	KeyPreview = .T.
	oModule = .NULL.
	cKey = ""
	cKind = "classify"
	cSource = ""      && el alias o el .dbf de la tabla de trabajo
	cTableName = ""
	lDbf = .F.
	oLastResult = .NULL.
	cDbf = ""         && el .dbf elegido con GETFILE, si se abrió uno (sigue en la lista)
	cDbfCols = ""     && sus columnas de texto (el .dbf no queda abierto)
	nRows = 0         && las filas que se enviarían, contadas al abrir la tabla (Cost)
	lCopy = .F.       && si se trabaja sobre una copia (solo lectura o .dbf)

	ADD OBJECT lblTable AS Label WITH Left = 10, Top = 14, AutoSize = .T., Caption = ""
	*-- Los alias abiertos (OpenAliases), y el .dbf elegido con GETFILE si se abrió uno.
	ADD OBJECT cboTable AS ComboBox WITH Left = 130, Top = 10, Width = 380, Height = 24, Style = 2
	ADD OBJECT lblColumn AS Label WITH Left = 10, Top = 44, AutoSize = .T., Caption = ""
	ADD OBJECT cboColumn AS ComboBox WITH Left = 130, Top = 40, Width = 200, Height = 24, Style = 2
	ADD OBJECT lblInto AS Label WITH Left = 10, Top = 74, AutoSize = .T., Caption = ""
	ADD OBJECT txtInto AS TextBox WITH Left = 130, Top = 70, Width = 120, Height = 24, MaxLength = 10, Value = ""
	ADD OBJECT lblNames AS Label WITH Left = 130, Top = 98, Width = 380, Height = 30, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	ADD OBJECT lblInstruction AS Label WITH Left = 10, Top = 132, AutoSize = .T., Caption = ""
	ADD OBJECT edtInstruction AS EditBox WITH Left = 130, Top = 130, Width = 380, Height = 60, Value = ""
	ADD OBJECT lblLabels AS Label WITH Left = 10, Top = 202, AutoSize = .T., Caption = ""
	ADD OBJECT txtLabels AS TextBox WITH Left = 130, Top = 198, Width = 200, Height = 24, MaxLength = 250, Value = ""
	ADD OBJECT lblLabelsHint AS Label WITH Left = 130, Top = 224, Width = 380, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	ADD OBJECT lblBlock AS Label WITH Left = 10, Top = 250, AutoSize = .T., Caption = ""
	ADD OBJECT spnBlock AS Spinner WITH Left = 130, Top = 246, Width = 80, Height = 24, Value = 200, ;
		SpinnerLowValue = 1, SpinnerHighValue = 1000, KeyboardLowValue = 1, KeyboardHighValue = 1000
	ADD OBJECT chkNew AS CheckBox WITH Left = 230, Top = 250, AutoSize = .T., Value = .F., Visible = .F.
	ADD OBJECT edtAnswer AS EditBox WITH Left = 130, Top = 246, Width = 380, Height = 56, ReadOnly = .T., Value = "", Visible = .F.
	ADD OBJECT lblCopy AS Label WITH Left = 10, Top = 278, Width = 500, Height = 30, WordWrap = .T., Caption = ""
	ADD OBJECT lblCost AS Label WITH Left = 10, Top = 308, Width = 500, Height = 30, WordWrap = .T., FontBold = .T., Caption = ""
	*-- Caption vacío: sin él, un Label enseña su nombre («Lblstate»).
	ADD OBJECT lblState AS Label WITH Left = 10, Top = 338, Width = 300, Height = 56, WordWrap = .T., Caption = ""
	ADD OBJECT cmdRun AS CommandButton WITH Left = 320, Top = 362, Width = 90, Height = 28, Default = .T.
	ADD OBJECT cmdClose AS CommandButton WITH Left = 420, Top = 362, Width = 90, Height = 28, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule, tcSource, tcName, tlDbf, tcCols, tcKind
		LOCAL lnI, llText
		This.oModule = toModule
		This.cKind = LOWER(EVL(tcKind, "classify"))
		This.cSource = tcSource
		This.cTableName = tcName
		This.lDbf = tlDbf
		This.Name = "FoxDockAi" + PROPER(This.cKind) + "_" + toModule.CopyName(tcName)
		llText = INLIST(This.cKind, "classify", "extract", "anonymize")
		IF tlDbf
			This.cDbf = tcSource
			This.cDbfCols = tcCols
		ENDIF
		This.FillTables()
		This.FillColumns(tcCols)
		This.spnBlock.Value = toModule.BlockRows()
		*-- Lo que enseña cada operación.
		This.lblColumn.Visible = llText
		This.cboColumn.Visible = llText
		This.lblInto.Visible = llText
		This.txtInto.Visible = llText
		This.lblLabels.Visible = !(This.cKind == "anonymize")
		This.txtLabels.Visible = !(This.cKind == "anonymize")
		This.lblLabelsHint.Visible = !(This.cKind == "anonymize")
		This.chkNew.Visible = (This.cKind == "filter")
		This.lblBlock.Visible = !(This.cKind == "ask")
		This.spnBlock.Visible = !(This.cKind == "ask")
		This.edtAnswer.Visible = (This.cKind == "ask")
		This.lblNames.Visible = !(This.cKind == "ask")
		*-- Ask no escribe nada: no hay copia que contar, y su respuesta va en ese sitio.
		This.lblCopy.Visible = !(This.cKind == "ask")
		This.Texts()
	ENDPROC

	PROCEDURE Destroy
		IF VARTYPE(This.oModule) == "O"
			This.oModule.FormGone(This.cKey)
			IF This.oModule.oForm == This
				This.oModule.oForm = .NULL.
			ENDIF
		ENDIF
		This.oModule = .NULL.
	ENDPROC

	*-- Los textos, en el idioma de FoxDock (también con la ventana abierta).
	*-- Lo común con las claves de Classify; lo de cada operación, con las suyas.
	PROCEDURE Texts
		LOCAL loM, lcK
		loM = This.oModule
		lcK = "data.ai." + This.cKind
		This.Caption = loM.T(lcK + ".caption", This.cTableName)
		This.lblTable.Caption = loM.T("data.ai.classify.table")
		This.lblColumn.Caption = loM.T("data.ai.classify.column")
		This.lblInto.Caption = loM.T("data.ai.classify.into")
		This.lblBlock.Caption = loM.T("data.ai.classify.block")
		This.cmdRun.Caption = loM.T("data.ai.classify.run")
		This.cmdClose.Caption = loM.T("data.ai.classify.close")
		DO CASE
			CASE This.cKind == "classify"
				This.lblInstruction.Caption = loM.T("data.ai.classify.instruction")
				This.lblLabels.Caption = loM.T("data.ai.classify.labels")
				This.lblLabelsHint.Caption = loM.T("data.ai.classify.labelsHint")
			CASE This.cKind == "extract"
				This.lblInstruction.Caption = loM.T("data.ai.classify.instruction")
				This.lblLabels.Caption = loM.T("data.ai.extract.schema")
				This.lblLabelsHint.Caption = loM.T("data.ai.extract.schemaHint")
			CASE This.cKind == "anonymize"
				This.lblInstruction.Caption = loM.T("data.ai.anonymize.instruction")
			CASE This.cKind == "filter"
				This.lblInstruction.Caption = loM.T("data.ai.filter.prompt")
				This.lblLabels.Caption = loM.T("data.ai.filter.columns")
				This.lblLabelsHint.Caption = loM.T("data.ai.filter.columnsHint")
				This.chkNew.Caption = loM.T("data.ai.filter.newCursor")
			CASE This.cKind == "ask"
				This.lblInstruction.Caption = loM.T("data.ai.ask.question")
				This.lblLabels.Caption = loM.T("data.ai.filter.columns")
				This.lblLabelsHint.Caption = loM.T("data.ai.filter.columnsHint")
				This.lblBlock.Caption = loM.T("data.ai.ask.answer")
				This.lblBlock.Visible = .T.
		ENDCASE
		This.Names()
		This.Cost()
		This.Arrange()
	ENDPROC

	*-- Las filas visibles, una debajo de otra, y la columna de los controles donde
	*-- la pida la etiqueta más larga en el idioma de ahora: así ninguna etiqueta
	*-- pisa su caja, y las filas ocultas no dejan hueco. Se rehace con el idioma
	*-- (Texts).
	PROCEDURE Arrange
		LOCAL lnX, lnY, lnI, loC, lnW, lnH
		lnX = 130
		FOR lnI = 1 TO This.ControlCount
			loC = This.Controls(lnI)
			IF loC.BaseClass == "Label" AND loC.AutoSize AND loC.Visible
				lnX = MAX(lnX, loC.Left + This.CaptionWidth(loC) + 14)
			ENDIF
		ENDFOR
		lnY = 10
		This.lblNames.Height = MAX(30, This.WrapHeight(This.lblNames))
		lnY = This.Row(This.lblTable, This.cboTable, .NULL., lnX, lnY)
		IF This.cboColumn.Visible
			lnY = This.Row(This.lblColumn, This.cboColumn, .NULL., lnX, lnY)
		ENDIF
		DO CASE
			CASE This.txtInto.Visible
				lnY = This.Row(This.lblInto, This.txtInto, This.lblNames, lnX, lnY)
			CASE This.lblNames.Visible
				*-- Filter: solo el aviso de la columna aixl_keep.
				This.lblNames.Move(lnX, lnY)
				lnY = lnY + This.lblNames.Height + 6
		ENDCASE
		lnY = This.Row(This.lblInstruction, This.edtInstruction, .NULL., lnX, lnY)
		IF This.txtLabels.Visible
			*-- La ayuda del esquema de Extraer es larga en los tres idiomas: va con el alto que pide su texto.
			This.lblLabelsHint.Height = MAX(17, This.WrapHeight(This.lblLabelsHint))
			lnY = This.Row(This.lblLabels, This.txtLabels, This.lblLabelsHint, lnX, lnY)
		ENDIF
		lnW = lnX + This.cboTable.Width + 10
		IF This.cKind == "ask"
			lnY = This.Row(This.lblBlock, This.edtAnswer, .NULL., lnX, lnY)
		ELSE
			lnY = This.Row(This.lblBlock, This.spnBlock, .NULL., lnX, lnY)
			This.chkNew.Move(lnX + This.spnBlock.Width + 16, This.spnBlock.Top + 3)
			IF This.chkNew.Visible
				lnW = MAX(lnW, This.chkNew.Left + This.CaptionWidth(This.chkNew) + 30)
			ENDIF
		ENDIF
		This.Width = lnW
		*-- Cada texto con WordWrap, con el alto que pide a su ancho (WrapHeight) y
		*-- nunca menos de 30 px: con un nombre de tabla largo, la línea de la copia
		*-- ocupa tres líneas, y en un alto fijo la frase del Esc no se vería.
		IF This.lblCopy.Visible
			lnH = MAX(30, This.WrapHeight(This.lblCopy, lnW - 20))
			This.lblCopy.Move(10, lnY, lnW - 20, lnH)
			lnY = lnY + lnH
		ENDIF
		lnH = MAX(30, This.WrapHeight(This.lblCost, lnW - 20))
		This.lblCost.Move(10, lnY, lnW - 20, lnH)
		lnY = lnY + lnH + 4
		lnH = MAX(46, This.WrapHeight(This.lblState, lnW - 220))
		This.lblState.Move(10, lnY, lnW - 220, lnH)
		This.cmdRun.Move(lnW - 200, lnY + 18)
		This.cmdClose.Move(lnW - 100, lnY + 18)
		This.Height = lnY + lnH + 8
	ENDPROC

	*-- El alto que pide el texto de una etiqueta con WordWrap: el del módulo.
	PROCEDURE WrapHeight
		LPARAMETERS toL, tnWidth
		RETURN This.oModule.WrapHeight(toL, tnWidth)
	ENDPROC

	*-- Una fila: la etiqueta a la izquierda, el control en la columna, y debajo su
	*-- aviso en gris si lo tiene. Devuelve dónde empieza la siguiente.
	PROCEDURE Row
		LPARAMETERS toLabel, toControl, toHint, tnX, tnY
		toControl.Move(tnX, tnY)
		toLabel.Move(10, tnY + 4)
		tnY = tnY + toControl.Height
		IF !ISNULL(toHint) AND toHint.Visible
			toHint.Move(tnX, tnY + 2)
			tnY = toHint.Top + toHint.Height
		ENDIF
		RETURN tnY + 8
	ENDPROC

	*-- Lo que pinta el texto de una etiqueta o una casilla: TXTWIDTH por
	*-- FONTMETRIC(6), con su letra y sin el «\<» (el Width de un AutoSize no
	*-- está al día antes de pintarse).
	PROCEDURE CaptionWidth
		LPARAMETERS toC
		LOCAL lcStyle
		lcStyle = EVL(IIF(toC.FontBold, "B", "") + IIF(toC.FontItalic, "I", ""), "N")
		RETURN CEILING(TXTWIDTH(STRTRAN(toC.Caption, "\<", ""), toC.FontName, toC.FontSize, lcStyle) * ;
			FONTMETRIC(6, toC.FontName, toC.FontSize, lcStyle))
	ENDPROC

	*-- Los nombres finales, en gris, el aviso si se recortan, y el choque.
	PROCEDURE Names
		LOCAL loM, lcN, lcClash, lcSchema, lcExists
		loM = This.oModule
		lcSchema = IIF(This.cKind == "extract", ALLTRIM(This.txtLabels.Value), "")
		lcN = loM.FinalNames(This.txtInto.Value, This.cKind, lcSchema)
		DO CASE
			CASE This.cKind == "classify"
				This.lblNames.Caption = loM.T("data.ai.classify.names", GETWORDNUM(lcN, 1, ","), GETWORDNUM(lcN, 2, ","), ;
					GETWORDNUM(lcN, 3, ",")) + IIF(loM.NamesCut(This.txtInto.Value), loM.T("data.ai.classify.namesCut"), "")
			CASE This.cKind == "extract"
				lcClash = loM.NamesClash(lcN)
				This.lblNames.Caption = IIF(!EMPTY(lcClash), loM.T("data.ai.extract.clash", lcClash), ;
					IIF(RIGHT(lcN, 2) == ",*", loM.T("data.ai.extract.namesFree", LEFT(lcN, LEN(lcN) - 2)), ;
					loM.T("data.ai.extract.names", STRTRAN(lcN, ",", ", "))) + ;
					IIF(loM.NamesCut(This.txtInto.Value, "extract", lcSchema), loM.T("data.ai.classify.namesCut"), ""))
			CASE This.cKind == "anonymize"
				This.lblNames.Caption = loM.T("data.ai.anonymize.names", lcN)
			CASE This.cKind == "filter"
				This.lblNames.Caption = loM.T("data.ai.filter.names")
		ENDCASE
		*-- Si alguna de esas columnas ya está en la tabla, Ejecutar
		*-- escribe encima: se dice antes.
		lcExists = This.Existing(lcN)
		IF !EMPTY(lcExists)
			This.lblNames.Caption = This.lblNames.Caption + loM.T("data.ai.classify.exists", lcExists, This.cTableName)
		ENDIF
	ENDPROC

	*-- De las columnas que va a dejar, las que ya tiene la tabla de trabajo (abierta en la
	*-- sesión 1; un .dbf elegido con GETFILE no está abierto y no se mira).
	PROCEDURE Existing
		LPARAMETERS tcNames
		LOCAL lnI, lcN, lcOut, lcHave
		lcOut = ""
		IF This.lDbf OR EMPTY(tcNames) OR !USED(This.cSource)
			RETURN ""
		ENDIF
		lcHave = "," + This.oModule.FieldList(This.cSource) + ","
		FOR lnI = 1 TO GETWORDCOUNT(tcNames, ",")
			lcN = GETWORDNUM(tcNames, lnI, ",")
			IF !(lcN == "*") AND "," + lcN + "," $ lcHave
				lcOut = lcOut + IIF(EMPTY(lcOut), "", ", ") + lcN
			ENDIF
		ENDFOR
		RETURN lcOut
	ENDPROC

	*-- La línea de la copia y la frase del coste, del objeto vivo: se rehacen
	*-- justo antes de Run. Con tlKeep (una tecla en la caja de las columnas), con
	*-- las filas ya contadas: abrir y cerrar la tabla en cada tecla devuelve el
	*-- cursor de la caja al principio, y «ID» se escribiría «DI».
	PROCEDURE Cost
		LPARAMETERS tlKeep
		LOCAL loM, loT, lnN, lcWhat, llRo, lcWork, lcCols
		loM = This.oModule
		IF !tlKeep
			loT = CREATEOBJECT("DataTable")
			lnN = 0
			llRo = This.lDbf
			IF loT.Open(This.cSource, .F.)
				lnN = loM.VisibleRows(loT.cAlias)
				llRo = loM.NeedsCopy(loT)
			ENDIF
			loT.Close()
			This.nRows = lnN
			This.lCopy = llRo
		ENDIF
		lnN = This.nRows
		llRo = This.lCopy
		*-- Ask no escribe nada: sin copia.
		llRo = llRo AND !(This.cKind == "ask")
		lcWork = loM.CopyName(This.cTableName)
		lcCols = CHRTRAN(ALLTRIM(This.txtLabels.Value), " ", "")
		DO CASE
			CASE INLIST(This.cKind, "filter", "ask")
				lcWhat = IIF(llRo, lcWork, This.cTableName) + IIF(EMPTY(lcCols), " " + loM.T("data.ai.filter.wholeRow"), "." + lcCols)
			OTHERWISE
				lcWhat = IIF(llRo, lcWork, This.cTableName) + "." + This.cboColumn.Value
		ENDCASE
		This.lblCopy.Caption = IIF(llRo, loM.T("data.ai.classify.copy", This.cTableName, lcWork), "") + ;
			IIF(This.cKind == "ask", "", IIF(llRo, " ", "") + loM.T("data.ai.classify.esc"))
		This.lblCost.Caption = loM.CostText(lnN, lcWhat, This.cKind)
		IF This.lblCopy.Visible AND This.lblCopy.Height # MAX(30, This.WrapHeight(This.lblCopy)) OR ;
			This.lblCost.Height # MAX(30, This.WrapHeight(This.lblCost))
			This.Arrange()
		ENDIF
	ENDPROC

	*-- Durante el lote, Esc no cierra la ventana (Close es Cancel): pide parar al acabar el bloque.
	PROCEDURE KeyPress
		LPARAMETERS nKeyCode, nShiftAltCtrl
		IF nKeyCode = 27 AND VARTYPE(This.oModule) == "O" AND This.oModule.lBusy
			This.oModule.lStopAsked = .T.
			NODEFAULT
		ENDIF
	ENDPROC

	*-- La lista de tablas: los alias abiertos (y el .dbf, si se eligió uno), con
	*-- la de ahora puesta.
	PROCEDURE FillTables
		LOCAL lcList, lnI, lcA
		lcList = This.oModule.OpenAliases(INLIST(This.cKind, "classify", "extract", "anonymize"))
		This.cboTable.Clear()
		IF !EMPTY(This.cDbf)
			This.cboTable.AddItem(This.cDbf)
		ENDIF
		FOR lnI = 1 TO GETWORDCOUNT(lcList, ",")
			This.cboTable.AddItem(GETWORDNUM(lcList, lnI, ","))
		ENDFOR
		*-- La de ahora, aunque no esté en la lista (sin columnas de texto, la ventana no se abre).
		lcA = IIF(This.lDbf, This.cSource, LOWER(This.cSource))
		FOR lnI = 1 TO This.cboTable.ListCount
			IF This.cboTable.List(lnI) == lcA
				This.cboTable.ListIndex = lnI
				RETURN
			ENDIF
		ENDFOR
		This.cboTable.AddItem(lcA, 1)
		This.cboTable.ListIndex = 1
	ENDPROC

	*-- Las columnas de texto de la tabla de ahora, la primera puesta, y el destino.
	PROCEDURE FillColumns
		LPARAMETERS tcCols
		LOCAL lnI
		This.cboColumn.Clear()
		FOR lnI = 1 TO GETWORDCOUNT(tcCols, ",")
			This.cboColumn.AddItem(GETWORDNUM(tcCols, lnI, ","))
		ENDFOR
		IF This.cboColumn.ListCount > 0
			This.cboColumn.ListIndex = 1
		ENDIF
		This.txtInto.Value = This.oModule.DefaultInto(This.cboColumn.Value, This.cKind)
	ENDPROC

	*-- Otra tabla: su nombre, sus columnas, el título, los nombres y el coste.
	PROCEDURE UseTable
		LPARAMETERS tcItem
		LOCAL loM
		loM = This.oModule
		IF !EMPTY(This.cDbf) AND tcItem == This.cDbf
			This.cSource = This.cDbf
			This.cTableName = LOWER(JUSTSTEM(This.cDbf))
			This.lDbf = .T.
			This.FillColumns(This.cDbfCols)
		ELSE
			This.cSource = UPPER(tcItem)
			This.cTableName = LOWER(tcItem)
			This.lDbf = .F.
			This.FillColumns(loM.TextColumns(tcItem))
		ENDIF
		This.lblState.Caption = ""
		This.Texts()
	ENDPROC

	PROCEDURE cboTable.InteractiveChange
		Thisform.UseTable(This.Value)
	ENDPROC

	PROCEDURE cboColumn.InteractiveChange
		Thisform.txtInto.Value = Thisform.oModule.DefaultInto(This.Value, Thisform.cKind)
		Thisform.Names()
		Thisform.Cost()
	ENDPROC

	PROCEDURE txtInto.InteractiveChange
		Thisform.Names()
	ENDPROC

	PROCEDURE txtLabels.InteractiveChange
		Thisform.Names()
		IF INLIST(Thisform.cKind, "filter", "ask")
			Thisform.Cost(.T.)
		ENDIF
	ENDPROC

	PROCEDURE cmdRun.Click
		LOCAL loM, loP, loR, lcTalk, llCols
		lcTalk = SET("TALK")
		SET TALK OFF
		loM = Thisform.oModule
		Thisform.Names()
		Thisform.Cost()
		llCols = INLIST(Thisform.cKind, "filter", "ask")
		loP = CREATEOBJECT("Empty")
		ADDPROPERTY(loP, "cKind", Thisform.cKind)
		ADDPROPERTY(loP, "cTable", Thisform.cSource)
		ADDPROPERTY(loP, "cColumn", IIF(llCols, "", Thisform.cboColumn.Value))
		ADDPROPERTY(loP, "cInto", IIF(llCols, "", ALLTRIM(Thisform.txtInto.Value)))
		ADDPROPERTY(loP, "cInstruction", ALLTRIM(Thisform.edtInstruction.Value))
		ADDPROPERTY(loP, "cLabels", IIF(llCols, "", ALLTRIM(Thisform.txtLabels.Value)))
		ADDPROPERTY(loP, "cColumns", IIF(llCols, ALLTRIM(Thisform.txtLabels.Value), ""))
		ADDPROPERTY(loP, "lNewCursor", Thisform.chkNew.Value)
		ADDPROPERTY(loP, "nBlock", Thisform.spnBlock.Value)
		ADDPROPERTY(loP, "lAgent", .F.)
		ADDPROPERTY(loP, "nLimit", 0)
		loM.oForm = Thisform
		This.Enabled = .F.
		Thisform.cmdClose.Enabled = .F.
		loR = loM.RunOp(loP)
		Thisform.cmdClose.Enabled = .T.
		This.Enabled = .T.
		Thisform.oLastResult = loR
		Thisform.lblState.Caption = loM.cLastNotice
		IF Thisform.cKind == "ask"
			Thisform.edtAnswer.Value = loR.cAnswer
		ENDIF
		Thisform.Cost()
		Thisform.Arrange()
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC
ENDDEFINE



*------------------------------------------------------------------
* Manage providers...: la lista de proveedores de IA, con
* Nuevo, Guardar, Borrar (dos pulsaciones: sin diálogo) y Use this one; y la
* licencia de AIXL, una para todos. Modeless, en el _screen. La clave guardada
* no se enseña nunca: la ventana dice cuánto mide, y vacía se conserva; con la
* variable de entorno, si este VFP la ve y cuánto mide lo que tiene.
*------------------------------------------------------------------
DEFINE CLASS DataAiProvidersForm AS Form
	Width = 620
	Height = 490
	AutoCenter = .T.
	BorderStyle = 2
	MaxButton = .F.
	MinButton = .F.
	ShowWindow = 0
	WindowType = 0
	Name = "FoxDockAiProviders"
	oModule = .NULL.
	cKey = ""
	cId = ""           && el de la lista que se está viendo ("" = uno nuevo)
	cDeleteAsked = ""  && Borrar, la primera pulsación
	oIds = .NULL.      && los ids, en el orden de la lista
	*-- Los probados desde AIXL primero (su manual, § 4.1); los otros los acepta su motor.
	cProviders = "deepseek,openai,anthropic,gemini,groq,monica"

	ADD OBJECT lstProviders AS ListBox WITH Left = 10, Top = 10, Width = 200, Height = 322
	ADD OBJECT cmdNew AS CommandButton WITH Left = 10, Top = 340, Width = 96, Height = 26
	ADD OBJECT cmdDelete AS CommandButton WITH Left = 114, Top = 340, Width = 96, Height = 26
	ADD OBJECT lblName AS Label WITH Left = 225, Top = 14, AutoSize = .T., Caption = ""
	ADD OBJECT txtName AS TextBox WITH Left = 330, Top = 10, Width = 280, Height = 24, MaxLength = 40, Value = ""
	ADD OBJECT lblProvider AS Label WITH Left = 225, Top = 44, AutoSize = .T., Caption = ""
	ADD OBJECT cboProvider AS ComboBox WITH Left = 330, Top = 40, Width = 180, Height = 24, Style = 2
	ADD OBJECT lblProviderHint AS Label WITH Left = 330, Top = 66, Width = 280, Height = 30, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	ADD OBJECT lblModel AS Label WITH Left = 225, Top = 104, AutoSize = .T., Caption = ""
	*-- Style 0: la lista del proveedor, y se puede escribir otro (se lee DisplayValue).
	ADD OBJECT cboModel AS ComboBox WITH Left = 330, Top = 100, Width = 180, Height = 24, Style = 0
	ADD OBJECT lblModelHint AS Label WITH Left = 330, Top = 126, Width = 280, Height = 30, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	ADD OBJECT lblKeySource AS Label WITH Left = 225, Top = 164, AutoSize = .T., Caption = ""
	ADD OBJECT optKeySource AS OptionGroup WITH Left = 326, Top = 158, Width = 284, Height = 46, ButtonCount = 2, BorderStyle = 0, Value = 1
	ADD OBJECT lblKey AS Label WITH Left = 225, Top = 214, AutoSize = .T., Caption = ""
	ADD OBJECT txtKey AS TextBox WITH Left = 330, Top = 210, Width = 280, Height = 24, Value = ""
	ADD OBJECT lblKeyHint AS Label WITH Left = 330, Top = 236, Width = 280, Height = 30, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	ADD OBJECT lblEndpoint AS Label WITH Left = 225, Top = 274, AutoSize = .T., Caption = ""
	ADD OBJECT txtEndpoint AS TextBox WITH Left = 330, Top = 270, Width = 280, Height = 24, Value = ""
	ADD OBJECT lblEndpointHint AS Label WITH Left = 330, Top = 296, Width = 280, Height = 44, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	ADD OBJECT cmdSave AS CommandButton WITH Left = 330, Top = 344, Width = 100, Height = 26, Default = .T.
	ADD OBJECT cmdUse AS CommandButton WITH Left = 440, Top = 344, Width = 170, Height = 26
	ADD OBJECT lblLicense AS Label WITH Left = 10, Top = 388, AutoSize = .T., Caption = ""
	ADD OBJECT txtLicense AS TextBox WITH Left = 130, Top = 384, Width = 444, Height = 24, Value = ""
	ADD OBJECT cmdLicense AS CommandButton WITH Left = 580, Top = 384, Width = 30, Height = 24, Caption = "..."
	ADD OBJECT lblLicenseHint AS Label WITH Left = 130, Top = 410, Width = 480, Height = 16, WordWrap = .T., ForeColor = RGB(110, 110, 110), Caption = ""
	*-- Caption vacío: sin él, un Label enseña su nombre («Lblstate»).
	ADD OBJECT lblState AS Label WITH Left = 10, Top = 436, Width = 490, Height = 46, WordWrap = .T., Caption = ""
	ADD OBJECT cmdClose AS CommandButton WITH Left = 520, Top = 454, Width = 90, Height = 26, Cancel = .T.

	PROCEDURE Init
		LPARAMETERS toModule
		LOCAL lnI
		This.oModule = toModule
		This.oIds = CREATEOBJECT("Collection")
		FOR lnI = 1 TO GETWORDCOUNT(This.cProviders, ",")
			This.cboProvider.AddItem(GETWORDNUM(This.cProviders, lnI, ","))
		ENDFOR
		FOR lnI = 1 TO 2
			This.optKeySource.Buttons(lnI).Left = 4
			This.optKeySource.Buttons(lnI).Top = 2 + (lnI - 1) * 22
			This.optKeySource.Buttons(lnI).Width = 276
			This.optKeySource.Buttons(lnI).AutoSize = .F.
		ENDFOR
		This.Texts()
		This.FillList(toModule.ActiveId())
		This.txtLicense.Value = toModule.LicenseFile()
	ENDPROC

	PROCEDURE Destroy
		IF VARTYPE(This.oModule) == "O"
			This.oModule.FormGone(This.cKey)
		ENDIF
		This.oModule = .NULL.
	ENDPROC

	*-- La lista, con «(en uso)» en el que lo está; y el de tcSelect a la vista
	*-- (vacío: el primero, y sin ninguno, uno nuevo).
	PROCEDURE FillList
		LPARAMETERS tcSelect
		LOCAL loM, lnI, loE, lnPick
		loM = This.oModule
		This.lstProviders.Clear()
		This.oIds = CREATEOBJECT("Collection")
		lnPick = 0
		FOR lnI = 1 TO loM.oProviders.Count
			loE = loM.oProviders.Item(lnI)
			This.lstProviders.AddItem(loE.cName + IIF(loE.cId == loM.ActiveId(), " " + loM.T("data.ai.providers.inUse"), ""))
			This.oIds.Add(loE.cId)
			IF loE.cId == tcSelect
				lnPick = lnI
			ENDIF
		ENDFOR
		IF lnPick = 0 AND This.oIds.Count > 0
			lnPick = 1
		ENDIF
		This.lstProviders.ListIndex = lnPick
		IF lnPick = 0
			This.ShowEntry("")
		ELSE
			This.ShowEntry(This.oIds.Item(lnPick))
		ENDIF
	ENDPROC

	*-- Uno de la lista en los campos ("" = uno nuevo, vacío).
	PROCEDURE ShowEntry
		LPARAMETERS tcId
		LOCAL loM, loE, lnI, lcVar
		loM = This.oModule
		This.cId = tcId
		This.cDeleteAsked = ""
		IF EMPTY(tcId)
			This.txtName.Value = ""
			This.cboProvider.ListIndex = 1
			This.FillModels()
			This.optKeySource.Value = 1
			This.txtEndpoint.Value = ""
		ELSE
			loE = loM.oProviders.Item(tcId)
			This.txtName.Value = loE.cName
			IF !("," + loE.cProvider + "," $ "," + This.cProviders + ",")
				This.cboProvider.AddItem(loE.cProvider)
			ENDIF
			FOR lnI = 1 TO This.cboProvider.ListCount
				IF This.cboProvider.List(lnI) == loE.cProvider
					This.cboProvider.ListIndex = lnI
				ENDIF
			ENDFOR
			This.FillModels()
			IF !EMPTY(loE.cModel)
				This.cboModel.DisplayValue = loE.cModel
			ENDIF
			This.optKeySource.Value = IIF(loE.cKeySource == "environment", 2, 1)
			This.txtEndpoint.Value = loE.cEndpoint
		ENDIF
		lcVar = ""
		IF !EMPTY(tcId) AND This.optKeySource.Value = 2
			lcVar = loE.cKeyVariable
		ENDIF
		This.KeyFields(lcVar)
		This.cmdDelete.Enabled = !EMPTY(tcId)
		This.cmdUse.Enabled = !EMPTY(tcId) AND !(tcId == loM.ActiveId())
	ENDPROC

	*-- El campo de la clave según de dónde sale: la clave (con asteriscos) o el
	*-- nombre de la variable; y su línea gris.
	PROCEDURE KeyFields
		LPARAMETERS tcVariable
		LOCAL loM, loE, lnLen, lcVar
		loM = This.oModule
		*-- Borrar rehace el menú, el menú vuelve a poner los textos de las ventanas,
		*-- y cId puede ser aún el del borrado: por eso se mira si sigue en la lista.
		loE = IIF(EMPTY(This.cId) OR loM.oProviders.GetKey(This.cId) = 0, .NULL., loM.oProviders.Item(This.cId))
		IF This.optKeySource.Value = 2
			This.lblKey.Caption = loM.T("data.ai.providers.variable")
			This.txtKey.PasswordChar = ""
			lcVar = EVL(tcVariable, "")
			This.txtKey.Value = lcVar
			This.VariableHint()
		ELSE
			This.lblKey.Caption = loM.T("data.ai.providers.key")
			This.txtKey.PasswordChar = "*"
			This.txtKey.Value = ""
			lnLen = 0
			IF !ISNULL(loE) AND loE.cKeySource == "windows"
				lnLen = loM.KeyLength(loE)
			ENDIF
			This.lblKeyHint.Caption = IIF(lnLen > 0, loM.T("data.ai.providers.keySaved", lnLen), loM.T("data.ai.providers.keyNew"))
		ENDIF
		This.Arrange()
	ENDPROC

	*-- Con la variable: si este VFP la ve (y cuánto mide lo que tiene), al teclear.
	PROCEDURE VariableHint
		LOCAL loM, lcVar, lnLen
		loM = This.oModule
		lcVar = UPPER(ALLTRIM(This.txtKey.Value))
		lnLen = LEN(loM.EnvValue(lcVar))
		*-- Vacía: qué va ahí, sin ningún nombre de ejemplo.
		This.lblKeyHint.Caption = ICASE(EMPTY(lcVar), loM.T("data.ai.providers.variableHint"), ;
			lnLen > 0, loM.T("data.ai.providers.varFound", lnLen), loM.T("data.ai.providers.varMissing", lcVar))
		This.Arrange()
	ENDPROC

	*-- Los modelos del proveedor elegido, y el primero puesto.
	PROCEDURE FillModels
		LOCAL lcModels, lnI
		lcModels = This.oModule.ModelsFor(This.cboProvider.Value)
		This.cboModel.Clear()
		FOR lnI = 1 TO GETWORDCOUNT(lcModels, ",")
			This.cboModel.AddItem(GETWORDNUM(lcModels, lnI, ","))
		ENDFOR
		This.cboModel.DisplayValue = GETWORDNUM(lcModels, 1, ",")
	ENDPROC

	*-- Los textos, en el idioma de FoxDock (también con la ventana abierta: Retext).
	PROCEDURE Texts
		LOCAL loM
		loM = This.oModule
		This.Caption = loM.T("data.ai.providers.caption")
		This.cmdNew.Caption = loM.T("data.ai.providers.new")
		This.cmdDelete.Caption = loM.T("data.ai.providers.delete")
		This.lblName.Caption = loM.T("data.ai.providers.name")
		This.lblProvider.Caption = loM.T("data.ai.settings.provider")
		This.lblProviderHint.Caption = loM.T("data.ai.settings.providerHint")
		This.lblModel.Caption = loM.T("data.ai.settings.model")
		This.lblModelHint.Caption = loM.T("data.ai.settings.modelHint")
		This.lblKeySource.Caption = loM.T("data.ai.providers.keySource")
		This.optKeySource.Buttons(1).Caption = loM.T("data.ai.providers.keyWindows")
		This.optKeySource.Buttons(2).Caption = loM.T("data.ai.providers.keyEnvironment")
		This.lblEndpoint.Caption = loM.T("data.ai.settings.endpoint")
		This.lblEndpointHint.Caption = loM.T("data.ai.settings.endpointHint")
		This.cmdSave.Caption = loM.T("data.ai.settings.save")
		This.cmdUse.Caption = loM.T("data.ai.providers.use")
		This.lblLicense.Caption = loM.T("data.ai.settings.license")
		This.lblLicenseHint.Caption = loM.T("data.ai.providers.licenseHint")
		This.cmdClose.Caption = loM.T("data.ai.classify.close")
		IF !EMPTY(This.cId) OR This.lstProviders.ListCount > 0
			This.KeyFields(IIF(This.optKeySource.Value = 2, ALLTRIM(This.txtKey.Value), ""))
		ENDIF
		This.Arrange()
	ENDPROC

	*-- Las filas, una debajo de otra, y cada ayuda en gris con el alto que pide
	*-- su texto a su ancho (WrapHeight del módulo): con un alto fijo, alguna se
	*-- cortaría en algún idioma. Se rehace con el idioma (Texts) y cuando cambia
	*-- una ayuda (KeyFields, VariableHint).
	PROCEDURE Arrange
		LOCAL lnY, lnH
		lnY = 10
		lnY = This.Row(This.lblName, This.txtName, .NULL., lnY)
		lnY = This.Row(This.lblProvider, This.cboProvider, This.lblProviderHint, lnY)
		lnY = This.Row(This.lblModel, This.cboModel, This.lblModelHint, lnY)
		lnY = This.Row(This.lblKeySource, This.optKeySource, .NULL., lnY)
		lnY = This.Row(This.lblKey, This.txtKey, This.lblKeyHint, lnY)
		lnY = This.Row(This.lblEndpoint, This.txtEndpoint, This.lblEndpointHint, lnY)
		This.cmdSave.Top = lnY
		This.cmdUse.Top = lnY
		This.cmdNew.Top = lnY
		This.cmdDelete.Top = lnY
		This.lstProviders.Height = lnY - 8 - This.lstProviders.Top
		lnY = lnY + This.cmdSave.Height + 14
		This.lblLicense.Top = lnY + 4
		This.txtLicense.Top = lnY
		This.cmdLicense.Top = lnY
		lnY = lnY + This.txtLicense.Height + 2
		This.lblLicenseHint.Top = lnY
		This.lblLicenseHint.Height = MAX(16, This.oModule.WrapHeight(This.lblLicenseHint))
		lnY = lnY + This.lblLicenseHint.Height + 10
		lnH = MAX(46, This.oModule.WrapHeight(This.lblState))
		This.lblState.Move(This.lblState.Left, lnY, This.lblState.Width, lnH)
		This.cmdClose.Top = lnY + 18
		This.Height = lnY + lnH + 8
	ENDPROC

	*-- Una fila: el control en su sitio, la etiqueta a su altura y debajo su ayuda.
	PROCEDURE Row
		LPARAMETERS toLabel, toControl, toHint, tnY
		toControl.Top = tnY
		toLabel.Top = tnY + 4
		tnY = tnY + toControl.Height
		IF !ISNULL(toHint)
			toHint.Top = tnY + 2
			toHint.Height = MAX(16, This.oModule.WrapHeight(toHint))
			tnY = toHint.Top + toHint.Height
		ENDIF
		RETURN tnY + 8
	ENDPROC

	PROCEDURE lstProviders.InteractiveChange
		IF This.ListIndex > 0
			Thisform.ShowEntry(Thisform.oIds.Item(This.ListIndex))
			Thisform.lblState.Caption = ""
		ENDIF
	ENDPROC

	*-- Otro proveedor: sus modelos. La variable no cambia: no se propone ningún nombre.
	PROCEDURE cboProvider.InteractiveChange
		Thisform.FillModels()
	ENDPROC

	PROCEDURE optKeySource.InteractiveChange
		Thisform.KeyFields("")
	ENDPROC

	PROCEDURE txtKey.InteractiveChange
		IF Thisform.optKeySource.Value = 2
			Thisform.VariableHint()
		ENDIF
	ENDPROC

	PROCEDURE cmdNew.Click
		Thisform.lstProviders.ListIndex = 0
		Thisform.ShowEntry("")
		Thisform.lblState.Caption = ""
		Thisform.txtName.SetFocus()
	ENDPROC

	*-- Sin diálogo: la primera pulsación lo pide en la línea de estado, la segunda borra.
	PROCEDURE cmdDelete.Click
		LOCAL loM, lcErr, lcName
		loM = Thisform.oModule
		IF EMPTY(Thisform.cId)
			RETURN
		ENDIF
		lcName = loM.oProviders.Item(Thisform.cId).cName
		IF !(Thisform.cDeleteAsked == Thisform.cId)
			Thisform.cDeleteAsked = Thisform.cId
			Thisform.lblState.Caption = loM.T("data.ai.providers.deleteAgain", lcName)
			RETURN
		ENDIF
		lcErr = loM.DeleteEntry(Thisform.cId)
		Thisform.FillList(loM.ActiveId())
		Thisform.lblState.Caption = EVL(lcErr, loM.cLastNotice)
	ENDPROC

	PROCEDURE cmdSave.Click
		LOCAL loM, loD, lcErr
		loM = Thisform.oModule
		lcErr = loM.SaveLicense(Thisform.txtLicense.Value)
		IF !EMPTY(lcErr)
			Thisform.lblState.Caption = lcErr
			RETURN
		ENDIF
		Thisform.txtLicense.Value = loM.LicenseFile()
		loD = CREATEOBJECT("Empty")
		ADDPROPERTY(loD, "cId", Thisform.cId)
		ADDPROPERTY(loD, "cName", Thisform.txtName.Value)
		ADDPROPERTY(loD, "cProvider", Thisform.cboProvider.Value)
		ADDPROPERTY(loD, "cModel", Thisform.cboModel.DisplayValue)
		ADDPROPERTY(loD, "cEndpoint", Thisform.txtEndpoint.Value)
		ADDPROPERTY(loD, "cKeySource", IIF(Thisform.optKeySource.Value = 2, "environment", "windows"))
		ADDPROPERTY(loD, "cKey", IIF(Thisform.optKeySource.Value = 2, "", Thisform.txtKey.Value))
		ADDPROPERTY(loD, "cKeyVariable", IIF(Thisform.optKeySource.Value = 2, Thisform.txtKey.Value, ""))
		lcErr = loM.SaveEntry(loD)
		IF !EMPTY(loD.cId) AND loM.oProviders.GetKey(loD.cId) > 0
			Thisform.FillList(loD.cId)
		ENDIF
		Thisform.lblState.Caption = EVL(lcErr, loM.cLastNotice)
	ENDPROC

	PROCEDURE cmdUse.Click
		LOCAL loM, lcErr
		loM = Thisform.oModule
		loM.cLastNotice = ""
		lcErr = loM.UseProvider(Thisform.cId)
		Thisform.FillList(Thisform.cId)
		Thisform.lblState.Caption = EVL(lcErr, loM.cLastNotice)
	ENDPROC

	*-- El fichero de la licencia (GETFILE: lo pide la persona que pulsa el botón).
	PROCEDURE cmdLicense.Click
		LOCAL lcFile
		lcFile = GETFILE("lic", "", "", 0, Thisform.oModule.T("data.ai.settings.licensePick"))
		IF !EMPTY(lcFile)
			Thisform.txtLicense.Value = lcFile
		ENDIF
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC
ENDDEFINE
