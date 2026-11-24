package halley.versiones;

public record Version(long id, long ultimoRegistro, long ultimaCorreccion,
                      String hashOriginal, String hashCorregida, String creadaEn) {

    public String hashDe(String modo) {
        return "corregida".equals(modo) ? hashCorregida : hashOriginal;
    }
}
