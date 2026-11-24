:- encoding(utf8).
:- use_module(library(http/json)).

% Declaración dinámica por si el archivo de hechos se consulta o carga en runtime
:- dynamic persona/3, acceso/2, modulo/1, puerta/4, paso/8, presencia/4,
           sensores_apagados/2, temperatura/4, corte/4, mensaje/5,
           declaracion/7, oyo_puerta/4, tarjeta_perdida/4.

% Punto de entrada CLI:
% swipl prolog/razonador.pl -- <archivo de hechos> <pregunta> <argumentos...>
:- initialization(main, main).

main :-
    current_prolog_flag(argv, Args),
    (   Args = [ArchivoHechos, PreguntaAtom | RestoArgs]
    ->  consult(ArchivoHechos),
        atom_string(Pregunta, PreguntaAtom),
        responder(Pregunta, RestoArgs, RespuestaJson),
        json_write(current_output, RespuestaJson, [width(0)]),
        nl,
        halt(0)
    ;   Resp = _{
            pregunta: "desconocida",
            estado: "sin_respuesta",
            resumen: "Argumentos insuficientes para razonador.pl",
            candidatos: [],
            evidencia: []
        },
        json_write(current_output, Resp, [width(0)]),
        nl,
        halt(1)
    ).

% --- 1. Movimiento y topología de la estación ---

% Conexión directa entre dos módulos a través de una puerta (bidireccional)
conexion_directa(M1, M2, Puerta, Lector) :-
    puerta(Puerta, M1, M2, Lector).
conexion_directa(M1, M2, Puerta, Lector) :-
    puerta(Puerta, M2, M1, Lector).

% Recorrido entre módulos evitando repetir módulos (termina en grafos con ciclo)
camino(Origen, Destino, RutaPuertas) :-
    modulo(Origen),
    modulo(Destino),
    camino_aux(Origen, Destino, [Origen], [], RutaInvertida),
    reverse(RutaInvertida, RutaPuertas).

camino_aux(Destino, Destino, _, Acc, Acc).
camino_aux(Actual, Destino, Visitados, Acc, Ruta) :-
    conexion_directa(Actual, Siguiente, Puerta, _),
    \+ member(Siguiente, Visitados),
    camino_aux(Siguiente, Destino, [Siguiente | Visitados], [Puerta | Acc], Ruta).

% --- 2. Preguntas del contrato ---

% donde <persona> <hora>
responder(donde, [PersonaArg, HoraArg], Resp) :-
    atom_string(Persona, PersonaArg),
    number_string(Hora, HoraArg),
    (   \+ persona(Persona, _, _)
    ->  Resp = _{
            pregunta: "donde",
            estado: "no_reconocida",
            resumen: "Persona no registrada en los hechos",
            candidatos: [],
            evidencia: []
        }
    ;   findall(Ev-Mod, ubicacion_evidenciada(Persona, Hora, Mod, Ev), Hallazgos),
        (   Hallazgos == []
        ->  Resp = _{
                pregunta: "donde",
                estado: "no_se_puede_saber",
                resumen: "Sin evidencia suficiente para determinar la ubicacion",
                candidatos: [],
                evidencia: []
            }
        ;   pairs_values(Hallazgos, Mods),
            sort(Mods, ModsUnicos),
            (   ModsUnicos = [_]
            ->  Estado = "posible",
                Resumen = "Ubicacion inferida a partir de la evidencia disponible"
            ;   Estado = "contradictoria",
                Resumen = "La evidencia apunta a mas de un modulo incompatible"
            ),
            armar_evidencias(Hallazgos, EvJson),
            Resp = _{
                pregunta: "donde",
                estado: Estado,
                resumen: Resumen,
                candidatos: [],
                evidencia: EvJson
            }
        )
    ).

% quien_en <modulo> <desde> <hasta>
responder(quien_en, [ModuloArg, DesdeArg, HastaArg], Resp) :-
    atom_string(Modulo, ModuloArg),
    number_string(Desde, DesdeArg),
    number_string(Hasta, HastaArg),
    findall(_{persona: Id, nombre: Nombre},
            (persona(Id, Nombre, _), persona_en_rango(Id, Modulo, Desde, Hasta, _)),
            CandidatosRaw),
    sort(CandidatosRaw, Candidatos),
    findall(Ev-"presencia en modulo en el intervalo",
            (persona(Id2, _, _), persona_en_rango(Id2, Modulo, Desde, Hasta, Ev)),
            EvRaw),
    sort(EvRaw, EvUnica),
    armar_evidencias(EvUnica, EvJson),
    (   Candidatos == []
    ->  Estado = "no_se_puede_saber",
        Resumen = "Sin evidencia concluyente de personas en el modulo en ese rango"
    ;   Estado = "respondida",
        Resumen = "Personas asociadas al modulo en el rango consultado"
    ),
    Resp = _{
        pregunta: "quien_en",
        estado: Estado,
        resumen: Resumen,
        candidatos: Candidatos,
        evidencia: EvJson
    }.

