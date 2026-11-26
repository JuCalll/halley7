package halley.componentes;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public class RazonadorProlog implements Razonador {

    private final String swipl;
    private final Path programa;
    private final Salud salud = new Salud();

    public RazonadorProlog(String swipl, Path programa) {
        this.swipl = swipl;
        this.programa = programa;
    }

    @Override
    public String nombre() {
        return "razonador (Prolog)";
    }

    @Override
    public JsonObject estado() {
        return salud.comoJson(nombre());
    }

    @Override
    public JsonObject responder(Path hechos, List<String> pregunta) {
        List<String> comando = new ArrayList<>(List.of(swipl, programa.toString(), "--", hechos.toString()));
        comando.addAll(pregunta);
        try {
            Procesos.Salida s = Procesos.ejecutar(comando, null, 8);
            String linea = s.texto().strip();
            if (linea.isEmpty()) {
                salud.mal("respuesta vacia: " + s.errores().strip());
                return sinRespuesta("El razonador no devolvio respuesta.");
            }
            JsonObject r = JsonParser.parseString(linea.substring(linea.lastIndexOf('\n') + 1)).getAsJsonObject();
            salud.bien("respondio " + pregunta.get(0));
            return r;
        } catch (IOException e) {
            salud.mal("no se pudo ejecutar " + swipl + ": " + e.getMessage());
            return sinRespuesta("El razonador (Prolog) no esta disponible ahora. La pregunta quedo registrada.");
        } catch (ComponenteCaido e) {
            salud.mal(e.getMessage());
            return sinRespuesta("El razonador " + e.getMessage() + ".");
        } catch (RuntimeException e) {
            salud.mal("salida invalida: " + e.getMessage());
            return sinRespuesta("El razonador devolvio una respuesta ilegible.");
        }
    }

    private static JsonObject sinRespuesta(String resumen) {
        JsonObject o = new JsonObject();
        o.addProperty("estado", "sin_respuesta");
        o.addProperty("resumen", resumen);
        o.add("evidencia", new JsonArray());
        return o;
    }
}
