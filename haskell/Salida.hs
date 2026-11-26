module Salida (aJson, aProlog) where

import Data.List (find, intercalate)
import Json
import Tiempo
import Tipos

-- JSON para el servidor

aJson :: Integracion -> Json
aJson i =
  JObjeto
    [ ("personas", JLista (map persona (refPersonas ref)))
    , ("puertas", JLista (map puerta (refPuertas ref)))
    , ("eventos", JLista (map (evento ref) (inEventos i)))
    , ("problemas", JLista (map problema (inProblemas i)))
    , ("deducciones", JLista (deducciones i))
    , ("hechos", JTexto (aProlog i))
    ]
  where
    ref = inReferencia i

persona :: Persona -> Json
persona p =
  JObjeto
    [ ("id", JTexto (perId p))
    , ("nombre", JTexto (perNombre p))
    , ("cargo", JTexto (perCargo p))
    , ("tarjeta", JTexto (perTarjeta p))
    , ("accesos", JLista (map JTexto (perAccesos p)))
    ]

puerta :: Puerta -> Json
puerta p =
  JObjeto
    [ ("codigo", JTexto (puCodigo p))
    , ("modulo1", JTexto (puModulo1 p))
    , ("modulo2", JTexto (puModulo2 p))
    , ("lector", JBool (puLector p))
    ]

numeroJ :: Integer -> Json
numeroJ = JNum . fromIntegral

nombreDe :: Referencia -> PersonaId -> String
nombreDe ref pid = maybe pid perNombre (find ((== pid) . perId) (refPersonas ref))

evento :: Referencia -> Evento -> Json
evento ref e =
  JObjeto
    ( [ ("id", JTexto (evId e))
      , ("registro", JNum (fromIntegral (evRegistro e)))
      , ("fuente", JTexto (evFuente e))
      , ("ts", numeroJ (evTs e))
      , ("hora", JTexto (isoUtc (evTs e)))
      , ("precision", numeroJ (evPrecision e))
      , ("tipo", JTexto (tipoDe (evDato e)))
      , ("descripcion", JTexto (describir ref (evDato e)))
      ]
        ++ detalles (evDato e)
    )
  where
    detalles (Paso t p d h r) =
      [ ("tarjeta", JTexto t)
      , ("puerta", JTexto p)
      , ("desde", JTexto d)
      , ("hacia", JTexto h)
      , ("resultado", JTexto (if r == Ok then "ok" else "denegado"))
      ]
        ++ [("persona", JTexto (perId per)) | per <- refPersonas ref, perTarjeta per == t]
    detalles (Presencia m n) = [("modulo", JTexto m), ("valor", JNum (fromIntegral n))]
    detalles (Temperatura m c) = [("modulo", JTexto m), ("valor", JNum c)]
    detalles (Mensaje h _ t) = [("texto", JTexto t)] ++ [("persona", JTexto p) | Just p <- [h]]
    detalles (Nota a t) = [("texto", JTexto t)] ++ [("persona", JTexto p) | Just p <- [a]]
    detalles _ = []

tipoDe :: Dato -> String
tipoDe d = case d of
  Paso {} -> "paso"
  Presencia {} -> "presencia"
  SensoresApagados -> "sensores_apagados"
  Temperatura {} -> "temperatura"
  Consumo _ -> "consumo"
  Corte {} -> "corte"
  Restablecido -> "restablecido"
  Mensaje {} -> "mensaje"
  Nota {} -> "nota"

describir :: Referencia -> Dato -> String
describir ref d = case d of
  Paso t p desde hacia r ->
    "Tarjeta " ++ t ++ titular t ++ " en " ++ p ++ ": " ++ desde ++ " -> " ++ hacia ++ (if r == Ok then " (OK)" else " (DENEGADO)")
  Presencia m n -> "Sensor de presencia: " ++ show n ++ (if n == 1 then " persona en " else " personas en ") ++ m
  SensoresApagados -> "Sensores de presencia sin energia"
  Temperatura m c -> "Temperatura " ++ m ++ ": " ++ show c ++ " C"
  Consumo kws -> "Consumo electrico: " ++ intercalate ", " [m ++ " " ++ show k ++ " kW" | (m, k) <- kws]
  Corte afecta nota -> "Corte de energia en " ++ intercalate ", " afecta ++ (if null nota then "" else ". " ++ nota)
  Restablecido -> "Energia restablecida"
  Mensaje h dicho t -> "Radio, " ++ dicho ++ maybe "" (\p -> " (" ++ nombreDe ref p ++ ")") h ++ ": " ++ t
  Nota a t -> "Bitacora" ++ maybe "" (\p -> " de " ++ nombreDe ref p) a ++ ": " ++ t
  where
    titular t = maybe "" (\p -> " (" ++ perNombre p ++ ")") (find ((== t) . perTarjeta) (refPersonas ref))

problema :: Problema -> Json
problema p =
  JObjeto
    [ ("registro", JNum (fromIntegral (prRegistro p)))
    , ("fuente", JTexto (prFuente p))
    , ("tipo", JTexto (tipoProblema (prTipo p)))
    , ("motivo", JTexto (prMotivo p))
    , ("usado", JBool (prUsado p))
    ]

