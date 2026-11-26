port module Main exposing (main)

import Alertas
import Api
import Browser
import Dict exposing (Dict)
import Hora
import Html exposing (Html, button, div, h1, h2, h3, input, label, li, option, p, select, span, table, td, text, th, tr, ul)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Http
import Informe
import Json.Decode as D
import Json.Encode as E
import Time



-- Puertos


port imprimir : () -> Cmd msg



-- Modelo


type Pestana
    = Linea
    | Preguntar
    | Seguimiento
    | VerInforme
    | Custodia


type alias Seguida =
    { consulta : Api.Consulta
    , pregunta : Alertas.Pregunta
    , seguir : Bool
    , reconstruccion : Maybe String
    }


type alias Alerta =
    { consulta : Int
    , texto : String
    , cambio : Bool
    }


type alias Model =
    { nombre : String
    , entro : Bool
    , pestana : Pestana
    , estado : Maybe Api.Estado
    , conectado : Bool
    , referencia : Api.Referencia
    , datos : Maybe Api.Datos
    , modoLinea : String
    , filtro : String
    , ultimoVisto : Maybe Int
    , tipo : String
    , campos : Dict String String
    , modo : String
    , esperando : Bool
    , preguntas : List Seguida
    , alertas : List Alerta
    , informe : Maybe Informe.Reporte
    , modoInforme : String
    , custodia : Maybe Api.Custodia
    , correccion : Dict String String
    , mensaje : Maybe String
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { nombre = ""
      , entro = False
      , pestana = Linea
      , estado = Nothing
      , conectado = True
      , referencia = Api.Referencia [] []
      , datos = Nothing
      , modoLinea = "original"
      , filtro = ""
      , ultimoVisto = Nothing
      , tipo = "donde"
      , campos = Dict.empty
      , modo = "original"
      , esperando = False
      , preguntas = []
      , alertas = []
      , informe = Nothing
      , modoInforme = "original"
      , custodia = Nothing
      , correccion = Dict.fromList [ ( "tipo", "desfase_reloj" ), ( "fuente", "radio" ) ]
      , mensaje = Nothing
      }
    , Cmd.none
    )



-- Mensajes


type Msg
    = EscribirNombre String
    | Entrar
    | Ir Pestana
    | Tick Time.Posix
    | LlegoEstado (Result Http.Error Api.Estado)
    | LlegoReferencia (Result Http.Error Api.Referencia)
    | LlegoDatos (Result Http.Error Api.Datos)
    | LlegoNovedades (Result Http.Error Api.Novedades)
    | CambiarModoLinea String
    | Filtrar String
    | ElegirTipo String
    | Campo String String
    | ElegirModo String
    | Enviar
    | LlegoRespuesta (Result Http.Error Api.Consulta)
    | LlegoReconsulta Int String (Result Http.Error Api.Consulta)
    | AlternarSeguir Int
    | Reconstruir Int
    | LlegoReconstruccion Int (Result Http.Error String)
    | QuitarAlerta Int
    | PedirInforme
    | CambiarModoInforme String
    | LlegoInforme (Result Http.Error Api.Informe)
    | Imprimir
    | Verificar
    | LlegoCustodia (Result Http.Error Api.Custodia)
    | CampoCorreccion String String
    | EnviarCorreccion
    | CorreccionEnviada (Result Http.Error Int)



-- Peticiones


pedirEstado : Cmd Msg
pedirEstado =
    Http.get { url = "/api/estado", expect = Http.expectJson LlegoEstado Api.estadoDecoder }


pedirDatos : String -> Cmd Msg
pedirDatos modo =
    Http.get { url = "/api/linea?modo=" ++ modo, expect = Http.expectJson LlegoDatos Api.datosDecoder }


pedirNovedades : Int -> Cmd Msg
pedirNovedades desde =
    Http.get { url = "/api/novedades?desde=" ++ String.fromInt desde, expect = Http.expectJson LlegoNovedades Api.novedadesDecoder }


consultar : String -> Alertas.Pregunta -> String -> (Result Http.Error Api.Consulta -> Msg) -> Cmd Msg
consultar nombre pregunta modo alLlegar =
    Http.post
        { url = "/api/consultas"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "investigador", E.string nombre )
                    , ( "tipo", E.string pregunta.tipo )
                    , ( "modo", E.string modo )
                    , ( "parametros", E.dict identity E.string pregunta.parametros )
                    ]
                )
        , expect = Http.expectJson alLlegar Api.consultaDecoder
        }


