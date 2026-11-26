module Main (main) where

import Data.List (isInfixOf)
import Integracion
import Tiempo
import Tipos

-- Registros de prueba

reg :: Int -> String -> String -> Registro
reg i fuente texto = Registro i fuente i texto

referencia :: [Registro]
referencia =
  [ reg 1 "personal" "tarjeta,nombre,cargo,accesos"
  , reg 2 "personal" "JS-01,Tomás Okafor,Jefe de estación,P2 P3 P4 P5 P7 P8"
  , reg 7 "personal" "LP-04,Lucas Petrov,Radiooperador,P2 P5 P7"
  , reg 3 "personal" "IV-07,Irene Valcárcel,Glacióloga,P2 P3 P4"
  , reg 4 "estacion" "puerta,modulo_1,modulo_2,lector_tarjeta"
  , reg 5 "estacion" "P4,LAB-B,GEN,si"
  , reg 6 "estacion" "P7,GEN,ALM,si"
  ]

conPrueba :: [Registro] -> Integracion
conPrueba rs = integrar Original [] (referencia ++ rs)

tipos :: Integracion -> [TipoProblema]
tipos = map prTipo . inProblemas

-- Casos

casos :: [(String, Bool)]
casos =
  [ ("hora ISO a segundos", leerIso "2041-06-14T01:30:00" == Just 2254786200)
  , ("hora corrupta se rechaza", leerIso "2041-06-14T0#:4?:1?" == Nothing)
  , ( "linea duplicada se conserva como problema"
    , tipos (conPrueba [reg 10 "tarjetas" "2041-06-14T01:20:33,IV-07,P4,LAB-B,GEN,OK", reg 11 "tarjetas" "2041-06-14T01:20:33,IV-07,P4,LAB-B,GEN,OK"]) == [Duplicado]
    )
  , ( "linea corrupta no se usa y deja motivo"
    , case inProblemas (conPrueba [reg 10 "tarjetas" "2041-06-14T0#:4?:1?,AK-0?,P2,DO"]) of
        [p] -> prTipo p == Corrupto && not (prUsado p) && "4 campos de 6" `isInfixOf` prMotivo p
        _ -> False
    )
  , ( "modulo con guion bajo se normaliza"
    , tipos (conPrueba [reg 10 "presencia" "01.30;LAB_B;0"]) == [Formato]
    )
  , ( "tarjeta perdida usada es una contradiccion"
    , Contradiccion
        `elem` tipos
          ( conPrueba
              [ reg 10 "bitacora" "BITÁCORA DEL JEFE DE ESTACIÓN (manuscrita, digitalizada)"
              , reg 11 "bitacora" "12/06 - Día 4. Petrov dice que perdió su tarjeta de acceso."
              , reg 12 "tarjetas" "2041-06-14T01:39:47,LP-04,P7,GEN,ALM,OK"
              ]
          )
    )
  , ( "alias no oficial queda registrado"
    , AliasUsado `elem` tipos (conPrueba [reg 10 "radio" "TRANSCRIPCION - 14/06/2041", reg 11 "radio" "[02:31] Luka: Hola."])
    )
  , ( "la correccion de reloj mueve la hora sin tocar el original"
    , let rs = referencia ++ [reg 10 "radio" "TRANSCRIPCION - 14/06/2041", reg 11 "radio" "[01:47] Petrov: Se fue la luz."]
          corregida = integrar Corregida [DesfaseReloj 1 "radio" Nothing (-420)] rs
          original = integrar Original [DesfaseReloj 1 "radio" Nothing (-420)] rs
       in map evTs (inEventos corregida) == [aSegundos fechaCaso 1 40 0]
            && map evTs (inEventos original) == [aSegundos fechaCaso 1 47 0]
    )
  ]

main :: IO ()
main = do
  mapM_ (\(n, ok) -> putStrLn ((if ok then "[OK]    " else "[FALLA] ") ++ n)) casos
  putStrLn (show (length (filter snd casos)) ++ " de " ++ show (length casos) ++ " pruebas correctas.")
