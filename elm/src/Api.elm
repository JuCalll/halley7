module Api exposing
    ( Apertura
    , Consulta
    , Correccion
    , Custodia
    , Datos
    , Estado
    , Evento
    , Evidencia
    , Informe
    , Novedades
    , PersonaEstado
    , Problema
    , Referencia
    , Respuesta
    , consultaDecoder
    , custodiaDecoder
    , datosDecoder
    , estadoDecoder
    , informeDecoder
    , novedadesDecoder
    , referenciaDecoder
    , respuestaDecoder
    )

import Json.Decode as D exposing (Decoder)



-- Tipos


type alias Estado =
    { version : Int
    , registrosGuardados : Int
    , registrosEnVersion : Int
    , correcciones : Int
    , componentes : List ( String, Bool, String )
    }


type alias Referencia =
    { personas : List ( String, String, String )
    , modulos : List String
    }


type alias Evento =
    { id : String
    , registro : Int
    , fuente : String
    , ts : Int
    , tipo : String
    , descripcion : String
    , persona : Maybe String
    , modulo : Maybe String
    , desde : Maybe String
    , hacia : Maybe String
    , tarjeta : Maybe String
    , puerta : Maybe String
    }


type alias Problema =
    { registro : Int
    , fuente : String
    , tipo : String
    , motivo : String
    , usado : Bool
    , original : String
    }


type alias Datos =
    { version : Int
    , modo : String
    , eventos : List Evento
    , problemas : List Problema
    , deducciones : List String
    }


type alias Novedades =
    { version : Int
    , hasta : Int
    , eventos : List Evento
    }


type alias Evidencia =
    { id : String
    , nota : String
    }


type alias PersonaEstado =
    { nombre : String
    , estado : String
    }


type alias Apertura =
    { desde : String
    , hasta : String
    , caida : Float
    , personas : List String
    }


type alias Respuesta =
    { estado : String
    , resumen : String
    , evidencia : List Evidencia
    , modulos : List String
    , personas : List PersonaEstado
    , candidatos : List String
    , ruta : List String
    , aperturas : List Apertura
    }


type alias Consulta =
    { id : Int
    , version : Int
    , modo : String
    , tipo : String
    , investigador : String
    , parametros : List ( String, String )
    , respuesta : Respuesta
    }


type alias Correccion =
    { id : Int
    , agencia : String
    , tipo : String
    , motivo : String
    , creadaEn : String
    }


type alias Custodia =
    { registros : Int
    , correcciones : Int
    , valida : Bool
    , alterado : Maybe Int
    , ultimoHash : String
    }


type alias Informe =
    { datos : Datos
    , consultas : List Consulta
    , correcciones : List Correccion
    , custodia : Custodia
    }



-- Decodificadores


conDefecto : a -> String -> Decoder a -> Decoder a
conDefecto defecto campo dec =
    D.map (Maybe.withDefault defecto) (D.maybe (D.field campo dec))


estadoDecoder : Decoder Estado
estadoDecoder =
    D.map5 Estado
        (D.field "version" D.int)
        (D.field "registros_guardados" D.int)
        (D.field "registros_en_version" D.int)
        (D.field "correcciones" D.int)
        (D.field "componentes"
            (D.list
                (D.map3 (\a b c -> ( a, b, c ))
                    (D.field "nombre" D.string)
                    (D.field "disponible" D.bool)
                    (D.field "mensaje" D.string)
                )
            )
        )


referenciaDecoder : Decoder Referencia
referenciaDecoder =
    D.map2 Referencia
        (D.field "personas"
            (D.list
                (D.map3 (\a b c -> ( a, b, c ))
                    (D.field "id" D.string)
                    (D.field "nombre" D.string)
                    (D.field "tarjeta" D.string)
                )
            )
        )
        (D.field "modulos" (D.list D.string))


opcional : String -> Decoder (Maybe String)
opcional campo =
    D.maybe (D.field campo D.string)


