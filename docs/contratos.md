# Contratos entre componentes

Este documento es la referencia común del equipo. Si un contrato cambia, se cambia aquí primero,
en su propio PR, y se avisa en el grupo.

## 1. Integrador (Haskell): entrada y salida

El servidor ejecuta `bin/integrador` y le escribe en la entrada estándar:

~~~json
{
  "modo": "original | corregida",
  "registros": [ { "id": 1, "fuente": "personal", "num": 1, "texto": "tarjeta,nombre,cargo,accesos" } ],
  "correcciones": [
    { "id": 1, "tipo": "desfase_reloj", "fuente": "radio", "segundos": -420, "dispositivo": "P7 (opcional)", "motivo": "..." },
    { "id": 2, "tipo": "descartar", "registro": 25, "motivo": "..." }
  ]
}
~~~

- Un registro es una línea de un archivo tal como llegó (o el archivo completo, en `energia.json`).
- `fuente` es una de: `personal`, `estacion`, `tarjetas`, `radio`, `energia`, `presencia`, `temperatura`, `bitacora`.
- En modo `original` las correcciones se ignoran.

El integrador responde por la salida estándar:

~~~json
{
  "personas":    [ { "id": "okafor", "nombre": "Tomás Okafor", "cargo": "...", "tarjeta": "JS-01", "accesos": ["P2"] } ],
  "puertas":     [ { "codigo": "P1", "modulo1": "COM", "modulo2": "DOR", "lector": false } ],
  "eventos":     [ { "id": "R25", "registro": 25, "fuente": "tarjetas", "ts": 2254786787, "hora": "2041-06-14T01:39:47Z",
                     "precision": 0, "tipo": "paso", "descripcion": "...", "tarjeta": "LP-04", "puerta": "P7",
                     "desde": "GEN", "hacia": "ALM", "resultado": "ok", "persona": "petrov" } ],
  "problemas":   [ { "registro": 24, "fuente": "tarjetas", "tipo": "corrupto", "motivo": "...", "usado": false } ],
  "deducciones": [ { "evento": "R38", "tipo": "declaracion", "descripcion": "..." } ],
  "hechos":      ":- encoding(utf8).\n..."
}
~~~

- `ts`: segundos desde 1970 en UTC. `precision`: incertidumbre en segundos (0 exacta, 60 radio, 600 "aprox").
- Tipos de evento: `paso`, `presencia`, `sensores_apagados`, `temperatura`, `consumo`, `corte`, `restablecido`, `mensaje`, `nota`.
- Tipos de problema: `corrupto`, `duplicado`, `alias`, `formato`, `contradiccion`, `descartado`. `usado` dice si el registro se usa a pesar del problema.
- La identidad única de cada persona es su apellido sin tildes: `okafor`, `vidal`, `ruiz`, `petrov`, `kimura`, `valcarcel`.

## 2. Hechos de Prolog

`hechos` es un programa Prolog con estos predicados. Ev es el id de evidencia (`'R25'`, `'R40.2'`).

| Hecho | Significado |
| --- | --- |
| `persona(Id, Nombre, Tarjeta)` | Las seis personas |
| `acceso(Tarjeta, Puerta)` | Puertas que abre cada tarjeta |
| `modulo(M)` | COM, DOR, LAB-A, LAB-B, GEN, RAD, ALM, EXT |
| `puerta(P, M1, M2, con_lector \| sin_lector)` | Conexiones de la estación |
| `paso(Ev, T, Prec, Tarjeta, Puerta, Desde, Hacia, ok \| denegado)` | Uso de tarjeta |
| `presencia(Ev, T, Modulo, N)` | Conteo de personas |
| `sensores_apagados(Ev, T)` | Los sensores de presencia sin energía |
| `temperatura(Ev, T, Modulo, Celsius)` | Lecturas de temperatura |
| `corte(Ev, Inicio, Fin, Afectados)` | Corte de energía (Fin = 9999999999 si no volvió) |
| `mensaje(Ev, T, Prec, Hablante, Texto)` | Línea de la radio |
| `declaracion(Ev, T, Prec, Declarante, Sujeto, Modulo, propia \| testimonio)` | Ubicación dicha en la radio o la bitácora |
| `oyo_puerta(Ev, Testigo, Puerta, durante_corte \| hora(T))` | Alguien dice que oyó una puerta |
| `tarjeta_perdida(Ev, T, Prec, Tarjeta)` | Tarjeta reportada como perdida |

