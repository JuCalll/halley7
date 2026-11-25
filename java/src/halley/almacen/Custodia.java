package halley.almacen;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

public final class Custodia {

    public static final String GENESIS = "0".repeat(64);

    private Custodia() {
    }

    public static String sha256(String texto) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(md.digest(texto.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public static String hashRegistro(String anterior, String fuente, int num, String texto, String origen,
                                      String emisor, Long seq, String recibidoEn) {
        return sha256(String.join("|", anterior, fuente, String.valueOf(num), texto, origen,
                String.valueOf(emisor), String.valueOf(seq), recibidoEn));
    }

    public static String hashRegistro(Registro r) {
        return hashRegistro(r.hashAnterior(), r.fuente(), r.num(), r.texto(), r.origen(), r.emisor(), r.seq(), r.recibidoEn());
    }

    public static String hashCorreccion(String anterior, String agencia, String tipo, String fuente, String dispositivo,
                                        Long segundos, Long registro, String motivo, String creadaEn) {
        return sha256(String.join("|", anterior, agencia, tipo, String.valueOf(fuente), String.valueOf(dispositivo),
                String.valueOf(segundos), String.valueOf(registro), motivo, creadaEn));
    }

    public static String hashCorreccion(Correccion c) {
        return hashCorreccion(c.hashAnterior(), c.agencia(), c.tipo(), c.fuente(), c.dispositivo(),
                c.segundos(), c.registro(), c.motivo(), c.creadaEn());
    }
}
