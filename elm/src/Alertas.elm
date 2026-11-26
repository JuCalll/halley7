module Alertas exposing (Pregunta, afecta, cambio, centro)

import Api exposing (Evento, Respuesta)
import Dict exposing (Dict)
import Hora



-- Pregunta seguida


type alias Pregunta =
    { tipo : String
    , parametros : Dict String String
    }


dato : String -> Pregunta -> Maybe String
dato clave p =
    Dict.get clave p.parametros


centro : Pregunta -> Maybe ( Int, Int )
centro p =
    case ( Maybe.andThen Hora.aEpoch (dato "hora" p), Maybe.andThen Hora.aEpoch (dato "desde" p), Maybe.andThen Hora.aEpoch (dato "hasta" p) ) of
        ( Just t, _, _ ) ->
            Just ( t, t )

        ( Nothing, Just a, Just b ) ->
            Just ( a, b )

        _ ->
            Nothing



-- Relevancia de la evidencia nueva


ventana : Int
ventana =
    2 * 3600


cerca : Evento -> Pregunta -> Bool
cerca ev p =
    case centro p of
        Just ( a, b ) ->
            ev.ts >= a - ventana && ev.ts <= b + ventana

        Nothing ->
            True


tocaModulo : String -> Evento -> Bool
tocaModulo m ev =
    List.member (Just m) [ ev.modulo, ev.desde, ev.hacia ]


afecta : Evento -> Pregunta -> Bool
afecta ev p =
    let
        es campo valor =
            dato campo p == Just valor
    in
    cerca ev p
        && (case p.tipo of
                "donde" ->
                    Maybe.map (\x -> es "persona" x) ev.persona == Just True

                "quien_en" ->
                    Maybe.map (\m -> tocaModulo m ev) (dato "modulo" p) == Just True

                "quien_tarjeta" ->
                    Maybe.map (\t -> es "tarjeta" t) ev.tarjeta
                        == Just True
                        || ev.tipo
                        == "presencia"

                "recorrido" ->
                    Maybe.map (\x -> es "persona" x) ev.persona
                        == Just True
                        || ev.tipo
                        == "corte"
                        || ev.tipo
                        == "restablecido"

                "exterior" ->
                    (ev.tipo == "temperatura" && ev.modulo == Just "ALM")
                        || ev.puerta
                        == Just "P8"
                        || ev.tipo
                        == "presencia"

                _ ->
                    False
           )


cambio : Respuesta -> Respuesta -> Bool
cambio antes despues =
    antes.estado /= despues.estado || antes.resumen /= despues.resumen
