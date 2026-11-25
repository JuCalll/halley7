# Bitácora de decisiones

Cada entrada se escribe el mismo día de la decisión, en el PR que la implementa.

| Fecha | Autor | Problema | Alternativas | Decisión | Prueba que la respalda |
| --- | --- | --- | --- | --- | --- |
| 2026-11-23 | Juan | Cómo trabajar los cuatro en paralelo con solo siete días | Que cada uno defina sus formatos al integrar | Git Flow y contratos escritos antes del código (`docs/contratos.md`), con hechos de ejemplo para Prolog | Valentina programa contra `prolog/hechos_ejemplo.pl` desde el primer día |
| 24/11/2026 | Miguel | No perder lecturas si el servidor se cae mientras el simulador envía | Enviar cada lectura una sola vez y olvidarla | Reintentar la misma lectura con espera exponencial (0,5 s, 1 s, 2 s, 4 s y luego 5 s fijos) hasta recibir 200, sin pasar a la siguiente. El `seq` es el número de línea, así el servidor no duplica lo reenviado | Se cierra el receptor a mitad del escenario y se reinicia: llegan 27 de 27 lecturas, con seq del 2 al 28 sin huecos |
