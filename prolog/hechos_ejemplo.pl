:- encoding(utf8).
:- dynamic persona/3, acceso/2, modulo/1, puerta/4, paso/8, presencia/4, sensores_apagados/2,
   temperatura/4, corte/4, mensaje/5, declaracion/7, oyo_puerta/4, tarjeta_perdida/4.

persona('okafor', 'Tomás Okafor', 'JS-01').
persona('vidal', 'Daniel Vidal', 'DV-02').
persona('ruiz', 'Marta Ruiz', 'MR-03').
persona('petrov', 'Lucas Petrov', 'LP-04').
persona('kimura', 'Aiko Kimura', 'AK-05').
persona('valcarcel', 'Irene Valcárcel', 'IV-07').
acceso('JS-01', 'P2').
acceso('JS-01', 'P3').
acceso('JS-01', 'P4').
acceso('JS-01', 'P5').
acceso('JS-01', 'P7').
acceso('JS-01', 'P8').
acceso('DV-02', 'P2').
acceso('DV-02', 'P3').
acceso('MR-03', 'P2').
acceso('MR-03', 'P4').
acceso('MR-03', 'P5').
acceso('MR-03', 'P7').
acceso('LP-04', 'P2').
acceso('LP-04', 'P5').
acceso('LP-04', 'P7').
acceso('AK-05', 'P2').
acceso('AK-05', 'P3').
acceso('IV-07', 'P2').
acceso('IV-07', 'P3').
acceso('IV-07', 'P4').
modulo('COM').
modulo('DOR').
modulo('LAB-A').
modulo('LAB-B').
modulo('GEN').
modulo('RAD').
modulo('ALM').
modulo('EXT').
puerta('P1', 'COM', 'DOR', sin_lector).
puerta('P2', 'DOR', 'LAB-A', con_lector).
puerta('P3', 'LAB-A', 'LAB-B', con_lector).
puerta('P4', 'LAB-B', 'GEN', con_lector).
puerta('P5', 'GEN', 'RAD', con_lector).
puerta('P6', 'RAD', 'COM', sin_lector).
puerta('P7', 'GEN', 'ALM', con_lector).
puerta('P8', 'ALM', 'EXT', con_lector).
paso('R18', 2254781524, 0, 'IV-07', 'P2', 'DOR', 'LAB-A', ok).
paso('R19', 2254782641, 0, 'IV-07', 'P3', 'LAB-A', 'LAB-B', ok).
paso('R20', 2254784895, 0, 'MR-03', 'P5', 'RAD', 'GEN', ok).
paso('R21', 2254785633, 0, 'IV-07', 'P4', 'LAB-B', 'GEN', ok).
paso('R23', 2254786502, 0, 'MR-03', 'P5', 'GEN', 'RAD', ok).
paso('R25', 2254786787, 0, 'LP-04', 'P7', 'GEN', 'ALM', ok).
paso('R26', 2254789090, 0, 'DV-02', 'P2', 'DOR', 'LAB-A', ok).
paso('R27', 2254789356, 0, 'DV-02', 'P3', 'LAB-A', 'LAB-B', ok).
paso('R28', 2254789812, 0, 'AK-05', 'P2', 'DOR', 'LAB-A', ok).
paso('R29', 2254790405, 0, 'DV-02', 'P4', 'LAB-B', 'GEN', denegado).
paso('R30', 2254790480, 0, 'DV-02', 'P3', 'LAB-B', 'LAB-A', ok).
presencia('R42', 2254786200, 'COM', 1).
presencia('R43', 2254786200, 'DOR', 2).
presencia('R44', 2254786200, 'LAB-A', 0).
presencia('R45', 2254786200, 'LAB-B', 0).
presencia('R46', 2254786200, 'GEN', 2).
presencia('R47', 2254786200, 'RAD', 1).
presencia('R48', 2254786200, 'ALM', 0).
presencia('R50', 2254789200, 'COM', 1).
presencia('R51', 2254789200, 'DOR', 1).
presencia('R52', 2254789200, 'LAB-A', 1).
presencia('R53', 2254789200, 'LAB-B', 0).
presencia('R54', 2254789200, 'GEN', 0).
presencia('R55', 2254789200, 'RAD', 2).
presencia('R56', 2254789200, 'ALM', 0).
sensores_apagados('R49', 2254786800).
temperatura('R58', 2254786200, 'ALM', 12.0).
temperatura('R59', 2254786200, 'EXT', -38.2).
temperatura('R60', 2254786800, 'ALM', 12.1).
temperatura('R61', 2254786800, 'EXT', -38.4).
temperatura('R62', 2254787400, 'ALM', 11.8).
temperatura('R63', 2254787400, 'EXT', -38.9).
temperatura('R64', 2254787700, 'ALM', 2.9).
temperatura('R65', 2254787700, 'EXT', -39.0).
temperatura('R66', 2254788000, 'ALM', -6.3).
temperatura('R67', 2254788000, 'EXT', -39.1).
temperatura('R68', 2254788600, 'ALM', -7.1).
temperatura('R69', 2254788600, 'EXT', -39.3).
temperatura('R70', 2254789200, 'ALM', -7.4).
temperatura('R71', 2254789200, 'EXT', -39.2).
corte('R40.2', 2254786800, 2254788900, ['COM','DOR','LAB-A','LAB-B','GEN','ALM']).
mensaje('R32', 2254783920, 60, 'petrov', 'Okafor, aquí radio. La doctora sigue en el B, dice que no la esperen para la cena.').
mensaje('R33', 2254786020, 60, 'okafor', 'Doc, ¿puedes revisar a Kimura? Tiene fiebre.').
mensaje('R34', 2254786080, 60, 'vidal', 'Voy para dormitorios.').
mensaje('R35', 2254787220, 60, 'petrov', 'Se fue la luz. Otra vez.').
mensaje('R36', 2254788000, 60, 'petrov', 'Okafor, ¿me copias? Sigo sin luz aquí en radio.').
mensaje('R37', 2254789380, 60, 'okafor', 'Volvió la energía. ¿Alguien ha visto a Irene?').
mensaje('R38', 2254789440, 60, 'ruiz', 'La dejé en generadores a la una y media. Estaba bien.').
mensaje('R39', 2254789860, 60, 'petrov', 'Durante el corte escuché la puerta exterior. Pensé que era el viento.').
declaracion('R32', 2254783920, 60, 'petrov', 'petrov', 'RAD', propia).
declaracion('R32', 2254783920, 60, 'petrov', 'valcarcel', 'LAB-B', testimonio).
declaracion('R76', 2254787400, 600, 'okafor', 'okafor', 'COM', propia).
declaracion('R36', 2254788000, 60, 'petrov', 'petrov', 'RAD', propia).
declaracion('R38', 2254786200, 300, 'ruiz', 'valcarcel', 'GEN', testimonio).
oyo_puerta('R39', 'petrov', 'P8', durante_corte).
tarjeta_perdida('R74', 2254651200, 43200, 'LP-04').
