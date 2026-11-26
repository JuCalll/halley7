package halley.api;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import halley.Rutas;
import halley.almacen.Almacen;
import halley.componentes.Componente;
import halley.consultas.ServicioConsultas;
import halley.versiones.Publicador;
import halley.versiones.Version;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.Executors;

public class Api {

    private static final Set<String> FUENTES_EN_VIVO = Set.of("tarjetas", "presencia", "temperatura");

    private final Almacen almacen;
    private final Publicador publicador;
    private final ServicioConsultas consultas;
    private final List<Componente> componentes;
    private final Rutas rutas;

    public Api(Almacen almacen, Publicador publicador, ServicioConsultas consultas, List<Componente> componentes, Rutas rutas) {
        this.almacen = almacen;
        this.publicador = publicador;
        this.consultas = consultas;
        this.componentes = componentes;
        this.rutas = rutas;
    }

    public void iniciar(int puerto) throws IOException {
        HttpServer servidor = HttpServer.create(new InetSocketAddress(puerto), 0);
        servidor.createContext("/api/", this::api);
        servidor.createContext("/", this::estatico);
        servidor.setExecutor(Executors.newFixedThreadPool(16));
        servidor.start();
    }

    // Enrutamiento

    private void api(HttpExchange ex) throws IOException {
        try {
            String ruta = ex.getRequestURI().getPath();
            String metodo = ex.getRequestMethod();
            Map<String, String> q = parametros(ex.getRequestURI().getRawQuery());
            if (metodo.equals("GET") && ruta.equals("/api/estado")) {
                enviar(ex, 200, estado());
            } else if (metodo.equals("GET") && ruta.equals("/api/referencia")) {
                enviar(ex, 200, referencia());
            } else if (metodo.equals("GET") && ruta.equals("/api/linea")) {
                enviar(ex, 200, linea(q.getOrDefault("modo", "original"), q.get("version")));
            } else if (metodo.equals("GET") && ruta.equals("/api/novedades")) {
                enviar(ex, 200, novedades(Long.parseLong(q.getOrDefault("desde", "0"))));
            } else if (metodo.equals("POST") && ruta.equals("/api/vivo")) {
                vivo(ex);
            } else if (metodo.equals("POST") && ruta.equals("/api/consultas")) {
                JsonObject c = cuerpo(ex);
                enviar(ex, 200, consultas.preguntar(texto(c, "investigador"), texto(c, "tipo"),
                        c.has("parametros") ? c.getAsJsonObject("parametros") : new JsonObject(), texto(c, "modo")));
            } else if (metodo.equals("GET") && ruta.equals("/api/consultas")) {
                enviar(ex, 200, almacen.consultas());
            } else if (metodo.equals("GET") && ruta.matches("/api/consultas/\\d+/reconstruccion")) {
                long id = Long.parseLong(ruta.split("/")[3]);
                enviar(ex, 200, consultas.reconstruir(id));
            } else if (metodo.equals("POST") && ruta.equals("/api/correcciones")) {
                correccion(ex);
            } else if (metodo.equals("GET") && ruta.equals("/api/correcciones")) {
                enviar(ex, 200, almacen.correcciones());
            } else if (metodo.equals("GET") && ruta.equals("/api/custodia")) {
                enviar(ex, 200, almacen.verificarCustodia());
            } else if (metodo.equals("GET") && ruta.equals("/api/informe")) {
                enviar(ex, 200, informe(q.getOrDefault("modo", "original")));
            } else {
                enviar(ex, 404, error("Ruta desconocida: " + metodo + " " + ruta));
            }
        } catch (RuntimeException e) {
            enviar(ex, 400, error(e.getMessage() == null ? e.toString() : e.getMessage()));
        }
    }

    // Respuestas

    private JsonObject estado() {
        JsonObject o = new JsonObject();
        Optional<Version> v = publicador.actual();
        o.addProperty("version", v.map(Version::id).orElse(0L));
        o.addProperty("registros_en_version", v.map(Version::ultimoRegistro).orElse(0L));
        o.addProperty("registros_guardados", almacen.contarRegistros());
        o.addProperty("ultimo_registro", almacen.ultimoRegistro());
        o.addProperty("correcciones", almacen.ultimaCorreccion());
        JsonArray cs = new JsonArray();
        for (Componente c : componentes) {
            cs.add(c.estado());
        }
        o.add("componentes", cs);
        return o;
    }

    private JsonObject referencia() {
        JsonObject o = new JsonObject();
        o.add("personas", almacen.personas());
        JsonArray modulos = new JsonArray();
        for (String m : List.of("COM", "DOR", "LAB-A", "LAB-B", "GEN", "RAD", "ALM", "EXT")) {
            modulos.add(m);
        }
        o.add("modulos", modulos);
        return o;
    }

    private JsonObject linea(String modo, String version) {
        long id = version == null ? publicador.actual().map(Version::id).orElse(0L) : Long.parseLong(version);
        JsonObject o = new JsonObject();
        o.addProperty("version", id);
        o.addProperty("modo", modo);
        o.add("eventos", almacen.eventos(id, modo, 0));
        o.add("problemas", almacen.problemas(id, modo));
        o.add("deducciones", almacen.deducciones(id, modo));
        return o;
    }

