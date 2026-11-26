:- use_module(library(plunit)).
:- ensure_loaded(razonador).
:- consult(hechos_ejemplo).

% Uso: swipl -g run_tests -t halt pruebas.pl

hora_caso(H, M, S, T) :- T is 2254780800 + H * 3600 + M * 60 + S.

:- begin_tests(halley).

test(tarjeta_perdida_la_uso_irene) :-
    hora_caso(1, 39, 47, T), atom_number(A, T),
    responder([quien_tarjeta, 'LP-04', A], R),
    R.estado == identificada,
    R.candidatos = [C], C.persona == valcarcel.

test(irene_seguro_en_generadores) :-
    hora_caso(1, 38, 20, T), atom_number(A, T),
    responder([donde, valcarcel, A], R),
    R.estado == seguro, R.modulos == ['GEN'].

test(quien_en_generadores) :-
    hora_caso(1, 30, 0, T1), hora_caso(1, 38, 20, T2),
    atom_number(A1, T1), atom_number(A2, T2),
    responder([quien_en, 'GEN', A1, A2], R),
    findall(P-E, ( member(D, R.personas), P = D.persona, E = D.estado ), L),
    msort(L, [kimura-no, okafor-no, petrov-no, ruiz-si, valcarcel-si, vidal-no]).

test(recorrido_en_el_corte) :-
    hora_caso(1, 45, 0, T), atom_number(A, T),
    responder([recorrido, valcarcel, 'GEN', 'EXT', A, '5'], R),
    R.estado == si, R.ruta == ['GEN', 'ALM', 'EXT'].

test(recorrido_sin_acceso_antes_del_corte) :-
    hora_caso(1, 30, 0, T), atom_number(A, T),
    responder([recorrido, valcarcel, 'GEN', 'EXT', A, '5'], R),
    R.estado == no.

test(puerta_exterior_abierta) :-
    responder([exterior, '0', '9999999999'], R),
    R.estado == abierta_probable,
    length(R.aperturas, 2).

test(persona_desconocida_no_es_falso) :-
    responder([donde, pepito, '2254786787'], R),
    R.estado == no_se_puede_saber.

test(pregunta_desconocida_siempre_responde) :-
    responder([adivina, algo], R),
    R.estado == no_reconocida.

test(el_anillo_no_cuelga_la_busqueda, [fail]) :-
    alcanza(nadie, 'COM', 'LAB-A', 2254786200, 2254786700, _).

:- end_tests(halley).