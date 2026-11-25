module Tiempo
  ( Segundos
  , fechaCaso
  , aSegundos
  , leerIso
  , leerHoraMinuto
  , leerDiaMes
  , isoUtc
  , horaCorta
  ) where

import Data.Char (isDigit)

-- Tipo

type Segundos = Integer

fechaCaso :: (Integer, Integer, Integer)
fechaCaso = (2041, 6, 14)

-- Calendario

diasDesde1970 :: Integer -> Integer -> Integer -> Integer
diasDesde1970 a m d = era * 146097 + diaEra - 719468
  where
    a' = if m <= 2 then a - 1 else a
    era = (if a' >= 0 then a' else a' - 399) `div` 400
    anioEra = a' - era * 400
    mesDesdeMarzo = (m + 9) `mod` 12
    diaAnio = (153 * mesDesdeMarzo + 2) `div` 5 + d - 1
    diaEra = anioEra * 365 + anioEra `div` 4 - anioEra `div` 100 + diaAnio

civilDesde :: Integer -> (Integer, Integer, Integer)
civilDesde dias = (if m <= 2 then a + 1 else a, m, d)
  where
    z = dias + 719468
    era = (if z >= 0 then z else z - 146096) `div` 146097
    doe = z - era * 146097
    yoe = (doe - doe `div` 1460 + doe `div` 36524 - doe `div` 146096) `div` 365
    a = yoe + era * 400
    doy = doe - (365 * yoe + yoe `div` 4 - yoe `div` 100)
    mp = (5 * doy + 2) `div` 153
    d = doy - (153 * mp + 2) `div` 5 + 1
    m = if mp < 10 then mp + 3 else mp - 9

aSegundos :: (Integer, Integer, Integer) -> Integer -> Integer -> Integer -> Segundos
aSegundos (a, m, d) h mi s = diasDesde1970 a m d * 86400 + h * 3600 + mi * 60 + s

-- Lectura

numeroEn :: Int -> Int -> String -> Maybe Integer
numeroEn desde largo txt =
  let parte = take largo (drop desde txt)
   in if length parte == largo && all isDigit parte then Just (read parte) else Nothing

leerIso :: String -> Maybe Segundos
leerIso txt
  | length txt == 19 && txt !! 4 == '-' && txt !! 7 == '-' && txt !! 10 == 'T'
      && txt !! 13 == ':' && txt !! 16 == ':' = do
      a <- numeroEn 0 4 txt
      m <- numeroEn 5 2 txt
      d <- numeroEn 8 2 txt
      h <- numeroEn 11 2 txt
      mi <- numeroEn 14 2 txt
      s <- numeroEn 17 2 txt
      valida a m d h mi s
  | otherwise = Nothing

valida :: Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Maybe Segundos
valida a m d h mi s
  | m >= 1 && m <= 12 && d >= 1 && d <= 31 && h < 24 && mi < 60 && s < 60 = Just (aSegundos (a, m, d) h mi s)
  | otherwise = Nothing

leerHoraMinuto :: Char -> String -> Maybe (Integer, Integer)
leerHoraMinuto sep txt
  | length txt == 5 && txt !! 2 == sep = do
      h <- numeroEn 0 2 txt
      mi <- numeroEn 3 2 txt
      if h < 24 && mi < 60 then Just (h, mi) else Nothing
  | otherwise = Nothing

leerDiaMes :: String -> Maybe (Integer, Integer)
leerDiaMes txt
  | length txt >= 5 && txt !! 2 == '/' = do
      d <- numeroEn 0 2 txt
      m <- numeroEn 3 2 txt
      if d >= 1 && d <= 31 && m >= 1 && m <= 12 then Just (d, m) else Nothing
  | otherwise = Nothing

-- Escritura

dosDigitos :: Integer -> String
dosDigitos n = if n < 10 then '0' : show n else show n

isoUtc :: Segundos -> String
isoUtc t =
  show a ++ "-" ++ dosDigitos m ++ "-" ++ dosDigitos d ++ "T" ++ horaCorta t ++ "Z"
  where
    (a, m, d) = civilDesde (t `div` 86400)

horaCorta :: Segundos -> String
horaCorta t = dosDigitos h ++ ":" ++ dosDigitos mi ++ ":" ++ dosDigitos s
  where
    r = t `mod` 86400
    h = r `div` 3600
    mi = (r `mod` 3600) `div` 60
    s = r `mod` 60
