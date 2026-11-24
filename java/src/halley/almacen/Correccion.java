package halley.almacen;

public record Correccion(long id, String agencia, String tipo, String fuente, String dispositivo,
                         Long segundos, Long registro, String motivo, String creadaEn,
                         String hashAnterior, String hash) {
}