module Tipos where

import Tiempo (Segundos)

-- Entrada

type PersonaId = String

type Modulo = String

data Registro = Registro
  { regId :: Int
  , regFuente :: String
  , regNum :: Int
  , regTexto :: String
  }
  deriving (Show, Eq)

data Modo = Original | Corregida
  deriving (Show, Eq)

data Correccion
  = DesfaseReloj {corId :: Int, corFuente :: String, corPuerta :: Maybe String, corSegundos :: Integer}
  | Descartar {corId :: Int, corRegistro :: Int, corMotivo :: String}
  deriving (Show, Eq)

-- Referencia

data Persona = Persona
  { perId :: PersonaId
  , perNombre :: String
  , perCargo :: String
  , perTarjeta :: String
  , perAccesos :: [String]
  }
  deriving (Show, Eq)

data Puerta = Puerta
  { puCodigo :: String
  , puModulo1 :: Modulo
  , puModulo2 :: Modulo
  , puLector :: Bool
  }
  deriving (Show, Eq)

data Alias = Alias
  { alTexto :: [String]
  , alPersona :: PersonaId
  , alOficial :: Bool
  , alNota :: String
  }
  deriving (Show, Eq)

data Referencia = Referencia
  { refPersonas :: [Persona]
  , refPuertas :: [Puerta]
  , refAlias :: [Alias]
  }
  deriving (Show, Eq)

-- Evidencia

data Resultado = Ok | Denegado
  deriving (Show, Eq)

data Dato
  = Paso {daTarjeta :: String, daPuerta :: String, daDesde :: Modulo, daHacia :: Modulo, daResultado :: Resultado}
  | Presencia {daModulo :: Modulo, daPersonas :: Int}
  | SensoresApagados
  | Temperatura {daModulo :: Modulo, daCelsius :: Double}
  | Consumo [(Modulo, Double)]
  | Corte {daAfecta :: [Modulo], daNota :: String}
  | Restablecido
  | Mensaje {daHablante :: Maybe PersonaId, daNombreDicho :: String, daTexto :: String}
  | Nota {daAutor :: Maybe PersonaId, daTexto :: String}
  deriving (Show, Eq)

data Evento = Evento
  { evId :: String
  , evRegistro :: Int
  , evFuente :: String
  , evTs :: Segundos
  , evPrecision :: Segundos
  , evDato :: Dato
  }
  deriving (Show, Eq)

data TipoProblema = Corrupto | Duplicado | AliasUsado | Formato | Contradiccion | Descartado
  deriving (Show, Eq)

data Problema = Problema
  { prRegistro :: Int
  , prFuente :: String
  , prTipo :: TipoProblema
  , prMotivo :: String
  , prUsado :: Bool
  }
  deriving (Show, Eq)

-- Hechos deducidos de los textos

data TipoDeclaracion = Propia | Testimonio
  deriving (Show, Eq)

data Declaracion = Declaracion
  { deEvento :: String
  , deTs :: Segundos
  , dePrecision :: Segundos
  , deDeclarante :: PersonaId
  , deSujeto :: PersonaId
  , deModulo :: Modulo
  , deTipo :: TipoDeclaracion
  }
  deriving (Show, Eq)

data Momento = DuranteCorte | EnHora Segundos
  deriving (Show, Eq)

data OyoPuerta = OyoPuerta
  { opEvento :: String
  , opTestigo :: PersonaId
  , opPuerta :: String
  , opMomento :: Momento
  }
  deriving (Show, Eq)

data TarjetaPerdida = TarjetaPerdida
  { tpEvento :: String
  , tpTs :: Segundos
  , tpPrecision :: Segundos
  , tpTarjeta :: String
  }
  deriving (Show, Eq)

data CorteIntervalo = CorteIntervalo
  { ciEvento :: String
  , ciInicio :: Segundos
  , ciFin :: Maybe Segundos
  , ciAfecta :: [Modulo]
  }
  deriving (Show, Eq)

-- Salida

data Integracion = Integracion
  { inReferencia :: Referencia
  , inEventos :: [Evento]
  , inProblemas :: [Problema]
  , inDeclaraciones :: [Declaracion]
  , inOidos :: [OyoPuerta]
  , inPerdidas :: [TarjetaPerdida]
  , inCortes :: [CorteIntervalo]
  }
  deriving (Show, Eq)
