module Main (main) where

import Integracion
import Json
import Salida
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO
import Tipos

-- Entrada

ordenArchivos :: [(String, String)]
ordenArchivos =
  [ ("personal", "personal.csv")
  , ("estacion", "estacion.csv")
  , ("tarjetas", "tarjetas.csv")
  , ("radio", "radio.txt")
  , ("energia", "energia.json")
  , ("presencia", "presencia.csv")
  , ("temperatura", "temperatura.csv")
  , ("bitacora", "bitacora.txt")
  ]

registrosDeArchivos :: [(String, String)] -> [Registro]
registrosDeArchivos contenidos = zipWith numerar [1 ..] (concatMap partir contenidos)
  where
    partir ("energia", txt) = [("energia", 1, txt)]
    partir (fuente, txt) = zipWith (\n l -> (fuente, n, l)) [1 ..] (lines txt)
    numerar i (f, n, t) = Registro i f n t

leerPeticion :: Json -> Either String (Modo, [Correccion], [Registro])
leerPeticion j = do
  regs <- maybe (Left "falta 'registros'") Right (campo "registros" j >>= lista)
  rs <- mapM registro regs
  cs <- mapM correccion (maybe [] id (campo "correcciones" j >>= lista))
  let modo = if (campo "modo" j >>= texto) == Just "corregida" then Corregida else Original
  Right (modo, cs, rs)
  where
    registro r = maybe (Left "registro invalido") Right $ do
      i <- campo "id" r >>= entero
      f <- campo "fuente" r >>= texto
      n <- campo "num" r >>= entero
      t <- campo "texto" r >>= texto
      Just (Registro (fromIntegral i) f (fromIntegral n) t)
    correccion c = maybe (Left "correccion invalida") Right $ do
      i <- campo "id" c >>= entero
      tipo <- campo "tipo" c >>= texto
      case tipo of
        "desfase_reloj" -> do
          f <- campo "fuente" c >>= texto
          s <- campo "segundos" c >>= entero
          Just (DesfaseReloj (fromIntegral i) f (campo "dispositivo" c >>= texto) s)
        "descartar" -> do
          n <- campo "registro" c >>= entero
          Just (Descartar (fromIntegral i) (fromIntegral n) (maybe "" id (campo "motivo" c >>= texto)))
        _ -> Nothing

-- Main

main :: IO ()
main = do
  hSetEncoding stdin utf8
  hSetEncoding stdout utf8
  args <- getArgs
  case args of
    ("--archivos" : dir : resto) -> do
      contenidos <- mapM (\(f, a) -> fmap (\t -> (f, t)) (leerUtf8 (dir ++ "/" ++ a))) ordenArchivos
      let modo = if "--corregida" `elem` resto then Corregida else Original
          resultado = integrar modo [] (registrosDeArchivos contenidos)
      if "--prolog" `elem` resto
        then putStr (aProlog resultado)
        else putStrLn (mostrar (aJson resultado))
    _ -> do
      entrada <- getContents
      case parsear entrada >>= leerPeticion of
        Left err -> hPutStrLn stderr ("integrador: " ++ err) >> exitFailure
        Right (modo, cs, rs) -> putStrLn (mostrar (aJson (integrar modo cs rs)))

leerUtf8 :: FilePath -> IO String
leerUtf8 ruta = do
  h <- openFile ruta ReadMode
  hSetEncoding h utf8
  t <- hGetContents h
  length t `seq` hClose h
  return t