reconstruccionDecoder : D.Decoder String
reconstruccionDecoder =
    D.oneOf
        [ D.field "error" D.string
        , D.map2
            (\h r ->
                if h && r then
                    "Reconstruida desde la base de datos: los hechos y la respuesta son identicos."

                else
                    "La reconstruccion NO coincide (hechos: " ++ siNo h ++ ", respuesta: " ++ siNo r ++ ")."
            )
            (D.field "hechos_identicos" D.bool)
            (D.field "respuesta_identica" D.bool)
        ]


siNo : Bool -> String
siNo b =
    if b then
        "iguales"

    else
        "distintos"



-- Actualizacion


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EscribirNombre n ->
            ( { model | nombre = n }, Cmd.none )

        Entrar ->
            if String.isEmpty (String.trim model.nombre) then
                ( model, Cmd.none )

            else
                ( { model | entro = True }
                , Cmd.batch
                    [ pedirEstado
                    , pedirDatos model.modoLinea
                    , Http.get { url = "/api/referencia", expect = Http.expectJson LlegoReferencia Api.referenciaDecoder }
                    ]
                )

        Ir pestana ->
            ( { model | pestana = pestana, mensaje = Nothing }
            , case pestana of
                Linea ->
                    pedirDatos model.modoLinea

                VerInforme ->
                    Cmd.none

                Custodia ->
                    Http.get { url = "/api/custodia", expect = Http.expectJson LlegoCustodia Api.custodiaDecoder }

                _ ->
                    Cmd.none
            )

        Tick _ ->
            ( model
            , if model.entro then
                pedirEstado

              else
                Cmd.none
            )

        LlegoEstado (Ok estado) ->
            let
                cambioVersion =
                    Maybe.map .version model.estado /= Just estado.version
            in
            case model.ultimoVisto of
                Nothing ->
                    ( { model | estado = Just estado, conectado = True, ultimoVisto = Just estado.registrosEnVersion }, Cmd.none )

                Just visto ->
                    ( { model | estado = Just estado, conectado = True }
                    , if cambioVersion then
                        Cmd.batch
                            [ pedirNovedades visto
                            , if model.pestana == Linea then
                                pedirDatos model.modoLinea

                              else
                                Cmd.none
                            ]

                      else
                        Cmd.none
                    )

        LlegoEstado (Err _) ->
            ( { model | conectado = False }, Cmd.none )

        LlegoReferencia (Ok r) ->
            ( { model | referencia = r }, Cmd.none )

        LlegoReferencia (Err _) ->
            ( model, Cmd.none )

        LlegoDatos (Ok d) ->
            ( { model | datos = Just d }, Cmd.none )

        LlegoDatos (Err _) ->
            ( { model | conectado = False }, Cmd.none )

        LlegoNovedades (Ok nov) ->
            let
                afectadas =
                    List.filterMap
                        (\s ->
                            case List.filter (\ev -> Alertas.afecta ev s.pregunta) nov.eventos of
                                ev :: _ ->
                                    if s.seguir then
                                        Just ( s, ev )

                                    else
                                        Nothing

                                [] ->
                                    Nothing
                        )
                        model.preguntas
            in
            ( { model | ultimoVisto = Just (max nov.hasta (Maybe.withDefault 0 model.ultimoVisto)) }
            , Cmd.batch
                (List.map
                    (\( s, ev ) ->
                        consultar model.nombre s.pregunta s.consulta.modo (LlegoReconsulta s.consulta.id (ev.id ++ " · " ++ ev.descripcion))
                    )
                    afectadas
                )
            )

        LlegoNovedades (Err _) ->
            ( model, Cmd.none )

        CambiarModoLinea m ->
            ( { model | modoLinea = m }, pedirDatos m )

        Filtrar f ->
            ( { model | filtro = f }, Cmd.none )

        ElegirTipo t ->
            ( { model | tipo = t, campos = Dict.empty }, Cmd.none )

        Campo k v ->
            ( { model | campos = Dict.insert k v model.campos }, Cmd.none )

        ElegirModo m ->
            ( { model | modo = m }, Cmd.none )

        Enviar ->
            ( { model | esperando = True, mensaje = Nothing }
            , consultar model.nombre (Alertas.Pregunta model.tipo (camposCompletos model)) model.modo LlegoRespuesta
            )

        LlegoRespuesta (Ok c) ->
            ( { model
                | esperando = False
                , preguntas = Seguida c (Alertas.Pregunta c.tipo (Dict.fromList c.parametros)) False Nothing :: model.preguntas
              }
            , Cmd.none
            )

        LlegoRespuesta (Err _) ->
            ( { model | esperando = False, mensaje = Just "El servidor no respondio. La pregunta no se pudo enviar." }, Cmd.none )

        LlegoReconsulta idAnterior evidencia (Ok nueva) ->
            let
                anterior =
                    List.head (List.filter (\s -> s.consulta.id == idAnterior) model.preguntas)

                cambio =
                    Maybe.map (\s -> Alertas.cambio s.consulta.respuesta nueva.respuesta) anterior == Just True

                texto_ =
                    "Nueva evidencia ("
                        ++ evidencia
                        ++ ") afecta tu pregunta #"
                        ++ String.fromInt idAnterior
                        ++ ". "
                        ++ (if cambio then
                                "La respuesta CAMBIO: " ++ nueva.respuesta.resumen

                            else
                                "La respuesta se mantiene."
                           )
            in
            ( { model
                | alertas = Alerta nueva.id texto_ cambio :: model.alertas
                , preguntas =
                    List.map
                        (\s ->
                            if s.consulta.id == idAnterior then
                                { s | consulta = nueva, reconstruccion = Nothing }

                            else
                                s
                        )
                        model.preguntas
              }
            , Cmd.none
            )

        LlegoReconsulta _ _ (Err _) ->
            ( model, Cmd.none )

        AlternarSeguir id ->
            ( { model
                | preguntas =
                    List.map
                        (\s ->
                            if s.consulta.id == id then
                                { s | seguir = not s.seguir }

                            else
                                s
                        )
                        model.preguntas
              }
            , Cmd.none
            )

        Reconstruir id ->
            ( model
            , Http.get
                { url = "/api/consultas/" ++ String.fromInt id ++ "/reconstruccion"
                , expect = Http.expectJson (LlegoReconstruccion id) reconstruccionDecoder
                }
            )

        LlegoReconstruccion id resultado ->
            let
                txt =
                    case resultado of
                        Ok t ->
                            t

                        Err _ ->
                            "No se pudo pedir la reconstruccion."
            in
            ( { model
                | preguntas =
                    List.map
                        (\s ->
                            if s.consulta.id == id then
                                { s | reconstruccion = Just txt }

                            else
                                s
                        )
                        model.preguntas
              }
            , Cmd.none
            )

        QuitarAlerta i ->
            ( { model | alertas = List.take i model.alertas ++ List.drop (i + 1) model.alertas }, Cmd.none )

        PedirInforme ->
            ( model, Http.get { url = "/api/informe?modo=" ++ model.modoInforme, expect = Http.expectJson LlegoInforme Api.informeDecoder } )

        CambiarModoInforme m ->
            ( { model | modoInforme = m }, Cmd.none )

        LlegoInforme (Ok inf) ->
            ( { model | informe = Just (Informe.construir inf) }, Cmd.none )

        LlegoInforme (Err _) ->
            ( { model | mensaje = Just "No se pudo generar el informe." }, Cmd.none )

        Imprimir ->
            ( model, imprimir () )

        Verificar ->
            ( model, Http.get { url = "/api/custodia", expect = Http.expectJson LlegoCustodia Api.custodiaDecoder } )

        LlegoCustodia (Ok c) ->
            ( { model | custodia = Just c }, Cmd.none )

        LlegoCustodia (Err _) ->
            ( { model | mensaje = Just "No se pudo verificar la custodia." }, Cmd.none )

        CampoCorreccion k v ->
            ( { model | correccion = Dict.insert k v model.correccion }, Cmd.none )

        EnviarCorreccion ->
            ( model
            , Http.post
                { url = "/api/correcciones"
                , body = Http.jsonBody (cuerpoCorreccion model)
                , expect = Http.expectJson CorreccionEnviada (D.field "correccion" D.int)
                }
            )

        CorreccionEnviada (Ok id) ->
            ( { model | mensaje = Just ("Correccion C" ++ String.fromInt id ++ " registrada. La evidencia original no cambia: pregunte en modo corregida para usarla.") }, Cmd.none )

        CorreccionEnviada (Err _) ->
            ( { model | mensaje = Just "La correccion fue rechazada: revise los campos." }, Cmd.none )


