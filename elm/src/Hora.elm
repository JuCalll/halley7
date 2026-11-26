module Hora exposing (aEpoch, inicioDelCaso, texto)

-- Hora del caso (UTC)


inicioDelCaso : Int
inicioDelCaso =
    2254780800


texto : Int -> String
texto epoch =
    let
        enDia =
            modBy 86400 epoch

        dias =
            (epoch - inicioDelCaso) // 86400

        fecha =
            if epoch >= inicioDelCaso && dias == 0 then
                ""

            else
                fechaCivil (epoch // 86400) ++ " "
    in
    fecha ++ dos (enDia // 3600) ++ ":" ++ dos (modBy 60 (enDia // 60)) ++ ":" ++ dos (modBy 60 enDia)


dos : Int -> String
dos n =
    String.padLeft 2 '0' (String.fromInt n)


fechaCivil : Int -> String
fechaCivil diasDesde1970 =
    let
        z =
            diasDesde1970 + 719468

        era =
            z // 146097

        doe =
            z - era * 146097

        yoe =
            (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365

        doy =
            doe - (365 * yoe + yoe // 4 - yoe // 100)

        mp =
            (5 * doy + 2) // 153

        dia =
            doy - (153 * mp + 2) // 5 + 1

        mes =
            if mp < 10 then
                mp + 3

            else
                mp - 9
    in
    dos dia ++ "/" ++ dos mes


aEpoch : String -> Maybe Int
aEpoch txt =
    case List.map String.toInt (String.split ":" (String.trim txt)) of
        [ Just h, Just m ] ->
            valida h m 0

        [ Just h, Just m, Just s ] ->
            valida h m s

        _ ->
            Nothing


valida : Int -> Int -> Int -> Maybe Int
valida h m s =
    if h >= 0 && h < 24 && m >= 0 && m < 60 && s >= 0 && s < 60 then
        Just (inicioDelCaso + h * 3600 + m * 60 + s)

    else
        Nothing
