module Identidad
  ( normalizar
  , palabras
  , construirAlias
  , resolverNombre
  , menciones
  , personaPorTarjeta
  , modulosConocidos
  , normalizarModulo
  ) where

import Data.Char (isAlphaNum, toLower)
import Data.List (isPrefixOf, sortBy)
import Data.Ord (Down (..), comparing)
import Tipos

-- Texto

normalizar :: String -> String
normalizar = map (quitarTilde . toLower)

quitarTilde :: Char -> Char
quitarTilde c = maybe c id (lookup c tabla)
  where
    tabla = zip "áéíóúüñÁÉÍÓÚÜÑ" "aeiouunaeiouun"

palabras :: String -> [String]
palabras txt = filter (not . null) (partir (map separar (normalizar txt)))
  where
    separar c = if isAlphaNum c || c == '-' then c else ' '
    partir s = case break (== ' ') s of
      (p, []) -> [p]
      (p, _ : r) -> p : partir r

-- Alias

construirAlias :: [Persona] -> [Alias]
construirAlias ps = concatMap oficiales ps ++ concatMap porCargo ps ++ extras
  where
    oficiales p =
      [ Alias (palabras (perNombre p)) (perId p) True "nombre completo"
      , Alias (take 1 (palabras (perNombre p))) (perId p) True "nombre"
      , Alias [perId p] (perId p) True "apellido"
      , Alias (palabras (perTarjeta p)) (perId p) True "tarjeta"
      ]
    porCargo p =
      [ Alias (take 1 (palabras (perCargo p))) (perId p) False ("cargo: " ++ perCargo p)
      | perCargo p /= ""
      ]
    extras =
      [ Alias ["doc"] "vidal" False "abreviatura de doctor; Daniel Vidal es el medico"
      , Alias ["el", "doc"] "vidal" False "abreviatura de doctor; Daniel Vidal es el medico"
      , Alias ["doctora"] "valcarcel" False "la bitacora la llama 'la doctora Valcarcel'"
      , Alias ["luka"] "petrov" False "diminutivo de Lucas; no figura en personal.csv"
      ]

resolverNombre :: [Alias] -> String -> Maybe Alias
resolverNombre als nombre =
  case [a | a <- ordenados als, alTexto a == palabras nombre] of
    (a : _) -> Just a
    [] -> Nothing

ordenados :: [Alias] -> [Alias]
ordenados = sortBy (comparing (\a -> (Down (length (alTexto a)), not (alOficial a))))

menciones :: [Alias] -> String -> [Alias]
menciones als txt = recorrer (palabras txt)
  where
    candidatos = ordenados als
    recorrer [] = []
    recorrer ws@(_ : resto) =
      case [a | a <- candidatos, alTexto a `isPrefixOf` ws] of
        (a : _) -> a : recorrer (drop (length (alTexto a)) ws)
        [] -> recorrer resto

personaPorTarjeta :: [Persona] -> String -> Maybe Persona
personaPorTarjeta ps t = case filter ((== t) . perTarjeta) ps of
  (p : _) -> Just p
  [] -> Nothing

-- Modulos

modulosConocidos :: [Modulo]
modulosConocidos = ["COM", "DOR", "LAB-A", "LAB-B", "GEN", "RAD", "ALM", "EXT"]

normalizarModulo :: String -> Maybe (Modulo, Bool)
normalizarModulo m
  | m `elem` modulosConocidos = Just (m, False)
  | otherwise =
      case [k | k <- modulosConocidos, map unificar k == map unificar m] of
        (k : _) -> Just (k, True)
        [] -> Nothing
  where
    unificar c = if c == '_' || c == ' ' then '-' else toLower c
