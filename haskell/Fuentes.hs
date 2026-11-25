module Fuentes
  ( limpiar
  , separar
  , leerReferencia
  , leerRegistro
  , Contexto (..)
  , contexto
  ) where

import Data.Char (isDigit, isSpace)
import Data.List (find, isPrefixOf)
import Data.Maybe (mapMaybe)
import Identidad
import Json
import Tiempo
import Tipos

-- Texto

limpiar :: String -> String
limpiar = recortar . filter (\c -> c /= '\r' && c /= '\65279')
  where
    recortar = reverse . dropWhile isSpace . reverse . dropWhile isSpace

separar :: Char -> String -> [String]
separar sep s = case break (== sep) s of
  (a, []) -> [limpiar a]
  (a, _ : r) -> limpiar a : separar sep r

esEncabezado :: String -> Registro -> Bool
esEncabezado primeraColumna r = (primeraColumna ++ ",") `isPrefixOf` normalizar (limpiar (regTexto r))

-- Referencia

leerReferencia :: [Registro] -> (Referencia, [Problema])
leerReferencia regs = (Referencia personas puertas (construirAlias personas), probs1 ++ probs2)
  where
    deFuente f = [r | r <- regs, regFuente r == f, limpiar (regTexto r) /= ""]
    (personas, probs1) = juntar (map leerPersona (filter (not . esEncabezado "tarjeta") (deFuente "personal")))
    (puertas, probs2) = juntar (map leerPuerta (filter (not . esEncabezado "puerta") (deFuente "estacion")))

juntar :: [Either Problema a] -> ([a], [Problema])
juntar xs = ([a | Right a <- xs], [p | Left p <- xs])

corrupto :: Registro -> String -> Problema
corrupto r motivo = Problema (regId r) (regFuente r) Corrupto motivo False

leerPersona :: Registro -> Either Problema Persona
leerPersona r = case separar ',' (limpiar (regTexto r)) of
  [tarjeta, nombre, cargo, accesos]
    | tarjeta /= "" && nombre /= "" ->
        Right (Persona (apellido nombre) nombre cargo tarjeta (words accesos))
  campos -> Left (corrupto r ("personal: se esperaban 4 campos y hay " ++ show (length campos)))
  where
    apellido n = case palabras n of
      [] -> "desconocido"
      ws -> last ws

leerPuerta :: Registro -> Either Problema Puerta
leerPuerta r = case separar ',' (limpiar (regTexto r)) of
  [codigo, m1, m2, lector]
    | Just (a, _) <- normalizarModulo m1
    , Just (b, _) <- normalizarModulo m2 ->
        Right (Puerta codigo a b (normalizar lector == "si"))
  _ -> Left (corrupto r "estacion: linea invalida")

-- Contexto de lectura

data Contexto = Contexto
  { cxReferencia :: Referencia
  , cxFechaRadio :: (Integer, Integer, Integer)
  , cxAutorBitacora :: Maybe PersonaId
  }

contexto :: Referencia -> [Registro] -> Contexto
contexto ref regs = Contexto ref fechaRadio autor
  where
    encabezados f = [t | r <- regs, regFuente r == f, let t = limpiar (regTexto r), esEncabezadoDe f t]
    fechaRadio = case concatMap fechaEn (encabezados "radio") of
      (f : _) -> f
      [] -> fechaCaso
    autor = case encabezados "bitacora" of
      (encabezado : _) -> fmap perId (find (\p -> normalizar (perCargo p) `contenidoEn` normalizar encabezado) (refPersonas ref))
      [] -> Nothing

esEncabezadoDe :: String -> String -> Bool
esEncabezadoDe "radio" t = take 1 t /= "[" && not (null (fechaEn t))
esEncabezadoDe "bitacora" t = "bitacora" `isPrefixOf` normalizar t
esEncabezadoDe _ _ = False

contenidoEn :: String -> String -> Bool
contenidoEn aguja pajar = any (aguja `isPrefixOf`) (colas pajar)
  where
    colas [] = [[]]
    colas s@(_ : r) = s : colas r

fechaEn :: String -> [(Integer, Integer, Integer)]
fechaEn [] = []
fechaEn s@(_ : r) =
  case leerDiaMes (take 5 s) of
    Just (d, m)
      | take 1 (drop 5 s) == "/" && all isDigit (take 4 (drop 6 s)) && length (take 4 (drop 6 s)) == 4 ->
          (read (take 4 (drop 6 s)), m, d) : fechaEn r
    _ -> fechaEn r

-- Registros de evidencia

