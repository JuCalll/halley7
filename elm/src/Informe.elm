module Informe exposing (Reporte, construir, vista)

import Api exposing (Consulta, Evento, Evidencia, Problema)
import Dict exposing (Dict)
import Hora
import Html exposing (Html, div, h2, h3, li, p, span, table, td, text, th, tr, ul)
import Html.Attributes exposing (class)



-- Modelo del informe


type alias Respaldo =
    { evidencia : Evidencia
    , evento : Maybe Evento
    }


type alias PreguntaRespondida =
    { consulta : Consulta
    , respaldos : List Respaldo
    }


type alias Reporte =
    { version : Int
    , modo : String
    , linea : List Evento
    , deducciones : List String
    , problemasPorFuente : List ( String, List Problema )
    , conteoPorTipo : List ( String, Int )
    , preguntas : List PreguntaRespondida
    , correcciones : List Api.Correccion
    , custodia : Api.Custodia
    }



-- Construccion


construir : Api.Informe -> Reporte
construir inf =
    let
        porId =
            Dict.fromList (List.map (\e -> ( e.id, e )) inf.datos.eventos)

        respaldar ev =
            Respaldo ev (Dict.get ev.id porId)
    in
    { version = inf.datos.version
    , modo = inf.datos.modo
    , linea = inf.datos.eventos
    , deducciones = inf.datos.deducciones
    , problemasPorFuente = agrupar .fuente inf.datos.problemas
    , conteoPorTipo = List.map (\( t, ps ) -> ( t, List.length ps )) (agrupar .tipo inf.datos.problemas)
    , preguntas =
        List.map (\c -> PreguntaRespondida c (List.map respaldar c.respuesta.evidencia))
            (List.filter (\c -> c.modo == inf.datos.modo) inf.consultas)
    , correcciones = inf.correcciones
    , custodia = inf.custodia
    }


agrupar : (a -> String) -> List a -> List ( String, List a )
agrupar clave xs =
    Dict.toList
        (List.foldr (\x d -> Dict.update (clave x) (\v -> Just (x :: Maybe.withDefault [] v)) d) Dict.empty xs)



-- Vista


vista : Reporte -> Html msg
vista r =
    div [ class "informe" ]
        [ h2 [] [ text "Informe del caso Halley-7" ]
        , p []
            [ text
                ("Version de la evidencia: "
                    ++ String.fromInt r.version
                    ++ " · Modo: "
                    ++ r.modo
                    ++ " · Custodia: "
                    ++ (if r.custodia.valida then
                            "integra (" ++ String.fromInt r.custodia.registros ++ " registros)"

                        else
                            "ALTERADA"
                       )
                )
            ]
        , h3 [] [ text "1. Linea de tiempo reconstruida" ]
        , table [] (tr [] [ th [] [ text "Hora (UTC)" ], th [] [ text "Fuente" ], th [] [ text "Evento" ], th [] [ text "Id" ] ] :: List.map filaEvento r.linea)
        , h3 [] [ text "Deducciones de los textos" ]
        , ul [] (List.map (\d -> li [] [ text d ]) r.deducciones)
        , h3 [] [ text "2. Problemas encontrados en las fuentes" ]
        , p [] [ text (String.join " · " (List.map (\( t, n ) -> t ++ ": " ++ String.fromInt n) r.conteoPorTipo)) ]
        , div [] (List.map seccionFuente r.problemasPorFuente)
        , h3 [] [ text "3. Preguntas y respuestas" ]
        , div [] (List.map vistaPregunta r.preguntas)
        , h3 [] [ text "4. Correcciones recibidas" ]
        , if List.isEmpty r.correcciones then
            p [] [ text "Ninguna." ]

          else
            ul [] (List.map (\c -> li [] [ text ("C" ++ String.fromInt c.id ++ " · " ++ c.agencia ++ " · " ++ c.tipo ++ ": " ++ c.motivo) ]) r.correcciones)
        ]


filaEvento : Evento -> Html msg
filaEvento e =
    tr [] [ td [] [ text (Hora.texto e.ts) ], td [] [ text e.fuente ], td [] [ text e.descripcion ], td [] [ text e.id ] ]


seccionFuente : ( String, List Problema ) -> Html msg
seccionFuente ( fuente, ps ) =
    div []
        [ p [ class "fuente" ] [ text (fuente ++ " (" ++ String.fromInt (List.length ps) ++ ")") ]
        , ul []
            (List.map
                (\pr ->
                    li []
                        [ span [ class ("etiqueta " ++ pr.tipo) ] [ text pr.tipo ]
                        , text
                            (" R"
                                ++ String.fromInt pr.registro
                                ++ ": "
                                ++ pr.motivo
                                ++ (if pr.usado then
                                        " (se usa)"

                                    else
                                        " (no se usa)"
                                   )
                            )
                        ]
                )
                ps
            )
        ]


vistaPregunta : PreguntaRespondida -> Html msg
vistaPregunta pr =
    let
        c =
            pr.consulta
    in
    div [ class "pregunta" ]
        [ p [] [ text ("#" ++ String.fromInt c.id ++ " · " ++ c.investigador ++ " · " ++ c.tipo ++ " " ++ String.join ", " (List.map (\( k, v ) -> k ++ "=" ++ v) c.parametros) ++ " · version " ++ String.fromInt c.version) ]
        , p [] [ span [ class ("estado " ++ c.respuesta.estado) ] [ text c.respuesta.estado ], text (" " ++ c.respuesta.resumen) ]
        , ul []
            (List.map
                (\rs ->
                    li [] [ text (rs.evidencia.id ++ " · " ++ rs.evidencia.nota ++ Maybe.withDefault "" (Maybe.map (\e -> " — " ++ Hora.texto e.ts ++ " " ++ e.descripcion) rs.evento)) ]
                )
                pr.respaldos
            )
        ]
