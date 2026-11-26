package halley;

import halley.almacen.Almacen;
import halley.almacen.AlmacenSqlite;
import halley.api.Api;
import halley.componentes.IntegradorHaskell;
import halley.componentes.RazonadorProlog;
import halley.consultas.ServicioConsultas;
import halley.versiones.Publicador;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public class Servidor {

    private static final List<String[]> ARCHIVOS = List.of(
            new String[]{"personal", "personal.csv"},
            new String[]{"estacion", "estacion.csv"},
            new String[]{"tarjetas", "tarjetas.csv"},
            new String[]{"radio", "radio.txt"},
            new String[]{"energia", "energia.json"},
            new String[]{"presencia", "presencia.csv"},
            new String[]{"temperatura", "temperatura.csv"},
            new String[]{"bitacora", "bitacora.txt"});

    public static void main(String[] args) throws IOException {
        Path raiz = Path.of(opcion(args, "--raiz", ".")).toAbsolutePath().normalize();
        int puerto = Integer.parseInt(opcion(args, "--puerto", "8080"));
        Rutas rutas = new Rutas(raiz);
        Files.createDirectories(rutas.hechos());

        Almacen almacen = new AlmacenSqlite(rutas.baseDatos());
        if (almacen.contarRegistros() == 0) {
            cargarArchivos(almacen, rutas.datos());
        }
        IntegradorHaskell integrador = new IntegradorHaskell(rutas.integrador());
        RazonadorProlog razonador = new RazonadorProlog(opcion(args, "--swipl", "swipl"), rutas.razonador());
        Publicador publicador = new Publicador(almacen, integrador, rutas);
        ServicioConsultas consultas = new ServicioConsultas(almacen, publicador, razonador);

        publicador.iniciar(1000);
        new Api(almacen, publicador, consultas, List.of(integrador, razonador), rutas).iniciar(puerto);
        System.out.println("Halley-7 listo en http://localhost:" + puerto);
    }

    private static void cargarArchivos(Almacen almacen, Path datos) throws IOException {
        for (String[] a : ARCHIVOS) {
            String contenido = Files.readString(datos.resolve(a[1]), StandardCharsets.UTF_8);
            if (a[0].equals("energia")) {
                almacen.agregarRegistro(a[0], 1, contenido, "archivo", null, null);
            } else {
                String[] lineas = contenido.split("\n", -1);
                int total = lineas.length;
                if (total > 0 && lineas[total - 1].isEmpty()) {
                    total--;
                }
                for (int i = 0; i < total; i++) {
                    almacen.agregarRegistro(a[0], i + 1, lineas[i], "archivo", null, null);
                }
            }
        }
        System.out.println("Evidencia original cargada: " + almacen.contarRegistros() + " registros");
    }

    private static String opcion(String[] args, String nombre, String porDefecto) {
        for (int i = 0; i + 1 < args.length; i++) {
            if (args[i].equals(nombre)) {
                return args[i + 1];
            }
        }
        return porDefecto;
    }
}