camposCompletos : Model -> Dict String String
camposCompletos model =
    let
        porDefecto =
            case model.tipo of
                "recorrido" ->
                    Dict.fromList [ ( "persona", "cualquiera" ), ( "origen", "COM" ), ( "destino", "COM" ) ]

                "quien_en" ->
                    Dict.fromList [ ( "modulo", "COM" ) ]

                "quien_tarjeta" ->
                    Dict.fromList [ ( "tarjeta", Maybe.withDefault "" (List.head (List.map (\( _, _, t ) -> t) model.referencia.personas)) ) ]

                "donde" ->
                    Dict.fromList [ ( "persona", Maybe.withDefault "" (List.head (List.map (\( i, _, _ ) -> i) model.referencia.personas)) ) ]

                _ ->
                    Dict.empty
    in
    Dict.filter (\_ v -> v /= "") (Dict.union model.campos porDefecto)


cuerpoCorreccion : Model -> E.Value
cuerpoCorreccion model =
    let
        campo k =
            Dict.get k model.correccion |> Maybe.withDefault ""

        numero k =
            String.toInt (campo k)

        opcional k =
            if campo k == "" then
                []

            else
                [ ( k, E.string (campo k) ) ]
    in
    E.object
        ([ ( "agencia", E.string (campo "agencia") )
         , ( "tipo", E.string (campo "tipo") )
         , ( "motivo", E.string (campo "motivo") )
         ]
            ++ opcional "fuente"
            ++ opcional "dispositivo"
            ++ (Maybe.map (\n -> [ ( "segundos", E.int n ) ]) (numero "segundos") |> Maybe.withDefault [])
            ++ (Maybe.map (\n -> [ ( "registro", E.int n ) ]) (numero "registro") |> Maybe.withDefault [])
        )



