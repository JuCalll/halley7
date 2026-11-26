package halley.componentes;

import com.google.gson.JsonObject;

import java.time.Instant;

final class Salud {

    private volatile boolean disponible = true;
    private volatile String mensaje = "sin uso todavia";
    private volatile String cuando = Instant.now().toString();

    void bien(String m) {
        disponible = true;
        mensaje = m;
        cuando = Instant.now().toString();
    }

    void mal(String m) {
        disponible = false;
        mensaje = m;
        cuando = Instant.now().toString();
    }

    JsonObject comoJson(String nombre) {
        JsonObject o = new JsonObject();
        o.addProperty("nombre", nombre);
        o.addProperty("disponible", disponible);
        o.addProperty("mensaje", mensaje);
        o.addProperty("desde", cuando);
        return o;
    }
}
