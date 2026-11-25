import halley.almacen.*;
import java.nio.file.Path;
var a = new AlmacenSqlite(Path.of("trabajo/prueba/halley.db"));
a.agregarRegistro("tarjetas", 26, "2041-06-14T01:39:47,LP-04,P7,GEN,ALM,OK", "archivo", null, null);
var r1 = a.agregarRegistro("presencia", 1, "2041-06-14T03:00:00,COM,2", "vivo", "simulador", 1L);
var r2 = a.agregarRegistro("presencia", 1, "2041-06-14T03:00:00,COM,2", "vivo", "simulador", 1L);
System.out.println("mismo id al repetir: " + (r1 == r2) + ", registros: " + a.contarRegistros());
a.agregarCorreccion("Agencia Polar", "desfase_reloj", "radio", null, -420L, null, "la radio va 7 minutos adelantada");
System.out.println(a.verificarCustodia());
/exit
