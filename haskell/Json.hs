module Json
  ( Json (..)
  , parsear
  , mostrar
  , campo
  , texto
  , entero
  , numero
  , lista
  ) where

import Data.Char (chr, isDigit, isHexDigit, isSpace, ord)
import Numeric (readHex, showHex)

-- Tipo

data Json
  = JNulo
  | JBool Bool
  | JNum Double
  | JTexto String
  | JLista [Json]
  | JObjeto [(String, Json)]
  deriving (Show, Eq)

-- Lectura

parsear :: String -> Either String Json
parsear entrada =
  case valor (saltar entrada) of
    Right (j, resto)
      | all isSpace resto -> Right j
      | otherwise -> Left ("texto sobrante: " ++ take 20 resto)
    Left err -> Left err

type Parser a = String -> Either String (a, String)

saltar :: String -> String
saltar = dropWhile isSpace

valor :: Parser Json
valor ('n' : 'u' : 'l' : 'l' : r) = Right (JNulo, r)
valor ('t' : 'r' : 'u' : 'e' : r) = Right (JBool True, r)
valor ('f' : 'a' : 'l' : 's' : 'e' : r) = Right (JBool False, r)
valor ('"' : r) = fmap (\(s, r2) -> (JTexto s, r2)) (cadena r)
valor ('[' : r) = arreglo (saltar r) []
valor ('{' : r) = objeto (saltar r) []
valor s@(c : _)
  | c == '-' || isDigit c = numeroJson s
valor s = Left ("valor inesperado: " ++ take 20 s)

cadena :: Parser String
cadena ('"' : r) = Right ("", r)
cadena ('\\' : c : r) =
  case c of
    'n' -> seguir '\n' r
    't' -> seguir '\t' r
    'r' -> seguir '\r' r
    'b' -> seguir '\b' r
    'f' -> seguir '\f' r
    'u' ->
      let (h, r2) = splitAt 4 r
       in if length h == 4 && all isHexDigit h
            then seguir (chr (fst (head (readHex h)))) r2
            else Left "escape \\u invalido"
    _ -> seguir c r
cadena (c : r) = seguir c r
cadena [] = Left "texto sin cerrar"

seguir :: Char -> Parser String
seguir c r = fmap (\(s, r2) -> (c : s, r2)) (cadena r)

numeroJson :: Parser Json
numeroJson s =
  let (txt, resto) = span (`elem` "+-0123456789.eE") s
      normal = if take 1 txt == "-" then "-" ++ conCero (drop 1 txt) else conCero txt
      conCero t = if take 1 t == "." then '0' : t else t
   in case reads (completar normal) :: [(Double, String)] of
        [(d, "")] -> Right (JNum d, resto)
        _ -> Left ("numero invalido: " ++ txt)
  where
    completar t = if last t == '.' then t ++ "0" else t

arreglo :: String -> [Json] -> Either String (Json, String)
arreglo (']' : r) acc = Right (JLista (reverse acc), r)
arreglo s acc = do
  (j, r) <- valor (saltar s)
  case saltar r of
    ',' : r2 -> arreglo (saltar r2) (j : acc)
    ']' : r2 -> Right (JLista (reverse (j : acc)), r2)
    _ -> Left "se esperaba , o ]"

objeto :: String -> [(String, Json)] -> Either String (Json, String)
objeto ('}' : r) acc = Right (JObjeto (reverse acc), r)
objeto ('"' : s) acc = do
  (k, r) <- cadena s
  case saltar r of
    ':' : r2 -> do
      (v, r3) <- valor (saltar r2)
      case saltar r3 of
        ',' : r4 -> objeto (saltar r4) ((k, v) : acc)
        '}' : r4 -> Right (JObjeto (reverse ((k, v) : acc)), r4)
        _ -> Left "se esperaba , o }"
    _ -> Left "se esperaba :"
objeto s _ = Left ("clave invalida: " ++ take 20 s)

-- Escritura

mostrar :: Json -> String
mostrar JNulo = "null"
mostrar (JBool b) = if b then "true" else "false"
mostrar (JNum d)
  | d == fromIntegral (round d :: Integer) && abs d < 1e15 = show (round d :: Integer)
  | otherwise = show d
mostrar (JTexto s) = "\"" ++ concatMap escapar s ++ "\""
mostrar (JLista xs) = "[" ++ unirCon "," (map mostrar xs) ++ "]"
mostrar (JObjeto kvs) = "{" ++ unirCon "," [mostrar (JTexto k) ++ ":" ++ mostrar v | (k, v) <- kvs] ++ "}"

escapar :: Char -> String
escapar '"' = "\\\""
escapar '\\' = "\\\\"
escapar '\n' = "\\n"
escapar '\r' = "\\r"
escapar '\t' = "\\t"
escapar c
  | ord c < 32 = "\\u" ++ replicate (4 - length h) '0' ++ h
  | otherwise = [c]
  where
    h = showHex (ord c) ""

unirCon :: String -> [String] -> String
unirCon _ [] = ""
unirCon sep (x : xs) = x ++ concatMap (sep ++) xs

-- Acceso

campo :: String -> Json -> Maybe Json
campo k (JObjeto kvs) = lookup k kvs
campo _ _ = Nothing

texto :: Json -> Maybe String
texto (JTexto s) = Just s
texto _ = Nothing

numero :: Json -> Maybe Double
numero (JNum d) = Just d
numero _ = Nothing

entero :: Json -> Maybe Integer
entero (JNum d)
  | d == fromIntegral (round d :: Integer) = Just (round d)
entero _ = Nothing

lista :: Json -> Maybe [Json]
lista (JLista xs) = Just xs
lista _ = Nothing