:- encoding(utf8).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(time)).
:- use_module(library(aggregate)).



:- dynamic persona/3, acceso/2, modulo/1, puerta/4, paso/8, presencia/4,
           sensores_apagados/2, temperatura/4, corte/4, mensaje/5,
           declaracion/7, oyo_puerta/4, tarjeta_perdida/4.

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

% Constantes

segundos_por_pasillo(120).
caida_minima(3.0).
limite_segundos(4).

% Estacion

conecta(A, B, P) :- puerta(P, A, B, _).
conecta(A, B, P) :- puerta(P, B, A, _).

exterior(P) :- puerta(P, A, B, _), ( A == 'EXT' ; B == 'EXT' ).

interna(P) :- puerta(P, _, _, _), \+ exterior(P).

nombre(P, Nombre) :- persona(P, Nombre, _), !.
nombre(P, P).

% Energia

corte_entre(T1, T2, Ev) :- corte(Ev, Inicio, Fin, _), Inicio =< T2, Fin >= T1.

% Tarjetas

titular(Tarjeta, Persona) :- persona(Persona, _, Tarjeta).

perdida_antes(Tarjeta, T, Ev) :- tarjeta_perdida(Ev, Tp, Prec, Tarjeta), Tp - Prec =< T.

confiable(Tarjeta, T) :- \+ perdida_antes(Tarjeta, T, _).

% Puertas que una persona puede cruzar a partir de la hora Tc (nadie = sin tarjeta propia)
% abierta(Quien, Desde, Hacia, Puerta, Tc, Limite, Inicio, Duracion, Motivo)

abierta(_, A, B, P, Tc, _, Tc, S, sin_lector) :-
    conecta(A, B, P), puerta(P, _, _, sin_lector), segundos_por_pasillo(S).
abierta(_, A, B, P, Tc, _, Tc, S, palanca) :-
    conecta(A, B, P), exterior(P), segundos_por_pasillo(S).
abierta(_, A, B, P, Tc, Limite, Inicio, S, corte(Ev)) :-
    conecta(A, B, P), puerta(P, _, _, con_lector), interna(P),
    corte(Ev, I, F, _), F >= Tc,
    Inicio is max(Tc, I), Inicio =< Limite,
    segundos_por_pasillo(S).
abierta(_, A, B, P, Tc, Limite, Tx, 0, tarjeta_ajena(Ev)) :-
    paso(Ev, Tx, _, Tarjeta, P, A, B, ok), Tx >= Tc, Tx =< Limite,
    \+ confiable(Tarjeta, Tx).
abierta(Quien, A, B, P, Tc, Limite, Tx, 0, propia(Ev)) :-
    Quien \== nadie,
    paso(Ev, Tx, _, Tarjeta, P, A, B, ok), Tx >= Tc, Tx =< Limite,
    titular(Tarjeta, Quien), confiable(Tarjeta, Tx).

% Recorridos con reloj: la lista de visitados evita los ciclos del anillo

alcanza(Quien, Origen, Destino, T1, T2, Ruta) :-
    T2 >= T1,
    camino(Quien, Origen, Destino, T1, T2, [Origen], Ruta).

camino(_, Destino, Destino, T1, T2, _, []) :-
    T2 >= T1.
camino(Quien, Actual, Destino, T1, T2, Visitados, [paso_ruta(Actual, Siguiente, P, Inicio, Motivo) | Resto]) :-
    abierta(Quien, Actual, Siguiente, P, T1, T2, Inicio, Dur, Motivo),
    \+ member(Siguiente, Visitados),
    FinTramo is Inicio + Dur,
    FinTramo =< T2,
    camino(Quien, Siguiente, Destino, FinTramo, T2, [Siguiente | Visitados], Resto).

% --- Preguntas del contrato ---

