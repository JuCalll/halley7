module Integracion (integrar) where

import Data.List (find, isInfixOf, sortBy)
import Data.Ord (comparing)
import Declaraciones
import Fuentes
import Identidad
import Tiempo
import Tipos

-- Linea de tiempo

integrar :: Modo -> [Correccion] -> [Registro] -> Integracion
integrar modo correcciones registros =
  Integracion ref eventos (ordenarProblemas (map conFuente todos)) decls oidos perdidas cortes
  where
    conFuente p
      | prFuente p == "" = p {prFuente = maybe "" regFuente (find ((== prRegistro p) . regId) registros)}
      | otherwise = p
    (ref, probRef) = leerReferencia registros
    cx = contexto ref registros
    ordenados = sortBy (comparing regId) registros
    (unicos, probDup) = separarDuplicados ordenados
    lecturas = map (leerRegistro cx) unicos
    eventosLeidos = concatMap fst lecturas
    probLectura = concatMap snd lecturas
    (eventosCorregidos, probCor) = case modo of
      Original -> (eventosLeidos, [])
      Corregida -> aplicarCorrecciones correcciones eventosLeidos
    eventos = sortBy (comparing (\e -> (evTs e, evRegistro e, evId e))) eventosCorregidos
    cortes = emparejarCortes eventos
    (decls, oidos, perdidas) = deducir ref eventos
    todos = probRef ++ probDup ++ probLectura ++ probCor ++ contradicciones ref eventos cortes perdidas

ordenarProblemas :: [Problema] -> [Problema]
ordenarProblemas = sortBy (comparing prRegistro)

-- Duplicados

conDuplicados :: [String]
conDuplicados = ["tarjetas", "presencia", "temperatura", "radio", "bitacora"]

separarDuplicados :: [Registro] -> ([Registro], [Problema])
separarDuplicados = go [] [] []
  where
    go _ us ps [] = (reverse us, reverse ps)
    go vistos us ps (r : rs)
      | regFuente r `elem` conDuplicados && limpiar (regTexto r) /= ""
      , Just original <- lookup (clave r) vistos =
          go vistos us (Problema (regId r) (regFuente r) Duplicado ("duplicado exacto del registro R" ++ show original) False : ps) rs
      | otherwise = go ((clave r, regId r) : vistos) (r : us) ps rs
    clave r = (regFuente r, limpiar (regTexto r))

-- Correcciones

aplicarCorrecciones :: [Correccion] -> [Evento] -> ([Evento], [Problema])
aplicarCorrecciones cs es = (map desfasar (filter (not . descartado) es), descartes)
  where
    descartes =
      [ Problema n "" Descartado ("descartado por la correccion C" ++ show i ++ ": " ++ m) False
      | Descartar i n m <- cs
      ]
    descartado e = evRegistro e `elem` [n | Descartar _ n _ <- cs]
    desfasar e = e {evTs = evTs e + sum [s | DesfaseReloj _ f p s <- cs, f == evFuente e, aplica p e]}
    aplica Nothing _ = True
    aplica (Just p) e = case evDato e of
      Paso {daPuerta = q} -> p == q
      Temperatura {daModulo = m} -> p == m
      _ -> False

-- Cortes de energia

emparejarCortes :: [Evento] -> [CorteIntervalo]
emparejarCortes es =
  [ CorteIntervalo (evId e) (evTs e) (fin (evTs e)) afecta
  | e <- es
  , Corte afecta _ <- [evDato e]
  ]
  where
    fin t = case [evTs r | r <- es, Restablecido <- [evDato r], evTs r > t] of
      (x : _) -> Just x
      [] -> Nothing

enCorte :: [CorteIntervalo] -> Segundos -> Bool
enCorte cs t = any (\c -> t >= ciInicio c && maybe True (t <=) (ciFin c)) cs

-- Contradicciones

contradicciones :: Referencia -> [Evento] -> [CorteIntervalo] -> [TarjetaPerdida] -> [Problema]
contradicciones ref es cortes perdidas =
  concatMap revisar es ++ sumasDePresencia
  where
    personas = refPersonas ref
    contra e m = Problema (evRegistro e) (evFuente e) Contradiccion m True
    revisar e = case evDato e of
      Paso tarjeta puerta _ _ resultado ->
        [ contra e ("la tarjeta " ++ tarjeta ++ " se reporto perdida (" ++ tpEvento p ++ ") y se uso a las " ++ horaCorta (evTs e) ++ ": no se puede atribuir a su titular")
        | resultado == Ok
        , p <- take 1 [p | p <- perdidas, tpTarjeta p == tarjeta, tpTs p - tpPrecision p <= evTs e]
        ]
          ++ [ contra e ("el lector registro un paso a las " ++ horaCorta (evTs e) ++ " durante un corte de energia")
             | enCorte cortes (evTs e)
             ]
          ++ [ contra e ("la tarjeta " ++ tarjeta ++ " abrio " ++ puerta ++ " sin tener acceso")
             | resultado == Ok
             , Just per <- [personaPorTarjeta personas tarjeta]
             , puerta `notElem` perAccesos per
             ]
          ++ [ contra e ("la tarjeta " ++ tarjeta ++ " fue denegada en " ++ puerta ++ " aunque tiene acceso")
             | resultado == Denegado
             , Just per <- [personaPorTarjeta personas tarjeta]
             , puerta `elem` perAccesos per
             ]
      Presencia _ _ ->
        [ contra e ("el sensor conto personas a las " ++ horaCorta (evTs e) ++ " durante un corte de energia")
        | enCorte cortes (evTs e)
        ]
      Mensaje _ _ txt -> anuncios e (palabras txt)
      _ -> []
    anuncios e ws =
      [ contra e ("la radio anuncia el corte a las " ++ horaCorta (evTs e) ++ " y el medidor lo registro a las " ++ horaCorta t ++ " (" ++ diferencia (evTs e) t ++ ")")
      | ["se", "fue", "la", "luz"] `isInfixOf` ws
      , Just t <- [cercano (evTs e) (map ciInicio cortes)]
      , abs (evTs e - t) > 120
      ]
        ++ [ contra e ("la radio anuncia el regreso de la energia a las " ++ horaCorta (evTs e) ++ " y el medidor lo registro a las " ++ horaCorta t ++ " (" ++ diferencia (evTs e) t ++ ")")
           | ["volvio", "la", "energia"] `isInfixOf` ws || ["volvio", "la", "luz"] `isInfixOf` ws
           , Just t <- [cercano (evTs e) [f | Just f <- map ciFin cortes]]
           , abs (evTs e - t) > 120
           ]
    sumasDePresencia =
      [ Problema (evRegistro e) "presencia" Contradiccion ("a las " ++ horaCorta t ++ " los sensores suman " ++ show total ++ " personas y en la estacion hay " ++ show (length personas)) True
      | t <- unicosTs [evTs e | e <- es, Presencia _ _ <- [evDato e]]
      , let lecturas = [(e, n) | e <- es, evTs e == t, Presencia _ n <- [evDato e]]
      , let total = sum (map snd lecturas)
      , total > length personas
      , Just (e, _) <- [find (const True) lecturas]
      ]

unicosTs :: [Segundos] -> [Segundos]
unicosTs = foldr (\t acc -> if t `elem` acc then acc else t : acc) []

cercano :: Segundos -> [Segundos] -> Maybe Segundos
cercano _ [] = Nothing
cercano t ts = Just (snd (minimum [(abs (t - x), x) | x <- ts]))

diferencia :: Segundos -> Segundos -> String
diferencia a b = show (abs (a - b) `div` 60) ++ " min de diferencia"
