:- encoding(utf8).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(time)).
:- use_module(library(aggregate)).

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
