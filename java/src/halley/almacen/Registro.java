package halley.almacen;

public record Registro(long id, String fuente, int num, String texto, String origen,
                       String emisor, Long seq, String recibidoEn, String hashAnterior, String hash) {
}
