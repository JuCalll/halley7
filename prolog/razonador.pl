:- encoding(utf8).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(time)).
:- use_module(library(aggregate)).
:- initialization(principal, main).
:- discontiguous resolver/2.

% Uso: swipl razonador.pl -- hechos.pl <pregunta> <argumentos...>

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
% Evidencia que sostiene una ubicacion

ancla_anterior(P, T, Ev, Ta, M) :-
    findall(Ta0-(Ev0-M0), ( ancla(P, M0, Ta0, _, Ev0, _), Ta0 =< T ), L),
    L \== [], max_member(Ta-(Ev-M), L).

ancla_siguiente(P, T, Ev, Ta, M) :-
    findall(Ta0-(Ev0-M0), ( ancla(P, M0, Ta0, _, Ev0, _), Ta0 > T ), L),
    L \== [], min_member(Ta-(Ev-M), L).

evidencia_lugar(P, T, Evidencia) :-
    findall(E, evidencia_lugar_una(P, T, E), Pares),
    como_evidencia(Pares, Evidencia).

como_evidencia(Pares, Evidencia) :-
    list_to_set(Pares, Unicos),
    findall(_{id: Id, nota: Nota}, member(Id-Nota, Unicos), Evidencia).

evidencia_lugar_una(P, T, Ev-Nota) :-
    ancla_anterior(P, T, Ev, Ta, M),
    hora(Ta, H), format(string(Nota), "ultima ubicacion antes: ~w a las ~w", [M, H]).
evidencia_lugar_una(P, T, Ev-Nota) :-
    ancla_siguiente(P, T, Ev, Ta, M),
    hora(Ta, H), format(string(Nota), "primera ubicacion despues: ~w a las ~w", [M, H]).
evidencia_lugar_una(P, T, Ev-Nota) :-
    modulo(M), excluida_por_presencia(P, M, T, Ev),
    format(string(Nota), "el sensor de ~w ya cuenta a todos los que estaban alli", [M]).
evidencia_lugar_una(P, T, Ev-"corte de energia: las puertas internas no registran") :-
    ancla_anterior(P, T, _, Ta, _), corte_entre(Ta, T, Ev).
evidencia_lugar_una(P, T, Ev-Nota) :-
    ancla_anterior(P, T, _, Ta, _),
    paso(Ev, Tp, _, Tarjeta, _, _, _, ok), Tp >= Ta, Tp =< T, \+ confiable(Tarjeta, Tp),
    perdida_antes(Tarjeta, Tp, _),
    format(string(Nota), "uso de la tarjeta perdida ~w: pudo usarla cualquiera", [Tarjeta]).

% Pregunta 1: donde pudo estar una persona a una hora

resolver([donde, P, TA], R) :-
    atom_number(TA, T),
    (   persona(P, Nombre, _)
    ->  estado_lugar(P, T, Estado, Modulos),
        evidencia_lugar(P, T, Ev),
        hora(T, H),
        resumen_donde(Estado, Nombre, H, Modulos, Resumen),
        R = _{pregunta: donde, estado: Estado, resumen: Resumen, modulos: Modulos, evidencia: Ev}
    ;   persona_desconocida(donde, P, R)
    ).

resumen_donde(seguro, N, H, [M], S) :-
    format(string(S), "A las ~w, ~w estaba en ~w: la evidencia no permite otro lugar.", [H, N, M]).
resumen_donde(posible, N, H, Ms, S) :-
    atomic_list_concat(Ms, ', ', L),
    format(string(S), "A las ~w, ~w pudo estar en: ~w. La evidencia no permite saber en cual.", [H, N, L]).
resumen_donde(no_se_puede_saber, N, H, _, S) :-
    format(string(S), "No hay evidencia que ubique a ~w; a las ~w no se puede saber donde estaba.", [N, H]).
resumen_donde(contradictoria, N, H, _, S) :-
    format(string(S), "La evidencia sobre ~w es contradictoria: ningun lugar es compatible a las ~w.", [N, H]).

% Pregunta 2: quien pudo estar en un modulo en un intervalo

