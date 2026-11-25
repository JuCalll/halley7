import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

// Servidor de prueba para el simulador: imprime cada lectura que recibe en /api/vivo
public class Receptor {

    public static void main(String[] args) throws IOException {
        HttpServer servidor = HttpServer.create(new InetSocketAddress(8080), 0);
        servidor.createContext("/api/vivo", intercambio -> {
            String cuerpo = new String(intercambio.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            System.out.println("recibida " + cuerpo);
            byte[] respuesta = "{\"ok\":true}".getBytes(StandardCharsets.UTF_8);
            intercambio.sendResponseHeaders(200, respuesta.length);
            try (OutputStream salida = intercambio.getResponseBody()) {
                salida.write(respuesta);
            }
        });
        servidor.start();
        System.out.println("Receptor de prueba en http://localhost:8080/api/vivo");
    }
}
