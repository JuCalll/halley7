package halley.simulador;

import com.google.gson.JsonObject;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;

public class Simulador {

    record Lectura(long seq, String fuente, String texto) {
    }

    public static void main(String[] args) throws IOException, InterruptedException {
        String url = opcion(args, "--url", "http://localhost:8080");
        double velocidad = Double.parseDouble(opcion(args, "--velocidad", "1"));
        Path escenario = Path.of(opcion(args, "--escenario", "datos/simulacion.txt"));
        String emisor = opcion(args, "--emisor", "simulador-1");

        List<Lectura> lecturas = leer(escenario);
        HttpClient cliente = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
        long pausa = (long) (1000 / Math.max(velocidad, 0.01));
        System.out.println("Simulador: " + lecturas.size() + " lecturas a " + velocidad + " por segundo hacia " + url);
        for (Lectura l : lecturas) {
            enviarHastaConfirmar(cliente, url, emisor, l);
            Thread.sleep(pausa);
        }
        System.out.println("Simulador: escenario completo");
    }

    private static List<Lectura> leer(Path escenario) throws IOException {
        List<String> lineas = Files.readAllLines(escenario, StandardCharsets.UTF_8);
        return java.util.stream.IntStream.range(0, lineas.size())
                .filter(i -> !lineas.get(i).isBlank() && !lineas.get(i).startsWith("#"))
                .mapToObj(i -> {
                    String[] partes = lineas.get(i).split("\\|", 2);
                    return new Lectura(i + 1, partes[0].strip(), partes[1].strip());
                })
                .toList();
    }

    private static void enviarHastaConfirmar(HttpClient cliente, String url, String emisor, Lectura l) throws InterruptedException {
        JsonObject cuerpo = new JsonObject();
        cuerpo.addProperty("emisor", emisor);
        cuerpo.addProperty("seq", l.seq());
        cuerpo.addProperty("fuente", l.fuente());
        cuerpo.addProperty("texto", l.texto());
        HttpRequest peticion = HttpRequest.newBuilder(URI.create(url + "/api/vivo"))
                .timeout(Duration.ofSeconds(5))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo.toString(), StandardCharsets.UTF_8))
                .build();
        long espera = 500;
        while (true) {
            try {
                HttpResponse<String> r = cliente.send(peticion, HttpResponse.BodyHandlers.ofString());
                if (r.statusCode() == 200) {
                    System.out.println("enviada " + l.seq() + " " + l.fuente() + ": " + l.texto());
                    return;
                }
                System.out.println("rechazada " + l.seq() + " (" + r.statusCode() + "): " + r.body());
                return;
            } catch (IOException e) {
                System.out.println("servidor no disponible, reintento la lectura " + l.seq() + " en " + espera + " ms");
                Thread.sleep(espera);
                espera = Math.min(espera * 2, 5000);
            }
        }
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