    private JsonObject novedades(long desde) {
        Optional<Version> v = publicador.actual();
        JsonObject o = new JsonObject();
        o.addProperty("version", v.map(Version::id).orElse(0L));
        o.addProperty("hasta", v.map(Version::ultimoRegistro).orElse(0L));
        o.add("eventos", v.map(x -> almacen.eventos(x.id(), "original", desde)).orElse(new JsonArray()));
        return o;
    }

    private void vivo(HttpExchange ex) throws IOException {
        JsonObject c = cuerpo(ex);
        String emisor = texto(c, "emisor");
        String fuente = texto(c, "fuente");
        String linea = texto(c, "texto");
        if (emisor == null || fuente == null || linea == null || !c.has("seq")) {
            enviar(ex, 400, error("Faltan datos: emisor, seq, fuente y texto son obligatorios."));
            return;
        }
        if (!FUENTES_EN_VIVO.contains(fuente) || linea.contains("\n")) {
            enviar(ex, 400, error("Solo se reciben en vivo lineas de tarjetas, presencia o temperatura."));
            return;
        }
        long seq = c.get("seq").getAsLong();
        boolean repetido = almacen.registroDeEmisor(emisor, seq).isPresent();
        long id = almacen.agregarRegistro(fuente, (int) seq, linea, "vivo", emisor, seq);
        JsonObject o = new JsonObject();
        o.addProperty("registro", id);
        o.addProperty("repetido", repetido);
        enviar(ex, 200, o);
    }

    private void correccion(HttpExchange ex) throws IOException {
        JsonObject c = cuerpo(ex);
        String tipo = texto(c, "tipo");
        String agencia = texto(c, "agencia");
        String motivo = texto(c, "motivo");
        if (agencia == null || motivo == null || !"desfase_reloj".equals(tipo) && !"descartar".equals(tipo)) {
            enviar(ex, 400, error("Una correccion necesita agencia, motivo y tipo (desfase_reloj o descartar)."));
            return;
        }
        Long segundos = c.has("segundos") ? c.get("segundos").getAsLong() : null;
        Long registro = c.has("registro") ? c.get("registro").getAsLong() : null;
        String fuente = texto(c, "fuente");
        if ("desfase_reloj".equals(tipo) && (fuente == null || segundos == null)) {
            enviar(ex, 400, error("Un desfase de reloj necesita la fuente y los segundos."));
            return;
        }
        if ("descartar".equals(tipo) && registro == null) {
            enviar(ex, 400, error("Para descartar hay que indicar el registro."));
            return;
        }
        long id = almacen.agregarCorreccion(agencia, tipo, fuente, texto(c, "dispositivo"), segundos, registro, motivo);
        JsonObject o = new JsonObject();
        o.addProperty("correccion", id);
        enviar(ex, 201, o);
    }

    private JsonObject informe(String modo) {
        JsonObject o = linea(modo, null);
        o.add("consultas", almacen.consultas());
        o.add("correcciones", almacen.correcciones());
        o.add("custodia", almacen.verificarCustodia());
        o.add("personas", almacen.personas());
        return o;
    }

    // Archivos del visor

    private void estatico(HttpExchange ex) throws IOException {
        String ruta = ex.getRequestURI().getPath();
        Path archivo = rutas.web().resolve(ruta.equals("/") ? "index.html" : ruta.substring(1)).normalize();
        if (!archivo.startsWith(rutas.web()) || !Files.isRegularFile(archivo)) {
            enviarTexto(ex, 404, "text/plain; charset=utf-8", "No encontrado".getBytes(StandardCharsets.UTF_8));
            return;
        }
        String tipo = archivo.toString().endsWith(".js") ? "text/javascript; charset=utf-8" : "text/html; charset=utf-8";
        enviarTexto(ex, 200, tipo, Files.readAllBytes(archivo));
    }

    // Utilidades

    private static JsonObject cuerpo(HttpExchange ex) throws IOException {
        String texto = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        JsonElement e = JsonParser.parseString(texto.isBlank() ? "{}" : texto);
        if (!e.isJsonObject()) {
            throw new IllegalArgumentException("El cuerpo debe ser un objeto JSON.");
        }
        return e.getAsJsonObject();
    }

    private static String texto(JsonObject o, String clave) {
        return o.has(clave) && !o.get(clave).isJsonNull() ? o.get(clave).getAsString() : null;
    }

    private static Map<String, String> parametros(String query) {
        Map<String, String> m = new HashMap<>();
        if (query != null) {
            for (String par : query.split("&")) {
                String[] kv = par.split("=", 2);
                m.put(URLDecoder.decode(kv[0], StandardCharsets.UTF_8), kv.length > 1 ? URLDecoder.decode(kv[1], StandardCharsets.UTF_8) : "");
            }
        }
        return m;
    }

    private static JsonObject error(String mensaje) {
        JsonObject o = new JsonObject();
        o.addProperty("error", mensaje);
        return o;
    }

    private static void enviar(HttpExchange ex, int codigo, JsonElement cuerpo) throws IOException {
        enviarTexto(ex, codigo, "application/json; charset=utf-8", cuerpo.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static void enviarTexto(HttpExchange ex, int codigo, String tipo, byte[] bytes) throws IOException {
        ex.getResponseHeaders().set("Content-Type", tipo);
        ex.getResponseHeaders().set("Cache-Control", "no-store");
        ex.sendResponseHeaders(codigo, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