% 1. donde <persona> <hora>
responder(donde, [PersonaArg, HoraArg], Resp) :-
    atom_string(Persona, PersonaArg),
    number_string(Hora, HoraArg),
    (   \+ persona(Persona, _, _)
    ->  Resp = _{
            pregunta: "donde",
            estado: "no_reconocida",
            resumen: "Persona no registrada en el sistema",
            candidatos: [],
            evidencia: []
        }
    ;   findall(Ev-Mod, ubicacion_evidencia(Persona, Hora, Mod, Ev), Hallazgos),
        (   Hallazgos == []
        ->  Resp = _{
                pregunta: "donde",
                estado: "no_se_puede_saber",
                resumen: "Sin evidencia suficiente para determinar el modulo en esa hora",
                candidatos: [],
                evidencia: []
            }
        ;   pairs_values(Hallazgos, Mods),
            sort(Mods, ModsUnicos),
            (   ModsUnicos = [_]
            ->  Estado = "posible",
                Resumen = "Modulo inferido a partir de la evidencia disponible"
            ;   Estado = "contradictoria",
                Resumen = "La evidencia apunta a modulos distintos para la misma hora"
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

% 2. quien_en <modulo> <desde> <hasta>
responder(quien_en, [ModuloArg, DesdeArg, HastaArg], Resp) :-
    atom_string(Modulo, ModuloArg),
    number_string(Desde, DesdeArg),
    number_string(Hasta, HastaArg),
    findall(_{persona: Id, nombre: Nombre},
            (persona(Id, Nombre, _), persona_en_intervalo(Id, Modulo, Desde, Hasta, _)),
            CandidatosRaw),
    sort(CandidatosRaw, Candidatos),
    findall(Ev-"asociacion con el modulo en el rango",
            (persona(Id2, _, _), persona_en_intervalo(Id2, Modulo, Desde, Hasta, Ev)),
            EvRaw),
    sort(EvRaw, EvUnica),
    armar_evidencias(EvUnica, EvJson),
    (   Candidatos == []
    ->  Estado = "no_se_puede_saber",
        Resumen = "Sin evidencia concluyente para el modulo en el intervalo"
    ;   Estado = "respondida",
        Resumen = "Candidatos asociados al modulo en el intervalo consultado"
    ),
    Resp = _{
        pregunta: "quien_en",
        estado: Estado,
        resumen: Resumen,
        candidatos: Candidatos,
        evidencia: EvJson
    }.

% 3. quien_tarjeta <tarjeta> <hora>
responder(quien_tarjeta, [TarjetaArg, HoraArg], Resp) :-
    atom_string(Tarjeta, TarjetaArg),
    number_string(Hora, HoraArg),
    findall(_{persona: Id, nombre: Nombre},
            persona(Id, Nombre, Tarjeta),
            Candidatos),
    (   Candidatos == []
    ->  Resp = _{
            pregunta: "quien_tarjeta",
            estado: "sin_registro",
            resumen: "Tarjeta no registrada en el sistema",
            candidatos: [],
            evidencia: []
        }
    ;   findall(EvPerd-"tarjeta reportada como perdida",
                perdida_antes(Tarjeta, Hora, EvPerd),
                EvPerdList),
        findall(EvPaso-"uso de tarjeta",
                (paso(EvPaso, TPaso, Prec, Tarjeta, _, _, _, _),
                 abs(Hora - TPaso) =< max(Prec, 300)),
                EvPasos),
        append(EvPerdList, EvPasos, EvAll),
        sort(EvAll, EvUnica),
        armar_evidencias(EvUnica, EvJson),
        (   EvPerdList \= []
        ->  Estado = "abierta_probable",
            Resumen = "Tarjeta reportada como perdida antes o cerca de la hora consultada"
        ;   Estado = "identificada",
            Resumen = "Titular registrado de la tarjeta"
        ),
        Resp = _{
            pregunta: "quien_tarjeta",
            estado: Estado,
            resumen: Resumen,
            candidatos: Candidatos,
            evidencia: EvJson
        }
    ).

% 4. recorrido <persona|cualquiera> <origen> <destino> <hora> <minutos>
responder(recorrido, [SujetoArg, OrigenArg, DestinoArg, HoraArg, MinArg], Resp) :-
    atom_string(Sujeto, SujetoArg),
    atom_string(Origen, OrigenArg),
    atom_string(Destino, DestinoArg),
    number_string(Hora, HoraArg),
    number_string(Minutos, MinArg),
    TFin is Hora + Minutos * 60,
    (   Sujeto == cualquiera
    ->  (   findall(Ruta, alcanza(nadie, Origen, Destino, Hora, TFin, Ruta), Rutas),
            Rutas \= []
        ->  Estado = "si",
            Resumen = "Existe al menos un recorrido valido dentro de la ventana de tiempo"
        ;   Estado = "no",
            Resumen = "No se encuentra recorrido valido en el tiempo y ventana indicados"
        ),
        Resp = _{
            pregunta: "recorrido",
            estado: Estado,
            resumen: Resumen,
            candidatos: [],
            evidencia: []
        }
    ;   \+ persona(Sujeto, _, _)
    ->  Resp = _{
            pregunta: "recorrido",
            estado: "no_reconocida",
            resumen: "Persona no registrada para evaluar el recorrido",
            candidatos: [],
            evidencia: []
        }
    ;   findall(Ruta, alcanza(Sujeto, Origen, Destino, Hora, TFin, Ruta), RutasPersona),
        (   RutasPersona \= []
        ->  Estado = "posible",
            Resumen = "Existe recorrido consistente con las reglas y eventos de la persona"
        ;   Estado = "no_se_puede_saber",
            Resumen = "Sin evidencia suficiente para confirmar el recorrido de la persona en ese rango"
        ),
        Resp = _{
            pregunta: "recorrido",
            estado: Estado,
            resumen: Resumen,
            candidatos: [],
            evidencia: []
        }
    ).

% 5. exterior <desde> <hasta>
responder(exterior, [DesdeArg, HastaArg], Resp) :-
    number_string(Desde, DesdeArg),
    number_string(Hasta, HastaArg),
    caida_minima(CaidaMin),
    findall(Ev-"paso registrado en puerta exterior",
            (paso(Ev, T, Prec, _, P, _, _, ok),
             exterior(P),
             T + Prec >= Desde,
             T - Prec =< Hasta),
            EvPasos),
    findall(Ev-"testimonio sobre puerta exterior",
            oyo_puerta(Ev, _, P, _),
            exterior(P)),
            EvOidos),
    findall(Ev-"caida termica abrupta en ALM",
            (temperatura(Ev, T, 'ALM', Temp),
             T >= Desde, T =< Hasta,
             Temp =< CaidaMin),
            EvTemp),
    append(EvPasos, EvOidos, Temp1),
    append(Temp1, EvTemp, EvAll),
    sort(EvAll, EvUnica),
    armar_evidencias(EvUnica, EvJson),
    (   EvUnica == []
    ->  Resp = _{
            pregunta: "exterior",
            estado: "sin_indicios",
            resumen: "No se registran indicios de apertura exterior en el intervalo",
            candidatos: [],
            evidencia: []
        }
    ;   Resp = _{
            pregunta: "exterior",
            estado: "abierta_probable",
            resumen: "Existen indicios de apertura de la puerta exterior en el intervalo",
            candidatos: [],
            evidencia: EvJson
        }
    ).

responder(_, _, Resp) :-
    Resp = _{
        pregunta: "desconocida",
        estado: "sin_respuesta",
        resumen: "Pregunta no soportada",
        candidatos: [],
        evidencia: []
    }.

% --- Auxiliares ---

ubicacion_evidencia(Persona, Hora, Mod, Ev) :-
    persona(Persona, _, Tarjeta),
    paso(Ev, T, Prec, Tarjeta, _, _, Mod, ok),
    abs(Hora - T) =< max(Prec, 300).

ubicacion_evidencia(Persona, Hora, Mod, Ev) :-
    declaracion(Ev, T, Prec, _, Persona, Mod, _),
    abs(Hora - T) =< max(Prec, 600).

persona_en_intervalo(Persona, Mod, Desde, Hasta, Ev) :-
    persona(Persona, _, Tarjeta),
    paso(Ev, T, Prec, Tarjeta, _, _, Mod, ok),
    T + Prec >= Desde,
    T - Prec =< Hasta.

persona_en_intervalo(Persona, Mod, Desde, Hasta, Ev) :-
    declaracion(Ev, T, Prec, _, Persona, Mod, _),
    T + Prec >= Desde,
    T - Prec =< Hasta.

armar_evidencias([], []).
armar_evidencias([Ev-Nota | Resto], [_{id: Ev, nota: Nota} | RestoJson]) :-
    armar_evidencias(Resto, RestoJson).

camino(_, D, D, _, _, Visitados, Ruta) :-
    reverse(Visitados, Ruta).
camino(Quien, A, D, Tc, Limite, Visitados, Ruta) :-
    A \== D,
    abierta(Quien, A, B, _, Tc, Limite, Inicio, Duracion, _),
    \+ memberchk(B, Visitados),
    Llegada is Inicio + Duracion,
    Llegada =< Limite,
    camino(Quien, B, D, Llegada, Limite, [B|Visitados], Ruta).

se_puede(Quien, A, B, T1, T2) :- once(alcanza(Quien, A, B, T1, T2, _)).

% Anclas: evidencia que ubica a una persona en un modulo

ancla(P, Hacia, T, 0, Ev, registro) :-
    paso(Ev, T, _, Tarjeta, _, _, Hacia, ok),
    titular(Tarjeta, P), confiable(Tarjeta, T).
ancla(P, Desde, T0, 0, Ev, registro) :-
    paso(Ev, T, _, Tarjeta, _, Desde, _, _),
    titular(Tarjeta, P), confiable(Tarjeta, T),
    T0 is T - 1.
ancla(P, M, T, Prec, Ev, Tipo) :-
    declaracion(Ev, T, Prec, _, P, M, Tipo).

tiene_anclas(P) :- once(ancla(P, _, _, _, _, _)).

compatible(P, M, T, Ma, Ta, Prec) :-
    (   T >= Ta
    ->  Desde is Ta - Prec, se_puede(P, Ma, M, Desde, T)
    ;   Hasta is Ta + Prec, se_puede(P, M, Ma, T, Hasta)
    ).

% Personas que con seguridad estaban en un modulo

seguro_en(P, M, T) :-
    ancla(P, M, Ta, 0, _, registro), Ta =< T,
    \+ ( ancla(P, _, Tb, _, _, registro), Tb > Ta, Tb =< T ),
    sin_salida(M, Ta, T, P).

seguros_en(M, T, Personas) :-
    findall(P, seguro_en(P, M, T), Lista),
    sort(Lista, Personas).

sin_salida(M, T1, T2, P) :-
    \+ abierta(nadie, M, _, _, T1, T2, _, _, _),
    \+ ( paso(_, Tx, _, Tarjeta, _, M, _, ok), titular(Tarjeta, P), Tx >= T1, Tx =< T2 ).

sin_entrada(M, T1, T2, P) :-
    \+ abierta(nadie, _, M, _, T1, T2, _, _, _),
    \+ ( paso(_, Tx, _, Tarjeta, _, _, M, ok), titular(Tarjeta, P), Tx >= T1, Tx =< T2 ).

% Sensor de presencia completo: si ya estan todos los que cuenta, nadie mas estaba

excluida_por_presencia(P, M, T, Ev) :-
    presencia(Ev, Tp, M, N),
    seguros_en(M, Tp, Seguros),
    length(Seguros, N),
    \+ memberchk(P, Seguros),
    (   Tp =< T
    ->  sin_entrada(M, Tp, T, P)
    ;   sin_salida(M, T, Tp, P)
    ).

% Donde pudo estar una persona

pudo_estar(P, M, T) :-
    modulo(M),
    forall(ancla(P, Ma, Ta, Prec, _, _), compatible(P, M, T, Ma, Ta, Prec)),
    \+ excluida_por_presencia(P, M, T, _).

posibles(P, T, Modulos) :-
    findall(M, pudo_estar(P, M, T), Modulos).

estado_lugar(P, T, Estado, Modulos) :-
    posibles(P, T, Modulos),
    (   Modulos == []
    ->  Estado = contradictoria
    ;   \+ tiene_anclas(P)
    ->  Estado = no_se_puede_saber
    ;   Modulos = [_]
    ->  Estado = seguro
    ;   Estado = posible
    ).