eventoDecoder : Decoder Evento
eventoDecoder =
    D.succeed Evento
        |> andMap (D.field "id" D.string)
        |> andMap (D.field "registro" D.int)
        |> andMap (D.field "fuente" D.string)
        |> andMap (D.field "ts" D.int)
        |> andMap (D.field "tipo" D.string)
        |> andMap (D.field "descripcion" D.string)
        |> andMap (opcional "persona")
        |> andMap (opcional "modulo")
        |> andMap (opcional "desde")
        |> andMap (opcional "hacia")
        |> andMap (opcional "tarjeta")
        |> andMap (opcional "puerta")


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    D.map2 (|>)


problemaDecoder : Decoder Problema
problemaDecoder =
    D.map6 Problema
        (D.field "registro" D.int)
        (D.field "fuente" D.string)
        (D.field "tipo" D.string)
        (D.field "motivo" D.string)
        (D.field "usado" D.bool)
        (conDefecto "" "original" D.string)


datosDecoder : Decoder Datos
datosDecoder =
    D.map5 Datos
        (D.field "version" D.int)
        (D.field "modo" D.string)
        (D.field "eventos" (D.list eventoDecoder))
        (D.field "problemas" (D.list problemaDecoder))
        (D.field "deducciones" (D.list (D.field "descripcion" D.string)))


novedadesDecoder : Decoder Novedades
novedadesDecoder =
    D.map3 Novedades
        (D.field "version" D.int)
        (D.field "hasta" D.int)
        (D.field "eventos" (D.list eventoDecoder))


respuestaDecoder : Decoder Respuesta
respuestaDecoder =
    D.succeed Respuesta
        |> andMap (D.field "estado" D.string)
        |> andMap (D.field "resumen" D.string)
        |> andMap (conDefecto [] "evidencia" (D.list (D.map2 Evidencia (D.field "id" D.string) (D.field "nota" D.string))))
        |> andMap (conDefecto [] "modulos" (D.list D.string))
        |> andMap (conDefecto [] "personas" (D.list (D.map2 PersonaEstado (D.field "nombre" D.string) (D.field "estado" D.string))))
        |> andMap (conDefecto [] "candidatos" (D.list (D.field "nombre" D.string)))
        |> andMap (conDefecto [] "ruta" (D.list D.string))
        |> andMap
            (conDefecto []
                "aperturas"
                (D.list
                    (D.map4 Apertura
                        (D.field "desde" D.string)
                        (D.field "hasta" D.string)
                        (D.field "caida" D.float)
                        (D.field "personas" (D.list D.string))
                    )
                )
            )


parametrosDecoder : Decoder (List ( String, String ))
parametrosDecoder =
    D.keyValuePairs (D.oneOf [ D.string, D.map String.fromInt D.int ])


consultaDecoder : Decoder Consulta
consultaDecoder =
    D.map7 Consulta
        (D.oneOf [ D.field "consulta" D.int, D.field "id" D.int ])
        (D.field "version" D.int)
        (D.field "modo" D.string)
        (D.field "tipo" D.string)
        (conDefecto "" "investigador" D.string)
        (conDefecto [] "parametros" parametrosDecoder)
        (D.field "respuesta" respuestaDecoder)


correccionDecoder : Decoder Correccion
correccionDecoder =
    D.map5 Correccion
        (D.field "id" D.int)
        (D.field "agencia" D.string)
        (D.field "tipo" D.string)
        (D.field "motivo" D.string)
        (D.field "creada_en" D.string)


custodiaDecoder : Decoder Custodia
custodiaDecoder =
    D.map5 Custodia
        (D.field "registros" D.int)
        (D.field "correcciones" D.int)
        (D.field "valida" D.bool)
        (D.maybe (D.field "registro_alterado" D.int))
        (D.field "ultimo_hash" D.string)


informeDecoder : Decoder Informe
informeDecoder =
    D.map4 Informe
        datosDecoder
        (D.field "consultas" (D.list consultaDecoder))
        (D.field "correcciones" (D.list correccionDecoder))
        (D.field "custodia" custodiaDecoder)