tipoProblema :: TipoProblema -> String
tipoProblema t = case t of
  Corrupto -> "corrupto"
  Duplicado -> "duplicado"
  AliasUsado -> "alias"
  Formato -> "formato"
  Contradiccion -> "contradiccion"
  Descartado -> "descartado"

deducciones :: Integracion -> [Json]
deducciones i =
  [ JObjeto
      [ ("evento", JTexto (deEvento d))
      , ("tipo", JTexto "declaracion")
      , ("ts", numeroJ (deTs d))
      , ("persona", JTexto (deSujeto d))
      , ("modulo", JTexto (deModulo d))
      , ("descripcion", JTexto (frase d))
      ]
  | d <- inDeclaraciones i
  ]
    ++ [ JObjeto
           [ ("evento", JTexto (opEvento o))
           , ("tipo", JTexto "oyo_puerta")
           , ("persona", JTexto (opTestigo o))
           , ("descripcion", JTexto (nombre (opTestigo o) ++ " dice que oyo la puerta " ++ opPuerta o ++ momento (opMomento o)))
           ]
       | o <- inOidos i
       ]
    ++ [ JObjeto
           [ ("evento", JTexto (tpEvento p))
           , ("tipo", JTexto "tarjeta_perdida")
           , ("ts", numeroJ (tpTs p))
           , ("descripcion", JTexto ("La tarjeta " ++ tpTarjeta p ++ " se reporto perdida"))
           ]
       | p <- inPerdidas i
       ]
  where
    nombre = nombreDe (inReferencia i)
    frase d = case deTipo d of
      Propia -> nombre (deDeclarante d) ++ " dice estar en " ++ deModulo d ++ " a las " ++ horaCorta (deTs d)
      Testimonio -> nombre (deDeclarante d) ++ " dice que " ++ nombre (deSujeto d) ++ " estaba en " ++ deModulo d ++ " a las " ++ horaCorta (deTs d)
    momento DuranteCorte = " durante el corte"
    momento (EnHora t) = " a las " ++ horaCorta t

-- Hechos para Prolog

aProlog :: Integracion -> String
aProlog i =
  unlines $
    [ ":- encoding(utf8)."
    , ":- dynamic persona/3, acceso/2, modulo/1, puerta/4, paso/8, presencia/4, sensores_apagados/2,"
    , "   temperatura/4, corte/4, mensaje/5, declaracion/7, oyo_puerta/4, tarjeta_perdida/4."
    , ""
    ]
      ++ [hecho "persona" [atomo (perId p), cita (perNombre p), cita (perTarjeta p)] | p <- personas]
      ++ [hecho "acceso" [cita (perTarjeta p), cita a] | p <- personas, a <- perAccesos p]
      ++ [hecho "modulo" [cita m] | m <- modulos]
      ++ [hecho "puerta" [cita (puCodigo p), cita (puModulo1 p), cita (puModulo2 p), if puLector p then "con_lector" else "sin_lector"] | p <- refPuertas ref]
      ++ [hecho "paso" [cita (evId e), show (evTs e), show (evPrecision e), cita t, cita p, cita d, cita h, if r == Ok then "ok" else "denegado"] | e <- es, Paso t p d h r <- [evDato e]]
      ++ [hecho "presencia" [cita (evId e), show (evTs e), cita m, show n] | e <- es, Presencia m n <- [evDato e]]
      ++ [hecho "sensores_apagados" [cita (evId e), show (evTs e)] | e <- es, SensoresApagados <- [evDato e]]
      ++ [hecho "temperatura" [cita (evId e), show (evTs e), cita m, show c] | e <- es, Temperatura m c <- [evDato e]]
      ++ [hecho "corte" [cita (ciEvento c), show (ciInicio c), maybe "9999999999" show (ciFin c), "[" ++ intercalate "," (map cita (ciAfecta c)) ++ "]"] | c <- inCortes i]
      ++ [hecho "mensaje" [cita (evId e), show (evTs e), show (evPrecision e), maybe "desconocido" atomo h, cita t] | e <- es, Mensaje h _ t <- [evDato e]]
      ++ [hecho "declaracion" [cita (deEvento d), show (deTs d), show (dePrecision d), atomo (deDeclarante d), atomo (deSujeto d), cita (deModulo d), if deTipo d == Propia then "propia" else "testimonio"] | d <- inDeclaraciones i]
      ++ [hecho "oyo_puerta" [cita (opEvento o), atomo (opTestigo o), cita (opPuerta o), momentoP (opMomento o)] | o <- inOidos i]
      ++ [hecho "tarjeta_perdida" [cita (tpEvento p), show (tpTs p), show (tpPrecision p), cita (tpTarjeta p)] | p <- inPerdidas i]
  where
    ref = inReferencia i
    personas = refPersonas ref
    es = inEventos i
    modulos = ["COM", "DOR", "LAB-A", "LAB-B", "GEN", "RAD", "ALM", "EXT"]
    momentoP DuranteCorte = "durante_corte"
    momentoP (EnHora t) = "hora(" ++ show t ++ ")"

hecho :: String -> [String] -> String
hecho nombre args = nombre ++ "(" ++ intercalate ", " args ++ ")."

cita :: String -> String
cita s = "'" ++ concatMap esc s ++ "'"
  where
    esc '\'' = "\\'"
    esc '\\' = "\\\\"
    esc c = [c]

atomo :: String -> String
atomo = cita
