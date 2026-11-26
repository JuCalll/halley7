package halley.componentes;

import com.google.gson.JsonObject;

public interface Componente {

    String nombre();

    JsonObject estado();
}
