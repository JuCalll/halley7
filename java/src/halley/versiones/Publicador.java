package halley.versiones;

import com.google.gson.JsonObject;
import halley.Rutas;
import halley.almacen.Almacen;
import halley.almacen.Correccion;
import halley.almacen.Custodia;
import halley.almacen.Registro;
import halley.componentes.ComponenteCaido;
import halley.componentes.Integrador;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public class Publicador {

    public static final List<String> MODOS = List.of("original", "corregida");

    private final Almacen almacen;
    private final Integrador integrador;
    private final Rutas rutas;
    private final AtomicReference<Version> actual = new AtomicReference<>();
    private final ScheduledExecutorService reloj = Executors.newSingleThreadScheduledExecutor();

    public Publicador(Almacen almacen, Integrador integrador, Rutas rutas) {
        this.almacen = almacen;
        this.integrador = integrador;
        this.rutas = rutas;
    }

    public void iniciar(long periodoMs) {
        almacen.ultimaVersion().ifPresent(actual::set);
        reloj.scheduleWithFixedDelay(this::publicarSinFallar, 0, periodoMs, TimeUnit.MILLISECONDS);
    }

    public Optional<Version> actual() {
        return Optional.ofNullable(actual.get());
    }

    private void publicarSinFallar() {
        try {
            publicar();
        } catch (ComponenteCaido e) {
            System.err.println("[publicador] integrador no disponible, se reintentara: " + e.getMessage());
        } catch (RuntimeException e) {
            System.err.println("[publicador] error: " + e.getMessage());
        }
    }

    public synchronized void publicar() throws ComponenteCaido {
        long ultimoRegistro = almacen.ultimoRegistro();
        long ultimaCorreccion = almacen.ultimaCorreccion();
        Version v = actual.get();
        if (ultimoRegistro == 0 || (v != null && v.ultimoRegistro() == ultimoRegistro && v.ultimaCorreccion() == ultimaCorreccion)) {
            return;
        }
        List<Registro> registros = almacen.registrosHasta(ultimoRegistro);
        List<Correccion> correcciones = almacen.correccionesHasta(ultimaCorreccion);
        JsonObject original = integrador.integrar("original", registros, correcciones);
        JsonObject corregida = integrador.integrar("corregida", registros, correcciones);
        String hechosO = original.get("hechos").getAsString();
        String hechosC = corregida.get("hechos").getAsString();
        long id = almacen.guardarVersion(ultimoRegistro, ultimaCorreccion,
                Custodia.sha256(hechosO), Custodia.sha256(hechosC), original, corregida);
        escribir(archivoHechos(id, "original"), hechosO);
        escribir(archivoHechos(id, "corregida"), hechosC);
        actual.set(almacen.version(id).orElseThrow());
        System.out.println("[publicador] version " + id + " con " + registros.size() + " registros y "
                + correcciones.size() + " correcciones");
    }

    public Path archivoHechos(long version, String modo) {
        return rutas.hechos().resolve("v" + version + "_" + modo + ".pl");
    }

    public String reconstruirHechos(Version v, String modo) throws ComponenteCaido {
        JsonObject r = integrador.integrar(modo, almacen.registrosHasta(v.ultimoRegistro()),
                almacen.correccionesHasta(v.ultimaCorreccion()));
        return r.get("hechos").getAsString();
    }

    public Path hechosDe(Version v, String modo) throws ComponenteCaido {
        Path archivo = archivoHechos(v.id(), modo);
        try {
            if (Files.exists(archivo) && Custodia.sha256(Files.readString(archivo, StandardCharsets.UTF_8)).equals(v.hashDe(modo))) {
                return archivo;
            }
        } catch (IOException e) {
            System.err.println("[publicador] no se pudo leer " + archivo + ": " + e.getMessage());
        }
        String hechos = reconstruirHechos(v, modo);
        if (!Custodia.sha256(hechos).equals(v.hashDe(modo))) {
            throw new ComponenteCaido("los hechos reconstruidos de la version " + v.id() + " no coinciden con su hash");
        }
        escribir(archivo, hechos);
        return archivo;
    }

    private static void escribir(Path archivo, String texto) {
        try {
            Files.createDirectories(archivo.getParent());
            Path tmp = archivo.resolveSibling(archivo.getFileName() + ".tmp");
            Files.writeString(tmp, texto, StandardCharsets.UTF_8);
            Files.move(tmp, archivo, java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo escribir " + archivo + ": " + e.getMessage(), e);
        }
    }
}