leerRegistro :: Contexto -> Registro -> ([Evento], [Problema])
leerRegistro cx r
  | limpiar (regTexto r) == "" = ([], [])
  | otherwise = case regFuente r of
      "tarjetas" -> unico (leerTarjeta cx r)
      "presencia" -> leerPresencia r
      "temperatura" -> unico (leerTemperatura r)
      "radio" -> leerRadio cx r
      "bitacora" -> unico (leerBitacora cx r)
      "energia" -> leerEnergia r
      "personal" -> ([], [])
      "estacion" -> ([], [])
      otra -> ([], [corrupto r ("fuente desconocida: " ++ otra)])
  where
    unico (Left Nothing) = ([], [])
    unico (Left (Just p)) = ([], [p])
    unico (Right (e, ps)) = ([e], ps)

evento :: Registro -> Segundos -> Segundos -> Dato -> Evento
evento r = Evento ("R" ++ show (regId r)) (regId r) (regFuente r)

leerTarjeta :: Contexto -> Registro -> Either (Maybe Problema) (Evento, [Problema])
leerTarjeta cx r
  | esEncabezado "fecha_hora" r = Left Nothing
  | otherwise =
      case (errores, campos) of
        ([], [f, t, p, d, h, res]) ->
          case (leerIso f, normalizarModulo d, normalizarModulo h) of
            (Just ts, Just (desde, _), Just (hacia, _)) ->
              Right (evento r ts 0 (Paso t p desde hacia (if res == "OK" then Ok else Denegado)), [])
            _ -> Left (Just (corrupto r "campos ilegibles"))
        _ -> Left (Just (corrupto r (unirMotivos errores)))
  where
    ref = cxReferencia cx
    campos = separar ',' (limpiar (regTexto r))
    errores = case campos of
      [f, t, p, d, h, res] ->
        [ "fecha_hora ilegible '" ++ f ++ "'" | leerIso f == Nothing ]
          ++ [ "tarjeta desconocida '" ++ t ++ "'" | personaPorTarjeta (refPersonas ref) t == Nothing ]
          ++ [ "puerta desconocida '" ++ p ++ "'" | Nothing <- [puertaDe p] ]
          ++ [ "los modulos " ++ d ++ " y " ++ h ++ " no son los de la puerta " ++ p
             | Just pu <- [puertaDe p]
             , not (conecta pu d h)
             ]
          ++ [ "resultado desconocido '" ++ res ++ "'" | res `notElem` ["OK", "DENEGADO"] ]
      _ ->
        [ "tiene " ++ show (length campos) ++ " campos de 6" ]
          ++ [ "fecha_hora ilegible '" ++ f ++ "'" | (f : _) <- [campos], leerIso f == Nothing ]
          ++ [ "tarjeta ilegible '" ++ t ++ "'" | (_ : t : _) <- [campos], personaPorTarjeta (refPersonas ref) t == Nothing ]
    puertaDe p = find ((== p) . puCodigo) (refPuertas ref)
    conecta pu a b = (puModulo1 pu, puModulo2 pu) `elem` [(a, b), (b, a)]

unirMotivos :: [String] -> String
unirMotivos [] = ""
unirMotivos (m : ms) = m ++ concatMap ("; " ++) ms

leerPresencia :: Registro -> ([Evento], [Problema])
leerPresencia r
  | normalizar (limpiar (regTexto r)) == "hora;modulo;personas" = ([], [])
  | otherwise =
      case separar ';' (limpiar (regTexto r)) of
        [hora, "*", "SIN_ENERGIA"]
          | Just (h, mi) <- leerHoraMinuto '.' hora ->
              ([evento r (aSegundos fechaCaso h mi 0) 0 SensoresApagados], [])
        [hora, modulo, personas]
          | Just (h, mi) <- leerHoraMinuto '.' hora
          , Just (m, corregido) <- normalizarModulo modulo
          , not (null personas) && all isDigit personas ->
              ( [evento r (aSegundos fechaCaso h mi 0) 0 (Presencia m (read personas))]
              , [ Problema (regId r) "presencia" Formato ("modulo '" ++ modulo ++ "' normalizado a '" ++ m ++ "'") True
                | corregido
                ]
              )
        campos -> ([], [corrupto r ("presencia ilegible (" ++ show (length campos) ++ " campos)")])

leerTemperatura :: Registro -> Either (Maybe Problema) (Evento, [Problema])
leerTemperatura r
  | esEncabezado "epoch" r = Left Nothing
  | otherwise =
      case separar ',' (limpiar (regTexto r)) of
        [e, sensor, c]
          | all isDigit e && not (null e)
          , Just m <- sensorModulo sensor
          , [(grados, "")] <- (reads c :: [(Double, String)]) ->
              Right (evento r (read e) 0 (Temperatura m grados), [])
        _ -> Left (Just (corrupto r "temperatura ilegible"))
  where
    sensorModulo s
      | "T-" `isPrefixOf` s = fmap fst (normalizarModulo (drop 2 s))
      | otherwise = Nothing

