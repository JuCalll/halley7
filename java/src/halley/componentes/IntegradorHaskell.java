package halley.componentes;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import halley.almacen.Correccion;
import halley.almacen.Registro;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public class IntegradorHaskell implements Integrador {

    private final Path ejecutable;
    private final Salud salud = new Salud();

    public IntegradorHaskell(Path ejecutable) {
        this.ejecutable = ejecutable;
    }

    @Override
    public String nombre() {
        return "integrador (Haskell)";
    }

    @Override
    public JsonObject estado() {
        return salud.comoJson(nombre());
    }

    @Override
    public JsonObject integrar(String modo, List<Registro> registros, List<Correccion> correcciones) throws ComponenteCaido {
        if (!Files.isExecutable(ejecutable)) {
            salud.mal("no se encuentra " + ejecutable);
            throw new ComponenteCaido("no se encuentra " + ejecutable);
        }
        try {
            Procesos.Salida s = Procesos.ejecutar(List.of(ejecutable.toString()), peticion(modo, registros, correcciones).toString(), 30);
            if (s.codigo() != 0) {
                salud.mal("termino con error: " + s.errores().strip());
                throw new ComponenteCaido("el integrador termino con error: " + s.errores().strip());
            }
            JsonObject resultado = JsonParser.parseString(s.texto()).getAsJsonObject();
            salud.bien("integro " + registros.size() + " registros");
            return resultado;
        } catch (IOException e) {
            salud.mal(e.getMessage());
            throw new ComponenteCaido(e.getMessage());
        } catch (ComponenteCaido e) {
            salud.mal(e.getMessage());
            throw e;
        } catch (RuntimeException e) {
            salud.mal("salida invalida: " + e.getMessage());
            throw new ComponenteCaido("salida invalida del integrador");
        }
    }

    private static JsonObject peticion(String modo, List<Registro> registros, List<Correccion> correcciones) {
        JsonObject o = new JsonObject();
        o.addProperty("modo", modo);
        JsonArray regs = new JsonArray();
        for (Registro r : registros) {
            JsonObject j = new JsonObject();
            j.addProperty("id", r.id());
            j.addProperty("fuente", r.fuente());
            j.addProperty("num", r.num());
            j.addProperty("texto", r.texto());
            regs.add(j);
        }
        o.add("registros", regs);
        JsonArray cs = new JsonArray();
        for (Correccion c : correcciones) {
            JsonObject j = new JsonObject();
            j.addProperty("id", c.id());
            j.addProperty("tipo", c.tipo());
            if (c.fuente() != null) j.addProperty("fuente", c.fuente());
            if (c.dispositivo() != null) j.addProperty("dispositivo", c.dispositivo());
            if (c.segundos() != null) j.addProperty("segundos", c.segundos());
            if (c.registro() != null) j.addProperty("registro", c.registro());
            j.addProperty("motivo", c.motivo());
            cs.add(j);
        }
        o.add("correcciones", cs);
        return o;
    }
}
