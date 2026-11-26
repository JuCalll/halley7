package halley.componentes;

import com.google.gson.JsonObject;
import halley.almacen.Correccion;
import halley.almacen.Registro;

import java.util.List;

public interface Integrador extends Componente {

    JsonObject integrar(String modo, List<Registro> registros, List<Correccion> correcciones) throws ComponenteCaido;
}
