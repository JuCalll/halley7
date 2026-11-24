package halley.almacen;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import halley.versiones.Version;

import java.util.List;
import java.util.Optional;

public interface Almacen {

    long agregarRegistro(String fuente, int num, String texto, String origen, String emisor, Long seq);

    Optional<Long> registroDeEmisor(String emisor, long seq);

    long contarRegistros();

    long ultimoRegistro();

    List<Registro> registrosHasta(long ultimo);

    long agregarCorreccion(String agencia, String tipo, String fuente, String dispositivo,
                           Long segundos, Long registro, String motivo);

    long ultimaCorreccion();

    List<Correccion> correccionesHasta(long ultima);

    long guardarVersion(long ultimoRegistro, long ultimaCorreccion, String hashOriginal, String hashCorregida,
                        JsonObject original, JsonObject corregida);

    Optional<Version> version(long id);

    Optional<Version> ultimaVersion();

    JsonArray eventos(long version, String modo, long desdeRegistro);

    JsonArray problemas(long version, String modo);

    JsonArray deducciones(long version, String modo);

    JsonArray personas();

    JsonArray correcciones();

    long guardarConsulta(String investigador, String tipo, JsonObject parametros, String modo, long version,
                         JsonObject respuesta, String hechosHash);

    Optional<JsonObject> consulta(long id);

    JsonArray consultas();

    JsonObject verificarCustodia();
}