resolver([quien_en, M, T1A, T2A], R) :-
    atom_number(T1A, T1), atom_number(T2A, T2),
    (   \+ modulo(M)
    ->  modulo_desconocido(quien_en, M, R)
    ;   T2 < T1
    ->  R = _{pregunta: quien_en, estado: no_se_puede_saber, resumen: "El intervalo esta al reves: la hora final es anterior a la inicial.", personas: [], evidencia: []}
    ;   muestras(T1, T2, Ts),
        findall(_{persona: P, nombre: N, estado: E}, ( persona(P, N, _), estado_en_intervalo(P, M, Ts, E) ), Personas),
        findall(N, ( member(D, Personas), D.estado == si, N = D.nombre ), Si),
        findall(N, ( member(D, Personas), member(D.estado, [pudo, no_se_puede_saber]), N = D.nombre ), Pudo),
        findall(Par, evidencia_intervalo(M, T1, T2, Ts, Par), Pares),
        como_evidencia(Pares, Evidencia),
        hora(T1, H1), hora(T2, H2),
        resumen_quien(M, H1, H2, Si, Pudo, Resumen),
        R = _{pregunta: quien_en, estado: respondida, resumen: Resumen, personas: Personas, evidencia: Evidencia}
    ).

evidencia_intervalo(M, T1, T2, _, Ev-"lectura de presencia en el intervalo") :-
    presencia(Ev, T, M, _), T >= T1, T =< T2.
evidencia_intervalo(_, T1, _, _, Ev-Nota) :-
    persona(P, N, _), ancla_anterior(P, T1, Ev, Ta, Ma),
    hora(Ta, H), format(string(Nota), "ultima ubicacion de ~w antes del intervalo: ~w a las ~w", [N, Ma, H]).
evidencia_intervalo(_, _, T2, _, Ev-Nota) :-
    persona(P, N, _), ancla_siguiente(P, T2, Ev, Ta, Ma),
    hora(Ta, H), format(string(Nota), "primera ubicacion de ~w despues del intervalo: ~w a las ~w", [N, Ma, H]).
evidencia_intervalo(M, _, _, Ts, Ev-Nota) :-
    persona(P, _, _), member(T, Ts), excluida_por_presencia(P, M, T, Ev),
    format(string(Nota), "el sensor de ~w ya cuenta a todos los que estaban alli", [M]).
evidencia_intervalo(_, T1, T2, _, Ev-"corte de energia: las puertas internas no registran") :-
    corte_entre(T1, T2, Ev).

