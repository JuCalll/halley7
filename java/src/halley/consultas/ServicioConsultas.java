package halley.consultas;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import halley.almacen.Almacen;
import halley.almacen.Custodia;
import halley.componentes.ComponenteCaido;
import halley.componentes.Razonador;
import halley.versiones.Publicador;
import halley.versiones.Version;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioConsultas {

    private final Almacen almacen;
    private final Publicador publicador;
    private final Razonador razonador;
    private final Map<String, CompletableFuture<JsonObject>> respuestas = new ConcurrentHashMap<>();

    public ServicioConsultas(Almacen almacen, Publicador publicador, Razonador razonador) {
        this.almacen = almacen;
        this.publicador = publicador;
        this.razonador = razonador;
    }

    public JsonObject preguntar(String investigador, String tipo, JsonObject parametros, String modo) {
        String m = "corregida".equals(modo) ? "corregida" : "original";
        Optional<Version> actual = publicador.actual();
        if (actual.isEmpty()) {
            return sinGuardar(tipo, m, aviso("sin_respuesta", "Todavia no hay evidencia integrada. Intente en unos segundos."));
        }
        Version v = actual.get();
        JsonObject respuesta;
        JsonObject usados;
        try {
            Pregunta p = Pregunta.desde(tipo, parametros == null ? new JsonObject() : parametros);
            usados = p.parametros();
            String clave = v.id() + "|" + m + "|" + String.join(" ", p.argumentos());
            CompletableFuture<JsonObject> futura = respuestas.computeIfAbsent(clave,
                    k -> CompletableFuture.supplyAsync(() -> razonar(v, m, p)));
            respuesta = futura.join();
            if ("sin_respuesta".equals(estadoDe(respuesta))) {
                respuestas.remove(clave, futura);
            }
        } catch (Pregunta.Invalida e) {
            usados = parametros == null ? new JsonObject() : parametros;
            respuesta = aviso("no_reconocida", e.getMessage());
        }
        long id = almacen.guardarConsulta(nombre(investigador), tipo == null ? "desconocida" : tipo, usados, m, v.id(),
                respuesta, v.hashDe(m));
        JsonObject o = new JsonObject();
        o.addProperty("consulta", id);
        o.addProperty("version", v.id());
        o.addProperty("modo", m);
        o.addProperty("tipo", tipo);
        o.add("parametros", usados);
        o.add("respuesta", respuesta);
        return o;
    }

    private JsonObject razonar(Version v, String modo, Pregunta p) {
        try {
            Path hechos = publicador.hechosDe(v, modo);
            return razonador.responder(hechos, p.argumentos());
        } catch (ComponenteCaido e) {
            return aviso("sin_respuesta", "No se pudieron preparar los hechos de la version " + v.id() + ": " + e.getMessage());
        }
    }

    public JsonObject reconstruir(long consultaId) {
        JsonObject resultado = new JsonObject();
        Optional<JsonObject> guardada = almacen.consulta(consultaId);
        if (guardada.isEmpty()) {
            resultado.addProperty("error", "No existe la consulta " + consultaId);
            return resultado;
        }
        JsonObject c = guardada.get();
        Version v = almacen.version(c.get("version").getAsLong()).orElseThrow();
        String modo = c.get("modo").getAsString();
        resultado.addProperty("consulta", consultaId);
        resultado.addProperty("version", v.id());
        resultado.addProperty("modo", modo);
        resultado.addProperty("registros_usados", v.ultimoRegistro());
        resultado.addProperty("correcciones_usadas", v.ultimaCorreccion());
        try {
            String hechos = publicador.reconstruirHechos(v, modo);
            String hashHechos = Custodia.sha256(hechos);
            resultado.addProperty("hechos_identicos", hashHechos.equals(c.get("hash_hechos").getAsString()));
            Path tmp = Files.createTempFile("halley-reconstruccion-", ".pl");
            Files.writeString(tmp, hechos, StandardCharsets.UTF_8);
            Pregunta p = Pregunta.desde(c.get("tipo").getAsString(), c.getAsJsonObject("parametros"));
            JsonObject nueva = razonador.responder(tmp, p.argumentos());
            Files.deleteIfExists(tmp);
            String json = nueva.toString();
            resultado.addProperty("respuesta_identica", Custodia.sha256(json).equals(c.get("hash_respuesta").getAsString()));
            resultado.add("respuesta_original", c.get("respuesta"));
            resultado.add("respuesta_reconstruida", JsonParser.parseString(json));
        } catch (ComponenteCaido | IOException e) {
            resultado.addProperty("error", "No se pudo reconstruir: " + e.getMessage());
        } catch (Pregunta.Invalida e) {
            resultado.addProperty("hechos_identicos", true);
            resultado.addProperty("respuesta_identica", true);
            resultado.addProperty("nota", "La pregunta era invalida; su respuesta no depende de la evidencia.");
        }
        return resultado;
    }

    private static String nombre(String investigador) {
        return investigador == null || investigador.isBlank() ? "anonimo" : investigador.strip();
    }

    private static String estadoDe(JsonObject r) {
        return r.has("estado") ? r.get("estado").getAsString() : "";
    }

    private static JsonObject aviso(String estado, String resumen) {
        JsonObject o = new JsonObject();
        o.addProperty("estado", estado);
        o.addProperty("resumen", resumen);
        o.add("evidencia", new JsonArray());
        return o;
    }

    private static JsonObject sinGuardar(String tipo, String modo, JsonObject respuesta) {
        JsonObject o = new JsonObject();
        o.addProperty("tipo", tipo);
        o.addProperty("modo", modo);
        o.add("respuesta", respuesta);
        return o;
    }
}
