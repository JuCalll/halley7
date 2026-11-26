package halley.componentes;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

final class Procesos {

    private Procesos() {
    }

    record Salida(int codigo, String texto, String errores) {
    }

    static Salida ejecutar(List<String> comando, String entrada, long segundos) throws IOException, ComponenteCaido {
        Process p = new ProcessBuilder(comando).start();
        CompletableFuture<String> salida = CompletableFuture.supplyAsync(() -> leer(p.getInputStream()));
        CompletableFuture<String> errores = CompletableFuture.supplyAsync(() -> leer(p.getErrorStream()));
        try (OutputStream os = p.getOutputStream()) {
            if (entrada != null) {
                os.write(entrada.getBytes(StandardCharsets.UTF_8));
            }
        }
        try {
            if (!p.waitFor(segundos, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                throw new ComponenteCaido("no respondio en " + segundos + " s y se detuvo");
            }
            return new Salida(p.exitValue(), salida.get(), errores.get());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            p.destroyForcibly();
            throw new ComponenteCaido("interrumpido");
        } catch (java.util.concurrent.ExecutionException e) {
            throw new ComponenteCaido("no se pudo leer la salida: " + e.getMessage());
        }
    }

    private static String leer(InputStream in) {
        try (in) {
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            in.transferTo(buf);
            return buf.toString(StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }
}
