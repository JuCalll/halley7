package halley.componentes;

import com.google.gson.JsonObject;

import java.nio.file.Path;
import java.util.List;

public interface Razonador extends Componente {

    JsonObject responder(Path hechos, List<String> pregunta);
}