muestras(T1, T2, Ts) :-
    Paso is max(60, (T2 - T1) // 300),
    findall(T, ( between(0, 100000, K), T is T1 + K * Paso, T =< T2 ), Base),
    findall(T, ( presencia(_, T, _, _), T >= T1, T =< T2 ), Lecturas),
    append([Base, Lecturas, [T2]], Todas),
    sort(Todas, Ts).

estado_en_intervalo(P, M, Ts, Estado) :-
    (   member(T, Ts), posibles(P, T, [M]), tiene_anclas(P)
    ->  Estado = si
    ;   member(T, Ts), pudo_estar(P, M, T)
    ->  ( tiene_anclas(P) -> Estado = pudo ; Estado = no_se_puede_saber )
    ;   Estado = no
    ).

resumen_quien(M, H1, H2, Si, Pudo, S) :-
    lista_texto(Si, TSi), lista_texto(Pudo, TPudo),
    format(string(S), "Entre ~w y ~w en ~w. Estuvo con seguridad: ~w. Pudo estar: ~w.", [H1, H2, M, TSi, TPudo]).
% Pregunta 3: quien pudo usar una tarjeta

resolver([quien_tarjeta, Tarjeta, TA], R) :-
    atom_number(TA, T),
    (   findall(D-Ev, ( paso(Ev, Tp, _, Tarjeta, _, _, _, _), D is abs(Tp - T), D =< 120 ), Cercanos),
        Cercanos \== []
    ->  min_member(_-Ev, Cercanos),
        paso(Ev, Tp, _, Tarjeta, Puerta, Desde, Hacia, Resultado),
        Antes is Tp - 1,
        findall(_{persona: P, nombre: N}, ( persona(P, N, _), pudo_estar(P, Desde, Antes) ), Candidatos),
        length(Candidatos, Cuantos),
        estado_tarjeta(Cuantos, Estado),
        evidencia_tarjeta(Ev, Tarjeta, Tp, Desde, Evidencia),
        hora(Tp, H),
        resumen_tarjeta(Estado, Tarjeta, Puerta, Desde, Hacia, Resultado, H, Candidatos, Resumen),
        R = _{pregunta: quien_tarjeta, estado: Estado, resumen: Resumen, candidatos: Candidatos, evidencia: Evidencia}
    ;   hora(T, H),
        format(string(S), "No hay ningun uso registrado de la tarjeta ~w cerca de las ~w.", [Tarjeta, H]),
        R = _{pregunta: quien_tarjeta, estado: sin_registro, resumen: S, candidatos: [], evidencia: []}
    ).

estado_tarjeta(0, contradictoria).
estado_tarjeta(1, identificada).
estado_tarjeta(N, varias) :- N > 1.

evidencia_tarjeta(Ev, Tarjeta, Tp, Desde, Evidencia) :-
    findall(E, evidencia_tarjeta_una(Ev, Tarjeta, Tp, Desde, E), Pares),
    como_evidencia(Pares, Evidencia).

evidencia_tarjeta_una(Ev, _, _, _, Ev-"uso de la tarjeta").
evidencia_tarjeta_una(_, Tarjeta, Tp, _, Ev-"la tarjeta estaba reportada como perdida") :-
    perdida_antes(Tarjeta, Tp, Ev).
evidencia_tarjeta_una(_, _, Tp, Desde, Ev-Nota) :-
    Antes is Tp - 1,
    persona(P, _, _), excluida_por_presencia(P, Desde, Antes, Ev),
    format(string(Nota), "el sensor de ~w ya contaba a todos los que estaban alli", [Desde]).
evidencia_tarjeta_una(Uso, _, Tp, Desde, Ev-Nota) :-
    Antes is Tp - 1,
    persona(P, _, _), seguro_en(P, Desde, Antes),
    ancla(P, Desde, Ta, 0, Ev, registro), Ta =< Antes, Ev \== Uso,
    nombre(P, N), format(string(Nota), "ubica a ~w en ~w", [N, Desde]).

resumen_tarjeta(Estado, Tarjeta, Puerta, Desde, Hacia, Resultado, H, Candidatos, S) :-
    findall(N, member(_{persona: _, nombre: N}, Candidatos), Ns),
    lista_texto(Ns, TNs),
    (   titular(Tarjeta, Tit), nombre(Tit, NT) -> true ; NT = "sin titular" ),
    (   tarjeta_perdida(_, _, _, Tarjeta) -> Aviso = " La tarjeta estaba reportada como perdida." ; Aviso = "" ),
    texto_estado_tarjeta(Estado, TE),
    format(string(S), "A las ~w la tarjeta ~w (titular: ~w) se uso en ~w de ~w a ~w (~w). ~w: ~w.~w",
           [H, Tarjeta, NT, Puerta, Desde, Hacia, Resultado, TE, TNs, Aviso]).

texto_estado_tarjeta(identificada, "Solo una persona pudo estar junto a la puerta").
texto_estado_tarjeta(varias, "Pudieron estar junto a la puerta").
texto_estado_tarjeta(contradictoria, "Ninguna persona es compatible con la evidencia").

% Pregunta 4: si un recorrido era posible en cierto tiempo

resolver([recorrido, Quien, Origen, Destino, TA, MinA], R) :-
    atom_number(TA, T), atom_number(MinA, Minutos),
    (   \+ modulo(Origen) -> modulo_desconocido(recorrido, Origen, R)
    ;   \+ modulo(Destino) -> modulo_desconocido(recorrido, Destino, R)
    ;   Quien \== cualquiera, \+ persona(Quien, _, _) -> persona_desconocida(recorrido, Quien, R)
    ;   ruta_mas_corta(Quien, Origen, Destino, T, Ruta, Puertas)
    ->  length(Puertas, Pasillos),
        segundos_por_pasillo(S), Necesarios is Pasillos * S / 60,
        ( Necesarios =< Minutos -> Estado = si ; Estado = no ),
        evidencia_recorrido(T, Puertas, Ev),
        resumen_recorrido(Estado, Quien, Ruta, Necesarios, Minutos, T, Resumen),
        R = _{pregunta: recorrido, estado: Estado, resumen: Resumen, ruta: Ruta, minutos: Necesarios, evidencia: Ev}
    ;   hora(T, H), nombre(Quien, N),
        (   titular(Tarjeta, Quien), perdida_antes(Tarjeta, T, EvP)
        ->  format(string(Extra), " Su tarjeta ~w estaba reportada como perdida.", [Tarjeta]), Ev = [_{id: EvP, nota: "tarjeta reportada como perdida"}]
        ;   Extra = "", Ev = []
        ),
        format(string(S), "~w no podia llegar de ~w a ~w a las ~w: todas las rutas pasan por puertas que no podia abrir.~w", [N, Origen, Destino, H, Extra]),
        R = _{pregunta: recorrido, estado: no, resumen: S, ruta: [], minutos: 0, evidencia: Ev}
    ).

puede_cruzar(Quien, A, B, P, T) :-
    abierta(Quien, A, B, P, T, T, _, _, _).
puede_cruzar(cualquiera, A, B, P, _) :-
    conecta(A, B, P).
puede_cruzar(Persona, A, B, P, T) :-
    conecta(A, B, P), puerta(P, _, _, con_lector),
    titular(Tarjeta, Persona), confiable(Tarjeta, T), acceso(Tarjeta, P).

ruta_mas_corta(Quien, Origen, Destino, T, Ruta, Puertas) :-
    between(0, 8, Limite),
    ruta(Quien, Origen, Destino, T, Limite, [Origen], Ruta, Puertas),
    !.

ruta(_, D, D, _, _, Visitados, Ruta, []) :-
    reverse(Visitados, Ruta).
ruta(Quien, A, D, T, N, Visitados, Ruta, [P|Ps]) :-
    A \== D, N > 0,
    puede_cruzar(Quien, A, B, P, T),
    \+ memberchk(B, Visitados),
    N1 is N - 1,
    ruta(Quien, B, D, T, N1, [B|Visitados], Ruta, Ps).

evidencia_recorrido(T, Puertas, Ev) :-
    findall(_{id: E, nota: "corte de energia: las puertas internas estaban desbloqueadas"},
            ( corte_entre(T, T, E), member(P, Puertas), interna(P), puerta(P, _, _, con_lector) ), L),
    list_to_set(L, Ev).

resumen_recorrido(Estado, Quien, Ruta, Necesarios, Minutos, T, S) :-
    nombre(Quien, N), hora(T, H),
    atomic_list_concat(Ruta, ' -> ', TR),
    (   Estado == si
    ->  format(string(S), "Si. A las ~w, ~w podia hacer ~w en ~w minutos (limite: ~w).", [H, N, TR, Necesarios, Minutos])
    ;   format(string(S), "No. A las ~w, la ruta mas corta para ~w es ~w y toma ~w minutos (limite: ~w).", [H, N, TR, Necesarios, Minutos])
    ).

% Pregunta 5: aperturas de la puerta exterior

resolver([exterior, T1A, T2A], R) :-
    atom_number(T1A, T1), atom_number(T2A, T2),
    findall(A, apertura(T1, T2, A), Aperturas),
    findall(_{id: Ev, nota: "testimonio sobre la puerta exterior"}, oyo_puerta(Ev, _, _, _), Testimonios),
    findall(_{id: Ev, nota: Nota}, fuera_de_modulos(T1, T2, Ev, Nota), Conteos),
    findall(E, ( member(A, Aperturas), member(E, A.evidencia) ), EvA),
    append([EvA, Testimonios, Conteos], Ev0),
    list_to_set(Ev0, Evidencia),
    ( Aperturas == [] -> Estado = sin_indicios ; Estado = abierta_probable ),
    resumen_exterior(Aperturas, Conteos, Resumen),
    R = _{pregunta: exterior, estado: Estado, resumen: Resumen, aperturas: Aperturas, evidencia: Evidencia}.

apertura(T1, T2, _{desde: Ha, hasta: Hb, caida: Caida, personas: Personas, evidencia: Ev}) :-
    temperatura(EvA, Ta, 'ALM', Ca),
    siguiente_temperatura(Ta, EvB, Tb, Cb),
    Ta >= T1, Tb =< T2,
    caida_minima(Min), Caida is Ca - Cb, Caida >= Min,
    hora(Ta, Ha), hora(Tb, Hb),
    muestras(Ta, Tb, Ts),
    findall(N, ( persona(P, N, _), member(T, Ts), pudo_estar(P, 'ALM', T) ), Ns0),
    sort(Ns0, Personas),
    findall(_{id: E, nota: "corte de energia: P8 no registra y tiene palanca"}, corte_entre(Ta, Tb, E), EvC),
    append([[_{id: EvA, nota: "temperatura del almacen antes"}, _{id: EvB, nota: "temperatura del almacen despues"}], EvC], Ev).

siguiente_temperatura(Ta, EvB, Tb, Cb) :-
    findall(Tx-(E-C), ( temperatura(E, Tx, 'ALM', C), Tx > Ta ), L),
    L \== [], min_member(Tb-(EvB-Cb), L).

fuera_de_modulos(T1, T2, Ev, Nota) :-
    presencia(Ev, T, 'COM', _), T >= T1, T =< T2,
    findall(N, presencia(_, T, _, N), Ns), sum_list(Ns, Dentro),
    aggregate_all(count, persona(_, _, _), Total),
    Fuera is Total - Dentro, Fuera > 0,
    hora(T, H),
    format(string(Nota), "a las ~w los sensores cuentan ~w de ~w personas: ~w no estaba en ningun modulo", [H, Dentro, Total, Fuera]).

resumen_exterior([], _, "No hay caidas de temperatura en el almacen que indiquen una apertura de la puerta exterior.").
resumen_exterior([A|As], Conteos, S) :-
    length([A|As], N),
    lista_texto(A.personas, TP),
    ( Conteos = [C|_] -> format(string(Extra), " Ademas, ~w.", [C.nota]) ; Extra = "" ),
    format(string(S), "Hay ~w intervalo(s) con caida brusca de temperatura en el almacen. El primero, de ~w a ~w (bajo ~1f grados), sin registro de tarjeta en P8. Pudieron estar en el almacen: ~w.~w",
           [N, A.desde, A.hasta, A.caida, TP, Extra]).

% Preguntas no reconocidas y datos desconocidos (siempre hay una respuesta)

resolver(Pregunta, R) :-
    atomic_list_concat(Pregunta, ' ', Texto),
    format(string(S), "No reconozco la pregunta '~w'. Tipos: donde, quien_en, quien_tarjeta, recorrido, exterior.", [Texto]),
    R = _{pregunta: desconocida, estado: no_reconocida, resumen: S, evidencia: []}.

persona_desconocida(Tipo, P, _{pregunta: Tipo, estado: no_se_puede_saber, resumen: S, evidencia: []}) :-
    format(string(S), "No hay ninguna persona '~w' en personal.csv.", [P]).

modulo_desconocido(Tipo, M, _{pregunta: Tipo, estado: no_se_puede_saber, resumen: S, evidencia: []}) :-
    format(string(S), "No existe el modulo '~w' en la estacion.", [M]).

% Una sola respuesta por pregunta

responder(Pregunta, R) :- once(resolver(Pregunta, R)).

% Utilidades

hora(T, Texto) :-
    stamp_date_time(T, D, 'UTC'),
    format_time(string(Texto), '%H:%M:%S', D).

lista_texto([], "nadie") :- !.
lista_texto(L, T) :- atomic_list_concat(L, ', ', A), atom_string(A, T).

% Programa

principal :-
    current_prolog_flag(argv, Argumentos),
    (   Argumentos = [Hechos|Pregunta], Pregunta \== []
    ->  set_stream(user_output, encoding(utf8)),
        catch(consult(Hechos), _, true),
        limite_segundos(L),
        catch(call_with_time_limit(L, responder(Pregunta, R)), Error, error_a_respuesta(Error, R)),
        json_write_dict(current_output, R, [width(0)]),
        nl
    ;   true
    ).

error_a_respuesta(time_limit_exceeded, _{pregunta: error, estado: sin_respuesta, resumen: "La consulta supero el tiempo limite y se detuvo.", evidencia: []}) :- !.
error_a_respuesta(E, _{pregunta: error, estado: sin_respuesta, resumen: S, evidencia: []}) :-
    format(string(S), "Error al razonar: ~q", [E]).