-- Vista


view : Model -> Html Msg
view model =
    if not model.entro then
        div [ class "entrada" ]
            [ h1 [] [ text "Halley-7 · Sistema forense" ]
            , p [] [ text "Escriba su nombre de investigador para entrar." ]
            , input [ placeholder "Nombre", value model.nombre, onInput EscribirNombre ] []
            , button [ onClick Entrar ] [ text "Entrar" ]
            ]

    else
        div []
            [ cabecera model
            , div [ class "alertas" ] (List.indexedMap vistaAlerta model.alertas)
            , case model.mensaje of
                Just m ->
                    p [ class "mensaje" ] [ text m ]

                Nothing ->
                    text ""
            , case model.pestana of
                Linea ->
                    vistaLinea model

                Preguntar ->
                    vistaPreguntar model

                Seguimiento ->
                    vistaSeguimiento model

                VerInforme ->
                    vistaInforme model

                Custodia ->
                    vistaCustodia model
            ]


cabecera : Model -> Html Msg
cabecera model =
    div [ class "cabecera" ]
        [ h1 [] [ text "Halley-7" ]
        , span [ class "quien" ] [ text ("Investigador: " ++ model.nombre) ]
        , case model.estado of
            Just e ->
                span [ class "version" ]
                    [ text
                        ("Version "
                            ++ String.fromInt e.version
                            ++ " · "
                            ++ String.fromInt e.registrosGuardados
                            ++ " registros · "
                            ++ String.join " · "
                                (List.map
                                    (\( n, ok, _ ) ->
                                        n
                                            ++ (if ok then
                                                    " OK"

                                                else
                                                    " CAIDO"
                                               )
                                    )
                                    e.componentes
                                )
                        )
                    ]

            Nothing ->
                text ""
        , if model.conectado then
            text ""

          else
            span [ class "desconectado" ] [ text "Sin conexion con el servidor, reintentando..." ]
        , div [ class "pestanas" ]
            [ boton model Linea "Linea de tiempo"
            , boton model Preguntar "Preguntar"
            , boton model Seguimiento ("Mis preguntas (" ++ String.fromInt (List.length model.preguntas) ++ ")")
            , boton model VerInforme "Informe"
            , boton model Custodia "Custodia"
            ]
        ]