## 3. Razonador (Prolog)

~~~
swipl prolog/razonador.pl -- <archivo de hechos> <pregunta> <argumentos...>
~~~

| Pregunta | Argumentos |
| --- | --- |
| `donde` | persona, hora |
| `quien_en` | módulo, desde, hasta |
| `quien_tarjeta` | tarjeta, hora |
| `recorrido` | persona o `cualquiera`, origen, destino, hora, minutos |
| `exterior` | desde, hasta |

Las horas van en segundos desde 1970 (UTC). Responde una línea JSON:

~~~json
{ "pregunta": "quien_tarjeta", "estado": "identificada", "resumen": "...",
  "candidatos": [ { "persona": "valcarcel", "nombre": "Irene Valcárcel" } ],
  "evidencia": [ { "id": "R25", "nota": "uso de la tarjeta" } ] }
~~~

Estados: `seguro`, `posible`, `si`, `no`, `identificada`, `varias`, `abierta_probable`, `sin_indicios`,
`respondida`, `no_se_puede_saber`, `contradictoria`, `sin_registro`, `no_reconocida`, `sin_respuesta`.
"No" solo se responde cuando la evidencia lo excluye; si falta evidencia, la respuesta es `no_se_puede_saber`.

## 4. API del servidor (Java)

| Método y ruta | Uso |
| --- | --- |
| `GET /api/estado` | Versión actual, registros y salud de los componentes |
| `GET /api/referencia` | Personas y módulos |
| `GET /api/linea?modo=original` | Línea de tiempo, problemas y deducciones de la versión actual |
| `GET /api/novedades?desde=N` | Eventos de registros con id mayor que N |
| `POST /api/vivo` | `{emisor, seq, fuente, texto}`: lectura en vivo (idempotente por emisor y seq) |
| `POST /api/consultas` | `{investigador, tipo, modo, parametros}`: pregunta |
| `GET /api/consultas` | Todas las consultas con su respuesta |
| `GET /api/consultas/{id}/reconstruccion` | Recalcula la respuesta desde la base de datos |
| `POST /api/correcciones` | `{agencia, tipo, fuente, dispositivo, segundos, registro, motivo}` |
| `GET /api/correcciones` | Correcciones recibidas |
| `GET /api/custodia` | Verifica la cadena SHA-256 |
| `GET /api/informe?modo=original` | Datos del informe del caso |

En `parametros`, las horas se escriben `HH:MM` o `HH:MM:SS` (UTC del 14/06/2041) o `AAAA-MM-DDTHH:MM:SS`.

## 5. Modelo de datos (SQLite)

| Tabla | Contenido | Relaciones |
| --- | --- | --- |
| `fuente` | Los 8 archivos | |
| `modulo` | Los 8 módulos | |
| `persona` | Las 6 personas | |
| `registro` | Evidencia original, una fila por línea; solo inserción; hash encadenado | `fuente_id → fuente` |
| `correccion` | Correcciones de las agencias; solo inserción; hash encadenado | `fuente_id → fuente`, `registro_id → registro` |
| `version` | Instantánea: último registro y última corrección usados, hash de los hechos | `ultimo_registro → registro` |
| `evento` | Línea de tiempo de cada versión y modo | `version_id → version`, `registro_id → registro`, `persona_id → persona`, `modulo → modulo` |
| `problema` | Problemas de cada versión y modo | `version_id → version`, `registro_id → registro` |
| `investigador` | Quién pregunta | |
| `consulta` | Pregunta, parámetros, modo y versión usada | `investigador_id → investigador`, `version_id → version` |
| `respuesta` | Respuesta, su hash y el hash de los hechos | `consulta_id → consulta` |

Los disparadores impiden `UPDATE` y `DELETE` en `registro`, `correccion`, `version`, `consulta` y `respuesta`.
