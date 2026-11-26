package halley.consultas;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

public record Pregunta(String tipo, List<String> argumentos, JsonObject parametros) {

    public static final LocalDate FECHA_CASO = LocalDate.of(2041, 6, 14);
    private static final Pattern SEGURO = Pattern.compile("[A-Za-z0-9_\\-]{1,40}");

    public static class Invalida extends Exception {
        private static final long serialVersionUID = 1L;

        public Invalida(String mensaje) {
            super(mensaje);
        }
    }

    public static Pregunta desde(String tipo, JsonObject p) throws Invalida {
        if (tipo == null) {
            throw new Invalida("Falta el tipo de pregunta.");
        }
        List<String> args = new ArrayList<>();
        args.add(tipo);
        JsonObject usados = new JsonObject();
        switch (tipo) {
            case "donde" -> {
                args.add(palabra(p, "persona", usados));
                args.add(hora(p, "hora", usados));
            }
            case "quien_en" -> {
                args.add(palabra(p, "modulo", usados));
                args.add(hora(p, "desde", usados));
                args.add(hora(p, "hasta", usados));
            }
            case "quien_tarjeta" -> {
                args.add(palabra(p, "tarjeta", usados));
                args.add(hora(p, "hora", usados));
            }
            case "recorrido" -> {
                args.add(palabra(p, "persona", usados));
                args.add(palabra(p, "origen", usados));
                args.add(palabra(p, "destino", usados));
                args.add(hora(p, "hora", usados));
                args.add(entero(p, "minutos", usados));
            }
            case "exterior" -> {
                args.add(p.has("desde") ? hora(p, "desde", usados) : "0");
                args.add(p.has("hasta") ? hora(p, "hasta", usados) : "9999999999");
            }
            default -> throw new Invalida("No reconozco la pregunta '" + tipo + "'. Tipos: donde, quien_en, quien_tarjeta, recorrido, exterior.");
        }
        return new Pregunta(tipo, args, usados);
    }

    private static String texto(JsonObject p, String clave) throws Invalida {
        JsonElement e = p.get(clave);
        if (e == null || e.isJsonNull() || e.getAsString().isBlank()) {
            throw new Invalida("Falta el dato '" + clave + "'.");
        }
        return e.getAsString().strip();
    }

    private static String palabra(JsonObject p, String clave, JsonObject usados) throws Invalida {
        String v = texto(p, clave);
        if (!SEGURO.matcher(v).matches()) {
            throw new Invalida("El dato '" + clave + "' tiene caracteres no permitidos: " + v);
        }
        usados.addProperty(clave, v);
        return v;
    }

    private static String entero(JsonObject p, String clave, JsonObject usados) throws Invalida {
        String v = texto(p, clave);
        try {
            long n = Long.parseLong(v);
            if (n < 0) {
                throw new Invalida("El dato '" + clave + "' no puede ser negativo.");
            }
            usados.addProperty(clave, n);
            return String.valueOf(n);
        } catch (NumberFormatException e) {
            throw new Invalida("El dato '" + clave + "' debe ser un numero entero: " + v);
        }
    }

    private static String hora(JsonObject p, String clave, JsonObject usados) throws Invalida {
        String v = texto(p, clave);
        usados.addProperty(clave, v);
        return String.valueOf(aEpoch(v));
    }

    public static long aEpoch(String v) throws Invalida {
        try {
            if (v.matches("\\d{9,11}")) {
                return Long.parseLong(v);
            }
            if (v.matches("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(:\\d{2})?Z?")) {
                return LocalDateTime.parse(v.replace("Z", "")).toEpochSecond(ZoneOffset.UTC);
            }
            if (v.matches("\\d{1,2}:\\d{2}(:\\d{2})?")) {
                String hhmm = v.length() == 4 || v.length() == 7 ? "0" + v : v;
                return LocalDateTime.of(FECHA_CASO, LocalTime.parse(hhmm)).toEpochSecond(ZoneOffset.UTC);
            }
        } catch (RuntimeException e) {
            throw new Invalida("Hora invalida: " + v);
        }
        throw new Invalida("Hora invalida: " + v + " (use HH:MM, HH:MM:SS o AAAA-MM-DDTHH:MM:SS, en UTC)");
    }
}
