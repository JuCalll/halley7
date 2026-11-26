module Declaraciones (deducir) where

import Data.List (find, isInfixOf, isPrefixOf, tails)
import Fuentes (limpiar)
import Identidad
import Tiempo
import Tipos

-- Vocabulario

lugares :: [([String], Modulo)]
lugares =
  [ (["radio"], "RAD")
  , (["generadores"], "GEN")
  , (["comedor"], "COM")
  , (["dormitorios"], "DOR")
  , (["almacen"], "ALM")
  , (["el", "b"], "LAB-B")
  , (["laboratorio", "b"], "LAB-B")
  , (["laboratorio", "a"], "LAB-A")
  ]

primeraPersona :: [String]
primeraPersona = ["aqui", "escribo", "estoy", "sigo"]

verbosDeLugar :: [String]
verbosDeLugar = ["sigue", "esta", "deje", "dejo", "quedo"]

numerosHora :: [(String, Integer)]
numerosHora = zip ["una", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce"] [1 ..]

-- Recorrido de los textos

data Estado = Estado
  { esDeclaraciones :: [Declaracion]
  , esOidos :: [OyoPuerta]
  , esPerdidas :: [TarjetaPerdida]
  , esUltimo :: Maybe PersonaId
  }

deducir :: Referencia -> [Evento] -> ([Declaracion], [OyoPuerta], [TarjetaPerdida])
deducir ref eventos = (reverse (esDeclaraciones final), reverse (esOidos final), reverse (esPerdidas final))
  where
    final = foldl (leerEvento ref) (Estado [] [] [] Nothing) eventos

leerEvento :: Referencia -> Estado -> Evento -> Estado
leerEvento ref est e = case evDato e of
  Mensaje (Just quien) _ txt -> foldl (leerOracion ref e quien True) est (oraciones txt)
  Nota (Just quien) txt -> foldl (leerOracion ref e quien False) est (oraciones txt)
  _ -> est

oraciones :: String -> [String]
oraciones s = filter (not . null) (map limpiar (partir s))
  where
    partir txt = case break (`elem` ".?!") txt of
      (a, []) -> [a]
      (a, _ : r) -> a : partir r

leerOracion :: Referencia -> Evento -> PersonaId -> Bool -> Estado -> String -> Estado
leerOracion ref e quien esRadio est oracion =
  est
    { esDeclaraciones = maybe id (:) declaracion (esDeclaraciones est)
    , esOidos = maybe id (:) oido (esOidos est)
    , esPerdidas = maybe id (:) perdida (esPerdidas est)
    , esUltimo = if null otros then esUltimo est else Just (last otros)
    }
  where
    ws = palabras oracion
    als = refAlias ref
    vocativo = if esRadio then fmap alPersona (resolverNombre als (takeWhile (/= ',') oracion)) else Nothing
    otros = [alPersona a | a <- menciones als oracion, Just (alPersona a) /= vocativo, alPersona a /= quien]
    lugar = buscarLugar ws
    (ts, prec) = case horaHablada ws of
      Just (h, mi) -> (aSegundos (diaDe (evTs e)) h mi 0, 300)
      Nothing -> (evTs e, evPrecision e)
    tieneVerbo = any (`elem` verbosDeLugar) ws
    sujetoTercero = case otros of
      (p : _) -> Just p
      []
        | take 1 ws `elem` [["la"], ["lo"]] -> esUltimo est
        | otherwise -> Nothing
    declaracion = case lugar of
      Nothing -> Nothing
      Just m
        | tieneVerbo, Just s <- sujetoTercero -> Just (Declaracion (evId e) ts prec quien s m Testimonio)
        | any (`elem` primeraPersona) ws -> Just (Declaracion (evId e) ts prec quien quien m Propia)
        | otherwise -> Nothing
    puertaExterior = fmap puCodigo (find (\p -> "EXT" `elem` [puModulo1 p, puModulo2 p]) (refPuertas ref))
    oido
      | ["puerta", "exterior"] `isInfixOf` ws && any (`elem` ["escuche", "oi", "senti"]) ws
      , Just p <- puertaExterior =
          Just (OyoPuerta (evId e) quien p (if ["durante", "el", "corte"] `isInfixOf` ws then DuranteCorte else EnHora (evTs e)))
      | otherwise = Nothing
    perdida
      | "perdio" `elem` ws && "tarjeta" `elem` ws
      , Just p <- find ((== maybe quien id (sujetoDe otros)) . perId) (refPersonas ref) =
          Just (TarjetaPerdida (evId e) (evTs e) (evPrecision e) (perTarjeta p))
      | otherwise = Nothing
    sujetoDe (p : _) = Just p
    sujetoDe [] = Nothing

buscarLugar :: [String] -> Maybe Modulo
buscarLugar ws =
  case [m | t <- tails ws, (clave, m) <- lugares, clave `isPrefixOf` t] of
    (m : _) -> Just m
    [] -> Nothing

horaHablada :: [String] -> Maybe (Integer, Integer)
horaHablada ws =
  case [t | t <- tails ws, take 1 t == ["a"], take 1 (drop 1 t) `elem` [["la"], ["las"]]] of
    (t : _) -> do
      h <- lookup (concat (take 1 (drop 2 t))) numerosHora
      let resto = take 2 (drop 3 t)
      Just $ case resto of
        ["y", "media"] -> (h, 30)
        ["y", "cuarto"] -> (h, 15)
        ["menos", "cuarto"] -> (h - 1, 45)
        _ -> (h, 0)
    [] -> Nothing

diaDe :: Segundos -> (Integer, Integer, Integer)
diaDe t = case take 10 (isoUtc t) of
  [a1, a2, a3, a4, _, m1, m2, _, d1, d2] -> (read [a1, a2, a3, a4], read [m1, m2], read [d1, d2])
  _ -> fechaCaso