% quien_tarjeta <tarjeta> <hora>
responder(quien_tarjeta, [TarjetaArg, HoraArg], Resp) :-
    atom_string(Tarjeta, TarjetaArg),
    number_string(Hora, HoraArg),
    (   tarjeta_perdida(EvPerd, TPerd, PrecPerd, Tarjeta),
        Hora >= TPerd - PrecPerd
    ->  Estado = "abierta_probable",
        Resumen = "Tarjeta reportada como perdida antes o cerca de la hora consultada",
        EvBase = [EvPerd-"tarjeta reportada como perdida"]
    ;   Estado = "identificada",
        Resumen = "Titular registrado de la tarjeta",
        EvBase = []
    ),
    findall(_{persona: Id, nombre: Nombre},
            persona(Id, Nombre, Tarjeta),
            Candidatos),
    findall(Ev-"uso de tarjeta",
            (paso(Ev, TPaso, Prec, Tarjeta, _, _, _, _),
             abs(Hora - TPaso) =< max(Prec, 300)),
            EvPasos),
    append(EvBase, EvPasos, EvAll),
    sort(EvAll, EvUnica),
    armar_evidencias(EvUnica, EvJson),
    (   Candidatos == []
    ->  Resp = _{
            pregunta: "quien_tarjeta",
            estado: "sin_registro",
            resumen: "Tarjeta no encontrada en el registro de personas",
            candidatos: [],
            evidencia: EvJson
        }
    ;   Resp = _{
            pregunta: "quien_tarjeta",
            estado: Estado,
            resumen: Resumen,
            candidatos: Candidatos,
            evidencia: EvJson
        }
    ).

% recorrido <persona|cualquiera> <origen> <destino> <hora> <minutos>
responder(recorrido, [SujetoArg, OrigenArg, DestinoArg, HoraArg, MinArg], Resp) :-
    atom_string(Sujeto, SujetoArg),
    atom_string(Origen, OrigenArg),
    atom_string(Destino, DestinoArg),
    number_string(_Hora, HoraArg),
    number_string(_Min, MinArg),
    (   camino(Origen, Destino, _Ruta)
    ->  (   Sujeto == cualquiera
        ->  Estado = "si",
            Resumen = "Existe al menos una ruta valida entre origen y destino sin repetir modulos"
        ;   persona(Sujeto, _, Tarjeta),
            findall(Puerta, paso(_, _, _, Tarjeta, Puerta, _, _, ok), PuertasOk),
            (   PuertasOk == []
            ->  Estado = "no_se_puede_saber",
                Resumen = "Ruta topologica existente, pero sin pasos validados suficientes para confirmar el recorrido"
            ;   Estado = "posible",
                Resumen = "Existen pasos autorizados de la persona y ruta entre los modulos"
            )
        ),
        Resp = _{
            pregunta: "recorrido",
            estado: Estado,
            resumen: Resumen,
            candidatos: [],
            evidencia: []
        }
    ;   Resp = _{
            pregunta: "recorrido",
            estado: "no",
            resumen: "No existe ruta entre el origen y el destino en la estacion",
            candidatos: [],
            evidencia: []
        }
    ).

% exterior <desde> <hasta>
responder(exterior, [DesdeArg, HastaArg], Resp) :-
    number_string(Desde, DesdeArg),
    number_string(Hasta, HastaArg),
    findall(Ev-"paso por puerta exterior P8",
            (paso(Ev, T, Prec, _, 'P8', _, _, ok),
             T + Prec >= Desde,
             T - Prec =< Hasta),
            EvPasos),
    findall(Ev-"testimonio de puerta exterior",
            oyo_puerta(Ev, _, 'P8', _),
            EvOidos),
    append(EvPasos, EvOidos, EvAll),
    sort(EvAll, EvUnica),
    armar_evidencias(EvUnica, EvJson),
    (   EvUnica == []
    ->  Resp = _{
            pregunta: "exterior",
            estado: "sin_indicios",
            resumen: "No se registran indicios directos de apertura exterior en el rango",
            candidatos: [],
            evidencia: []
        }
    ;   Resp = _{
            estado: "abierta_probable",
            pregunta: "exterior",
            resumen: "Existen indicios vinculados a la puerta exterior en el caso",
            candidatos: [],
            evidencia: EvJson
        }
    ).

responder(_, _, Resp) :-
    Resp = _{
        pregunta: "no_soportada",
        estado: "sin_respuesta",
        resumen: "Pregunta no reconocida",
        candidatos: [],
        evidencia: []
    }.

% --- Auxiliares ---

ubicacion_evidenciada(Persona, Hora, Mod, Ev) :-
    persona(Persona, _, Tarjeta),
    paso(Ev, T, Prec, Tarjeta, _, _, Mod, ok),
    abs(Hora - T) =< max(Prec, 300).

ubicacion_evidenciada(Persona, Hora, Mod, Ev) :-
    declaracion(Ev, T, Prec, _, Persona, Mod, _),
    abs(Hora - T) =< max(Prec, 600).

persona_en_rango(Persona, Mod, Desde, Hasta, Ev) :-
    persona(Persona, _, Tarjeta),
    paso(Ev, T, Prec, Tarjeta, _, _, Mod, ok),
    T + Prec >= Desde,
    T - Prec =< Hasta.

persona_en_rango(Persona, Mod, Desde, Hasta, Ev) :-
    declaracion(Ev, T, Prec, _, Persona, Mod, _),
    T + Prec >= Desde,
    T - Prec =< Hasta.

armar_evidencias([], []).
armar_evidencias([Ev-Nota | Resto], [_{id: Ev, nota: Nota} | RestoJson]) :-
    armar_evidencias(Resto, RestoJson).