boton : Model -> Pestana -> String -> Html Msg
boton model p etiqueta =
    button
        [ onClick (Ir p)
        , class
            (if model.pestana == p then
                "activa"

             else
                ""
            )
        ]
        [ text etiqueta ]


vistaAlerta : Int -> Alerta -> Html Msg
vistaAlerta i a =
    div
        [ class
            (if a.cambio then
                "alerta cambio"

             else
                "alerta"
            )
        ]
        [ text a.texto, button [ onClick (QuitarAlerta i) ] [ text "x" ] ]


selectorModo : String -> (String -> Msg) -> Html Msg
selectorModo actual alCambiar =
    label []
        [ text "Evidencia: "
        , select [ onInput alCambiar ]
            [ option [ value "original", selected (actual == "original") ] [ text "original" ]
            , option [ value "corregida", selected (actual == "corregida") ] [ text "con correcciones" ]
            ]
        ]


vistaLinea : Model -> Html Msg
vistaLinea model =
    case model.datos of
        Nothing ->
            p [] [ text "Cargando la linea de tiempo..." ]

        Just d ->
            let
                f =
                    String.toLower model.filtro

                eventos =
                    List.filter (\e -> String.contains f (String.toLower (e.descripcion ++ " " ++ e.fuente ++ " " ++ e.id))) d.eventos
            in
            div []
                [ div [ class "controles" ]
                    [ selectorModo model.modoLinea CambiarModoLinea
                    , input [ placeholder "Filtrar (persona, modulo, fuente...)", value model.filtro, onInput Filtrar ] []
                    , span [] [ text (String.fromInt (List.length eventos) ++ " eventos · version " ++ String.fromInt d.version) ]
                    ]
                , table []
                    (tr [] [ th [] [ text "Hora (UTC)" ], th [] [ text "Fuente" ], th [] [ text "Evento" ], th [] [ text "Id" ] ]
                        :: List.map (\e -> tr [] [ td [] [ text (Hora.texto e.ts) ], td [] [ text e.fuente ], td [] [ text e.descripcion ], td [] [ text e.id ] ]) eventos
                    )
                , h3 [] [ text "Deducciones de la radio y la bitacora" ]
                , ul [] (List.map (\x -> li [] [ text x ]) d.deducciones)
                , h3 [] [ text ("Problemas en las fuentes (" ++ String.fromInt (List.length d.problemas) ++ ")") ]
                , table []
                    (tr [] [ th [] [ text "Registro" ], th [] [ text "Fuente" ], th [] [ text "Tipo" ], th [] [ text "Motivo" ], th [] [ text "Original" ] ]
                        :: List.map
                            (\pr ->
                                tr []
                                    [ td [] [ text ("R" ++ String.fromInt pr.registro) ]
                                    , td [] [ text pr.fuente ]
                                    , td [] [ span [ class ("etiqueta " ++ pr.tipo) ] [ text pr.tipo ] ]
                                    , td []
                                        [ text
                                            (pr.motivo
                                                ++ (if pr.usado then
                                                        " (se usa)"

                                                    else
                                                        " (no se usa)"
                                                   )
                                            )
                                        ]
                                    , td [ class "crudo" ] [ text pr.original ]
                                    ]
                            )
                            d.problemas
                    )
                ]


