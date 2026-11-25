# Bitácora de decisiones

Cada entrada se escribe el mismo día de la decisión, en el PR que la implementa.

| Fecha | Autor | Problema | Alternativas | Decisión | Prueba que la respalda |
| --- | --- | --- | --- | --- | --- |
| 2026-11-23 | Juan | Cómo trabajar los cuatro en paralelo con solo siete días | Que cada uno defina sus formatos al integrar | Git Flow y contratos escritos antes del código (`docs/contratos.md`), con hechos de ejemplo para Prolog | Valentina programa contra `prolog/hechos_ejemplo.pl` desde el primer día |
| 2026-11-24 | Miguel | No perder lecturas si el servidor se cae mientras el simulador envía | Enviar cada lectura una sola vez y olvidarla | Reintentar la misma lectura con espera exponencial (0,5 s, 1 s, 2 s, 4 s y luego 5 s fijos) hasta recibir 200, sin pasar a la siguiente. El `seq` es el número de línea, así el servidor no duplica lo reenviado | Se cierra el receptor a mitad del escenario y se reinicia: llegan 27 de 27 lecturas, con seq del 2 al 28 sin huecos |
| 2026-11-23 | Juan | Líneas corruptas, duplicadas o con formato raro en las fuentes | Limpiar los archivos a mano o descartar las líneas en silencio | Cada línea cruda se conserva; el problema queda registrado con su tipo, su motivo y si la línea se usa | Prueba en GHCi: la línea corrupta de tarjetas produce un problema `Corrupto` con motivo y `prUsado = False` |
| 2026-11-23 | Juan | Una persona aparece con varios nombres (Luka, doc, doctora, jefe) | Usar la tarjeta como identidad | Identidad por apellido sin tildes y tabla de alias | Con la tarjeta como identidad, el uso de LP-04 (reportada perdida) se le atribuiría a Petrov |
| 2026-11-24 | Juan | La primera versión del razonador ubicaba a cada persona solo por sus pasos directos, fallaba con las horas como argumento y atribuía LP-04 a su titular | Mantenerla y corregir solo el error de `number_string/2` | Reemplazarla por la búsqueda con reloj, anclas y cierre por sensor de presencia (§5.3 de la guía) | Con la nueva base, `posibles(ruiz, 2254786787, L)` excluye GEN y la búsqueda en el anillo termina; con la anterior, `quien_tarjeta LP-04` respondía Petrov |
