package halley;

import java.nio.file.Path;

public record Rutas(Path raiz) {

    private static boolean esWindows() {
        return System.getProperty("os.name").toLowerCase().contains("win");
    }

    public Path datos() { return raiz.resolve("datos"); }
    public Path web() { return raiz.resolve("web"); }
    public Path trabajo() { return raiz.resolve("trabajo"); }
    public Path baseDatos() { return trabajo().resolve("halley.db"); }
    public Path hechos() { return trabajo().resolve("hechos"); }
    public Path integrador() { return raiz.resolve("bin").resolve(esWindows() ? "integrador.exe" : "integrador"); }
    public Path razonador() { return raiz.resolve("prolog").resolve("razonador.pl"); }
}