vistaPreguntar : Model -> Html Msg
vistaPreguntar model =
    let
        personas =
            List.map (\( i, n, _ ) -> ( i, n )) model.referencia.personas

        tarjetas =
            List.map (\( _, n, t ) -> ( t, t ++ " (" ++ n ++ ")" )) model.referencia.personas

        modulos =
            List.map (\m -> ( m, m )) model.referencia.modulos

        lista clave opciones =
            label []
                [ text (clave ++ ": ")
                , select [ onInput (Campo clave) ]
                    (List.map (\( v, t ) -> option [ value v, selected (Dict.get clave model.campos == Just v) ] [ text t ]) opciones)
                ]

        libre clave ayuda =
            label [] [ text (clave ++ ": "), input [ placeholder ayuda, value (Dict.get clave model.campos |> Maybe.withDefault ""), onInput (Campo clave) ] [] ]

        campos =
            case model.tipo of
                "donde" ->
                    [ lista "persona" personas, libre "hora" "01:39:47" ]

                "quien_en" ->
                    [ lista "modulo" modulos, libre "desde" "01:30", libre "hasta" "02:00" ]

                "quien_tarjeta" ->
                    [ lista "tarjeta" tarjetas, libre "hora" "01:39:47" ]

                "recorrido" ->
                    [ lista "persona" (( "cualquiera", "cualquier persona" ) :: personas)
                    , lista "origen" modulos
                    , lista "destino" modulos
                    , libre "hora" "01:45"
                    , libre "minutos" "5"
                    ]

                _ ->
                    [ libre "desde" "00:00 (opcional)", libre "hasta" "03:00 (opcional)" ]
    in
    div [ class "formulario" ]
        [ h2 [] [ text "Nueva pregunta" ]
        , label []
            [ text "Pregunta: "
            , select [ onInput ElegirTipo ]
                (List.map (\( v, t ) -> option [ value v, selected (model.tipo == v) ] [ text t ])
                    [ ( "donde", "¿Donde pudo estar una persona a una hora?" )
                    , ( "quien_en", "¿Quien pudo estar en un modulo en un intervalo?" )
                    , ( "quien_tarjeta", "¿Quien pudo usar una tarjeta?" )
                    , ( "recorrido", "¿Era posible un recorrido en cierto tiempo?" )
                    , ( "exterior", "¿Se abrio la puerta exterior y quien pudo salir?" )
                    ]
                )
            ]
        , div [ class "campos" ] campos
        , selectorModo model.modo ElegirModo
        , p [ class "ayuda" ] [ text "Horas en UTC del 14/06/2041, formato HH:MM o HH:MM:SS." ]
        , button [ onClick Enviar, disabled model.esperando ]
            [ text
                (if model.esperando then
                    "Consultando..."

                 else
                    "Preguntar"
                )
            ]
        , case model.preguntas of
            ultima :: _ ->
                vistaSeguida model ultima

            [] ->
                text ""
        ]


vistaSeguimiento : Model -> Html Msg
vistaSeguimiento model =
    div []
        [ h2 [] [ text "Mis preguntas" ]
        , p [ class "ayuda" ] [ text "Marque \"Avisarme\" para recibir una alerta cuando llegue evidencia nueva que afecte a la pregunta." ]
        , div [] (List.map (vistaSeguida model) model.preguntas)
        ]


vistaSeguida : Model -> Seguida -> Html Msg
vistaSeguida model s =
    let
        c =
            s.consulta

        r =
            c.respuesta

        eventos =
            Maybe.map (\d -> Dict.fromList (List.map (\e -> ( e.id, e )) d.eventos)) model.datos |> Maybe.withDefault Dict.empty
    in
    div [ class "respuesta" ]
        [ p [ class "titulo" ]
            [ text ("#" ++ String.fromInt c.id ++ " · " ++ c.tipo ++ " · " ++ String.join ", " (List.map (\( k, v ) -> k ++ "=" ++ v) c.parametros) ++ " · version " ++ String.fromInt c.version ++ " · " ++ c.modo) ]
        , p [] [ span [ class ("estado " ++ r.estado) ] [ text r.estado ], text (" " ++ r.resumen) ]
        , detalle r
        , if List.isEmpty r.evidencia then
            text ""

          else
            div []
                [ p [ class "sub" ] [ text "Evidencia que la sostiene:" ]
                , ul []
                    (List.map
                        (\ev ->
                            li []
                                [ text
                                    (ev.id
                                        ++ " · "
                                        ++ ev.nota
                                        ++ (Dict.get ev.id eventos |> Maybe.map (\e -> " — " ++ Hora.texto e.ts ++ " " ++ e.descripcion) |> Maybe.withDefault "")
                                    )
                                ]
                        )
                        r.evidencia
                    )
                ]
        , div [ class "acciones" ]
            [ label []
                [ input [ type_ "checkbox", Html.Attributes.checked s.seguir, onClick (AlternarSeguir c.id) ] []
                , text " Avisarme si llega evidencia que la afecte"
                ]
            , button [ onClick (Reconstruir c.id) ] [ text "Reconstruir desde la base de datos" ]
            ]
        , case s.reconstruccion of
            Just t ->
                p [ class "sub" ] [ text t ]

            Nothing ->
                text ""
        ]