leerRadio :: Contexto -> Registro -> ([Evento], [Problema])
leerRadio cx r
  | esEncabezadoDe "radio" (limpiar (regTexto r)) = ([], [])
  | otherwise =
      case limpiar (regTexto r) of
        ('[' : resto)
          | (hora, ']' : ' ' : cuerpo) <- break (== ']') resto
          , Just (h, mi) <- leerHoraMinuto ':' hora
          , (quien, ':' : dicho) <- break (== ':') cuerpo ->
              let als = refAlias (cxReferencia cx)
                  hablante = resolverNombre als quien
                  ts = aSegundos (cxFechaRadio cx) h mi 0
                  e = evento r ts 60 (Mensaje (fmap alPersona hablante) quien (limpiar dicho))
               in ([e], problemasDeNombre r quien hablante ++ problemasDeMencion r als dicho)
        _ -> ([], [corrupto r "linea de radio ilegible"])

problemasDeNombre :: Registro -> String -> Maybe Alias -> [Problema]
problemasDeNombre r quien Nothing = [Problema (regId r) (regFuente r) AliasUsado ("hablante no identificado '" ++ quien ++ "'") True]
problemasDeNombre r quien (Just a)
  | alOficial a = []
  | otherwise = [Problema (regId r) (regFuente r) AliasUsado ("'" ++ quien ++ "' se identifico como " ++ alPersona a ++ " (" ++ alNota a ++ ")") True]

problemasDeMencion :: Registro -> [Alias] -> String -> [Problema]
problemasDeMencion r als dicho =
  [ Problema (regId r) (regFuente r) AliasUsado ("'" ++ unwords (alTexto a) ++ "' se identifico como " ++ alPersona a ++ " (" ++ alNota a ++ ")") True
  | a <- menciones als dicho
  , not (alOficial a)
  ]

leerBitacora :: Contexto -> Registro -> Either (Maybe Problema) (Evento, [Problema])
leerBitacora cx r
  | esEncabezadoDe "bitacora" linea = Left Nothing
  | otherwise =
      case leerDiaMes (take 5 linea) of
        Nothing -> Left (Just (corrupto r "entrada de bitacora sin fecha DD/MM"))
        Just (d, m) ->
          let (a, _, _) = fechaCaso
              despuesDia = dropWhile (/= ',') (takeWhile (/= '.') (drop 5 linea))
              (hora, aprox) = case words (drop 1 despuesDia) of
                (hm : resto) | Just x <- leerHoraMinuto ':' hm -> (Just x, take 1 resto == ["aprox"])
                _ -> (Nothing, False)
              textoNota = limpiar (drop 1 (dropWhile (/= '.') (dropWhile (/= '-') (drop 5 linea))))
              (ts, prec) = case hora of
                Just (h, mi) -> (aSegundos (a, m, d) h mi 0, if aprox then 600 else 60)
                Nothing -> (aSegundos (a, m, d) 12 0 0, 43200)
              e = evento r ts prec (Nota (cxAutorBitacora cx) textoNota)
           in Right (e, problemasDeMencion r (refAlias (cxReferencia cx)) textoNota)
  where
    linea = limpiar (regTexto r)

leerEnergia :: Registro -> ([Evento], [Problema])
leerEnergia r =
  case parsear (regTexto r) of
    Left err -> ([], [corrupto r ("energia.json invalido: " ++ err)])
    Right doc ->
      case campo "registros" doc >>= lista of
        Nothing -> ([], [corrupto r "energia.json sin lista 'registros'"])
        Just regs ->
          let leidos = zipWith leerUno [1 :: Int ..] regs
           in ([e | Right e <- leidos], [p | Left p <- leidos])
  where
    leerUno k j =
      let idEv = "R" ++ show (regId r) ++ "." ++ show k
          ts = campo "ts" j >>= texto >>= leerIso
          tipo = campo "tipo" j >>= texto
          mk t d = Right (Evento idEv (regId r) "energia" t 0 d)
       in case (ts, tipo) of
            (Just t, Just "lectura") ->
              mk t (Consumo (maybe [] pares (campo "consumo_kw" j)))
            (Just t, Just "corte") ->
              mk t (Corte (maybe [] (mapMaybe texto) (campo "afecta" j >>= lista)) (maybe "" id (campo "nota" j >>= texto)))
            (Just t, Just "restablecido") -> mk t Restablecido
            _ -> Left (Problema (regId r) "energia" Corrupto ("elemento " ++ show k ++ " de energia.json ilegible") False)
    pares (JObjeto kvs) = [(k, v) | (k, JNum v) <- kvs]
    pares _ = []