detalle : Api.Respuesta -> Html Msg
detalle r =
    div []
        [ if List.isEmpty r.personas then
            text ""

          else
            ul [] (List.map (\pe -> li [] [ text (pe.nombre ++ ": "), span [ class ("estado " ++ pe.estado) ] [ text pe.estado ] ]) r.personas)
        , if List.isEmpty r.candidatos then
            text ""

          else
            p [] [ text ("Candidatos: " ++ String.join ", " r.candidatos) ]
        , if List.isEmpty r.ruta then
            text ""

          else
            p [] [ text ("Ruta: " ++ String.join " -> " r.ruta) ]
        , div []
            (List.map
                (\a -> p [] [ text ("Apertura probable " ++ a.desde ++ "-" ++ a.hasta ++ " (bajo " ++ String.fromFloat a.caida ++ " grados). Pudieron estar en el almacen: " ++ String.join ", " a.personas) ])
                r.aperturas
            )
        ]


vistaInforme : Model -> Html Msg
vistaInforme model =
    div []
        [ div [ class "controles no-imprimir" ]
            [ selectorModo model.modoInforme CambiarModoInforme
            , button [ onClick PedirInforme ] [ text "Generar informe" ]
            , button [ onClick Imprimir, disabled (model.informe == Nothing) ] [ text "Imprimir o guardar en PDF" ]
            ]
        , case model.informe of
            Just r ->
                Informe.vista r

            Nothing ->
                p [] [ text "Pulse \"Generar informe\" para construirlo con la evidencia y las preguntas actuales." ]
        ]


vistaCustodia : Model -> Html Msg
vistaCustodia model =
    let
        campo clave ayuda =
            label [] [ text (clave ++ ": "), input [ placeholder ayuda, value (Dict.get clave model.correccion |> Maybe.withDefault ""), onInput (CampoCorreccion clave) ] [] ]
    in
    div []
        [ h2 [] [ text "Cadena de custodia" ]
        , button [ onClick Verificar ] [ text "Verificar ahora" ]
        , case model.custodia of
            Just c ->
                p []
                    [ span
                        [ class
                            (if c.valida then
                                "estado seguro"

                             else
                                "estado contradictoria"
                            )
                        ]
                        [ text
                            (if c.valida then
                                "integra"

                             else
                                "alterada"
                            )
                        ]
                    , text
                        (" "
                            ++ String.fromInt c.registros
                            ++ " registros y "
                            ++ String.fromInt c.correcciones
                            ++ " correcciones encadenadas con SHA-256. "
                            ++ (Maybe.map (\i -> "Primer registro alterado: R" ++ String.fromInt i ++ ". ") c.alterado |> Maybe.withDefault "")
                            ++ "Ultimo hash: "
                            ++ String.left 16 c.ultimoHash
                            ++ "..."
                        )
                    ]

            Nothing ->
                text ""
        , h2 [] [ text "Enviar una correccion de una agencia" ]
        , p [ class "ayuda" ] [ text "La correccion se guarda aparte; la evidencia original nunca cambia." ]
        , div [ class "campos" ]
            [ campo "agencia" "BAS (Reino Unido)"
            , label []
                [ text "tipo: "
                , select [ onInput (CampoCorreccion "tipo") ]
                    [ option [ value "desfase_reloj" ] [ text "desfase de reloj" ]
                    , option [ value "descartar" ] [ text "descartar un registro" ]
                    ]
                ]
            , campo "fuente" "radio, tarjetas, temperatura..."
            , campo "dispositivo" "P7 (opcional)"
            , campo "segundos" "-420"
            , campo "registro" "25 (solo para descartar)"
            , campo "motivo" "El reloj estaba adelantado 7 minutos"
            ]
        , button [ onClick EnviarCorreccion ] [ text "Registrar correccion" ]
        ]



-- Programa


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Time.every 2000 Tick
        }
