package halley.almacen;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import halley.versiones.Version;

import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public class AlmacenSqlite implements Almacen {

    private final Connection con;

    public AlmacenSqlite(Path archivo) {
        try {
            con = DriverManager.getConnection("jdbc:sqlite:" + archivo.toAbsolutePath());
            try (Statement st = con.createStatement()) {
                st.execute("PRAGMA journal_mode=WAL");
                st.execute("PRAGMA foreign_keys=ON");
                for (String sql : Esquema.SENTENCIAS) {
                    st.execute(sql);
                }
            }
        } catch (SQLException e) {
            throw new IllegalStateException("No se pudo abrir la base de datos: " + e.getMessage(), e);
        }
    }

    private static String ahora() {
        return Instant.now().toString();
    }

    private static RuntimeException fallo(SQLException e) {
        return new IllegalStateException(e.getMessage(), e);
    }

    private long unNumero(String sql) throws SQLException {
        try (Statement st = con.createStatement(); ResultSet rs = st.executeQuery(sql)) {
            return rs.next() ? rs.getLong(1) : 0;
        }
    }

    private String ultimoHash(String tabla) throws SQLException {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery("SELECT hash FROM " + tabla + " ORDER BY id DESC LIMIT 1")) {
            return rs.next() ? rs.getString(1) : Custodia.GENESIS;
        }
    }

    // Evidencia original

    @Override
    public synchronized long agregarRegistro(String fuente, int num, String texto, String origen, String emisor, Long seq) {
        try {
            if (emisor != null && seq != null) {
                Optional<Long> ya = registroDeEmisor(emisor, seq);
                if (ya.isPresent()) {
                    return ya.get();
                }
            }
            String anterior = ultimoHash("registro");
            String recibido = ahora();
            String hash = Custodia.hashRegistro(anterior, fuente, num, texto, origen, emisor, seq, recibido);
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO registro (fuente_id, num, texto, origen, emisor, seq, recibido_en, hash_anterior, hash) "
                            + "VALUES (?,?,?,?,?,?,?,?,?) RETURNING id")) {
                ps.setString(1, fuente);
                ps.setInt(2, num);
                ps.setString(3, texto);
                ps.setString(4, origen);
                ps.setString(5, emisor);
                if (seq == null) ps.setNull(6, java.sql.Types.INTEGER); else ps.setLong(6, seq);
                ps.setString(7, recibido);
                ps.setString(8, anterior);
                ps.setString(9, hash);
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    return rs.getLong(1);
                }
            }
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized Optional<Long> registroDeEmisor(String emisor, long seq) {
        try (PreparedStatement ps = con.prepareStatement("SELECT id FROM registro WHERE emisor = ? AND seq = ?")) {
            ps.setString(1, emisor);
            ps.setLong(2, seq);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? Optional.of(rs.getLong(1)) : Optional.empty();
            }
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized long contarRegistros() {
        try {
            return unNumero("SELECT COUNT(*) FROM registro");
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized long ultimoRegistro() {
        try {
            return unNumero("SELECT COALESCE(MAX(id), 0) FROM registro");
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized List<Registro> registrosHasta(long ultimo) {
        List<Registro> lista = new ArrayList<>();
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT id, fuente_id, num, texto, origen, emisor, seq, recibido_en, hash_anterior, hash "
                        + "FROM registro WHERE id <= ? ORDER BY id")) {
            ps.setLong(1, ultimo);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    long seq = rs.getLong(7);
                    Long seqONulo = rs.wasNull() ? null : seq;
                    lista.add(new Registro(rs.getLong(1), rs.getString(2), rs.getInt(3), rs.getString(4),
                            rs.getString(5), rs.getString(6), seqONulo, rs.getString(8), rs.getString(9), rs.getString(10)));
                }
            }
            return lista;
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    // Correcciones

    @Override
    public synchronized long agregarCorreccion(String agencia, String tipo, String fuente, String dispositivo,
                                               Long segundos, Long registro, String motivo) {
        try {
            String anterior = ultimoHash("correccion");
            String creada = ahora();
            String hash = Custodia.hashCorreccion(anterior, agencia, tipo, fuente, dispositivo, segundos, registro, motivo, creada);
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO correccion (agencia, tipo, fuente_id, dispositivo, segundos, registro_id, motivo, creada_en, hash_anterior, hash) "
                            + "VALUES (?,?,?,?,?,?,?,?,?,?) RETURNING id")) {
                ps.setString(1, agencia);
                ps.setString(2, tipo);
                ps.setString(3, fuente);
                ps.setString(4, dispositivo);
                if (segundos == null) ps.setNull(5, java.sql.Types.INTEGER); else ps.setLong(5, segundos);
                if (registro == null) ps.setNull(6, java.sql.Types.INTEGER); else ps.setLong(6, registro);
                ps.setString(7, motivo);
                ps.setString(8, creada);
                ps.setString(9, anterior);
                ps.setString(10, hash);
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    return rs.getLong(1);
                }
            }
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized long ultimaCorreccion() {
        try {
            return unNumero("SELECT COALESCE(MAX(id), 0) FROM correccion");
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized List<Correccion> correccionesHasta(long ultima) {
        List<Correccion> lista = new ArrayList<>();
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT id, agencia, tipo, fuente_id, dispositivo, segundos, registro_id, motivo, creada_en, hash_anterior, hash "
                        + "FROM correccion WHERE id <= ? ORDER BY id")) {
            ps.setLong(1, ultima);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    long seg = rs.getLong(6);
                    Long segundos = rs.wasNull() ? null : seg;
                    long reg = rs.getLong(7);
                    Long registro = rs.wasNull() ? null : reg;
                    lista.add(new Correccion(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4),
                            rs.getString(5), segundos, registro, rs.getString(8), rs.getString(9),
                            rs.getString(10), rs.getString(11)));
                }
            }
            return lista;
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized JsonArray correcciones() {
        JsonArray arr = new JsonArray();
        for (Correccion c : correccionesHasta(Long.MAX_VALUE)) {
            JsonObject o = new JsonObject();
            o.addProperty("id", c.id());
            o.addProperty("agencia", c.agencia());
            o.addProperty("tipo", c.tipo());
            o.addProperty("fuente", c.fuente());
            o.addProperty("dispositivo", c.dispositivo());
            o.addProperty("segundos", c.segundos());
            o.addProperty("registro", c.registro());
            o.addProperty("motivo", c.motivo());
            o.addProperty("creada_en", c.creadaEn());
            o.addProperty("hash", c.hash());
            arr.add(o);
        }
        return arr;
    }

    // Versiones de la evidencia

    @Override
    public synchronized long guardarVersion(long ultimoRegistro, long ultimaCorreccion, String hashOriginal,
                                            String hashCorregida, JsonObject original, JsonObject corregida) {
        try {
            con.setAutoCommit(false);
            long id;
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO version (ultimo_registro, ultima_correccion, hechos_original, hechos_corregida, "
                            + "deducciones_original, deducciones_corregida, creada_en) VALUES (?,?,?,?,?,?,?) RETURNING id")) {
                ps.setLong(1, ultimoRegistro);
                ps.setLong(2, ultimaCorreccion);
                ps.setString(3, hashOriginal);
                ps.setString(4, hashCorregida);
                ps.setString(5, original.getAsJsonArray("deducciones").toString());
                ps.setString(6, corregida.getAsJsonArray("deducciones").toString());
                ps.setString(7, ahora());
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    id = rs.getLong(1);
                }
            }
            guardarPersonas(original.getAsJsonArray("personas"));
            guardarDerivados(id, "original", original);
            guardarDerivados(id, "corregida", corregida);
            con.commit();
            return id;
        } catch (SQLException e) {
            try {
                con.rollback();
            } catch (SQLException ignorada) {
                // se informa el error original
            }
            throw fallo(e);
        } finally {
            try {
                con.setAutoCommit(true);
            } catch (SQLException ignorada) {
                // la conexion sigue en uso
            }
        }
    }

    private void guardarPersonas(JsonArray personas) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(
                "INSERT INTO persona (id, nombre, cargo, tarjeta) VALUES (?,?,?,?) "
                        + "ON CONFLICT(id) DO UPDATE SET nombre = excluded.nombre, cargo = excluded.cargo, tarjeta = excluded.tarjeta")) {
            for (JsonElement e : personas) {
                JsonObject p = e.getAsJsonObject();
                ps.setString(1, p.get("id").getAsString());
                ps.setString(2, p.get("nombre").getAsString());
                ps.setString(3, p.get("cargo").getAsString());
                ps.setString(4, p.get("tarjeta").getAsString());
                ps.addBatch();
            }
            ps.executeBatch();
        }
    }

    private void guardarDerivados(long version, String modo, JsonObject resultado) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(
                "INSERT INTO evento (version_id, modo, id, registro_id, ts, tipo, persona_id, modulo, descripcion, json) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,?)")) {
            for (JsonElement e : resultado.getAsJsonArray("eventos")) {
                JsonObject ev = e.getAsJsonObject();
                ps.setLong(1, version);
                ps.setString(2, modo);
                ps.setString(3, ev.get("id").getAsString());
                ps.setLong(4, ev.get("registro").getAsLong());
                ps.setLong(5, ev.get("ts").getAsLong());
                ps.setString(6, ev.get("tipo").getAsString());
                ps.setString(7, ev.has("persona") ? ev.get("persona").getAsString() : null);
                ps.setString(8, ev.has("modulo") ? ev.get("modulo").getAsString()
                        : ev.has("hacia") ? ev.get("hacia").getAsString() : null);
                ps.setString(9, ev.get("descripcion").getAsString());
                ps.setString(10, ev.toString());
                ps.addBatch();
            }
            ps.executeBatch();
        }
        try (PreparedStatement ps = con.prepareStatement(
                "INSERT INTO problema (version_id, modo, registro_id, tipo, motivo, usado) VALUES (?,?,?,?,?,?)")) {
            for (JsonElement e : resultado.getAsJsonArray("problemas")) {
                JsonObject p = e.getAsJsonObject();
                ps.setLong(1, version);
                ps.setString(2, modo);
                ps.setLong(3, p.get("registro").getAsLong());
                ps.setString(4, p.get("tipo").getAsString());
                ps.setString(5, p.get("motivo").getAsString());
                ps.setInt(6, p.get("usado").getAsBoolean() ? 1 : 0);
                ps.addBatch();
            }
            ps.executeBatch();
        }
    }

    private Version leerVersion(ResultSet rs) throws SQLException {
        return new Version(rs.getLong(1), rs.getLong(2), rs.getLong(3), rs.getString(4), rs.getString(5), rs.getString(6));
    }

    @Override
    public synchronized Optional<Version> version(long id) {
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT id, ultimo_registro, ultima_correccion, hechos_original, hechos_corregida, creada_en FROM version WHERE id = ?")) {
            ps.setLong(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? Optional.of(leerVersion(rs)) : Optional.empty();
            }
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized Optional<Version> ultimaVersion() {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(
                     "SELECT id, ultimo_registro, ultima_correccion, hechos_original, hechos_corregida, creada_en "
                             + "FROM version ORDER BY id DESC LIMIT 1")) {
            return rs.next() ? Optional.of(leerVersion(rs)) : Optional.empty();
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized JsonArray eventos(long version, String modo, long desdeRegistro) {
        JsonArray arr = new JsonArray();
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT json FROM evento WHERE version_id = ? AND modo = ? AND registro_id > ? ORDER BY ts, registro_id, id")) {
            ps.setLong(1, version);
            ps.setString(2, modo);
            ps.setLong(3, desdeRegistro);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    arr.add(JsonParser.parseString(rs.getString(1)));
                }
            }
            return arr;
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized JsonArray problemas(long version, String modo) {
        JsonArray arr = new JsonArray();
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT p.registro_id, r.fuente_id, p.tipo, p.motivo, p.usado, r.texto FROM problema p "
                        + "JOIN registro r ON r.id = p.registro_id WHERE p.version_id = ? AND p.modo = ? ORDER BY p.registro_id, p.id")) {
            ps.setLong(1, version);
            ps.setString(2, modo);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    JsonObject o = new JsonObject();
                    o.addProperty("registro", rs.getLong(1));
                    o.addProperty("fuente", rs.getString(2));
                    o.addProperty("tipo", rs.getString(3));
                    o.addProperty("motivo", rs.getString(4));
                    o.addProperty("usado", rs.getInt(5) == 1);
                    o.addProperty("original", rs.getString(6).length() > 160 ? rs.getString(6).substring(0, 160) + "..." : rs.getString(6));
                    arr.add(o);
                }
            }
            return arr;
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized JsonArray deducciones(long version, String modo) {
        String columna = "corregida".equals(modo) ? "deducciones_corregida" : "deducciones_original";
        try (PreparedStatement ps = con.prepareStatement("SELECT " + columna + " FROM version WHERE id = ?")) {
            ps.setLong(1, version);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? JsonParser.parseString(rs.getString(1)).getAsJsonArray() : new JsonArray();
            }
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized JsonArray personas() {
        JsonArray arr = new JsonArray();
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery("SELECT id, nombre, cargo, tarjeta FROM persona ORDER BY nombre")) {
            while (rs.next()) {
                JsonObject o = new JsonObject();
                o.addProperty("id", rs.getString(1));
                o.addProperty("nombre", rs.getString(2));
                o.addProperty("cargo", rs.getString(3));
                o.addProperty("tarjeta", rs.getString(4));
                arr.add(o);
            }
            return arr;
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    // Consultas y respuestas

    private long investigador(String nombre) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement("INSERT OR IGNORE INTO investigador (nombre) VALUES (?)")) {
            ps.setString(1, nombre);
            ps.executeUpdate();
        }
        try (PreparedStatement ps = con.prepareStatement("SELECT id FROM investigador WHERE nombre = ?")) {
            ps.setString(1, nombre);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }

    @Override
    public synchronized long guardarConsulta(String investigador, String tipo, JsonObject parametros, String modo,
                                             long version, JsonObject respuesta, String hechosHash) {
        try {
            con.setAutoCommit(false);
            long idInv = investigador(investigador);
            long id;
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO consulta (investigador_id, tipo, parametros, modo, version_id, creada_en) VALUES (?,?,?,?,?,?) RETURNING id")) {
                ps.setLong(1, idInv);
                ps.setString(2, tipo);
                ps.setString(3, parametros.toString());
                ps.setString(4, modo);
                ps.setLong(5, version);
                ps.setString(6, ahora());
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    id = rs.getLong(1);
                }
            }
            String json = respuesta.toString();
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO respuesta (consulta_id, estado, json, hash, hechos_hash) VALUES (?,?,?,?,?)")) {
                ps.setLong(1, id);
                ps.setString(2, respuesta.has("estado") ? respuesta.get("estado").getAsString() : "sin_respuesta");
                ps.setString(3, json);
                ps.setString(4, Custodia.sha256(json));
                ps.setString(5, hechosHash);
                ps.executeUpdate();
            }
            con.commit();
            return id;
        } catch (SQLException e) {
            try {
                con.rollback();
            } catch (SQLException ignorada) {
                // se informa el error original
            }
            throw fallo(e);
        } finally {
            try {
                con.setAutoCommit(true);
            } catch (SQLException ignorada) {
                // la conexion sigue en uso
            }
        }
    }

    private static final String SELECT_CONSULTA =
            "SELECT c.id, i.nombre, c.tipo, c.parametros, c.modo, c.version_id, c.creada_en, r.json, r.hash, r.hechos_hash "
                    + "FROM consulta c JOIN investigador i ON i.id = c.investigador_id JOIN respuesta r ON r.consulta_id = c.id ";

    private JsonObject leerConsulta(ResultSet rs) throws SQLException {
        JsonObject o = new JsonObject();
        o.addProperty("id", rs.getLong(1));
        o.addProperty("investigador", rs.getString(2));
        o.addProperty("tipo", rs.getString(3));
        o.add("parametros", JsonParser.parseString(rs.getString(4)));
        o.addProperty("modo", rs.getString(5));
        o.addProperty("version", rs.getLong(6));
        o.addProperty("creada_en", rs.getString(7));
        o.add("respuesta", JsonParser.parseString(rs.getString(8)));
        o.addProperty("hash_respuesta", rs.getString(9));
        o.addProperty("hash_hechos", rs.getString(10));
        return o;
    }

    @Override
    public synchronized Optional<JsonObject> consulta(long id) {
        try (PreparedStatement ps = con.prepareStatement(SELECT_CONSULTA + "WHERE c.id = ?")) {
            ps.setLong(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? Optional.of(leerConsulta(rs)) : Optional.empty();
            }
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    @Override
    public synchronized JsonArray consultas() {
        JsonArray arr = new JsonArray();
        try (Statement st = con.createStatement(); ResultSet rs = st.executeQuery(SELECT_CONSULTA + "ORDER BY c.id")) {
            while (rs.next()) {
                arr.add(leerConsulta(rs));
            }
            return arr;
        } catch (SQLException e) {
            throw fallo(e);
        }
    }

    // Cadena de custodia

    @Override
    public synchronized JsonObject verificarCustodia() {
        JsonObject o = new JsonObject();
        String anterior = Custodia.GENESIS;
        Long roto = null;
        List<Registro> registros = registrosHasta(Long.MAX_VALUE);
        for (Registro r : registros) {
            if (!r.hashAnterior().equals(anterior) || !Custodia.hashRegistro(r).equals(r.hash())) {
                roto = r.id();
                break;
            }
            anterior = r.hash();
        }
        String anteriorC = Custodia.GENESIS;
        Long rotaC = null;
        List<Correccion> cs = correccionesHasta(Long.MAX_VALUE);
        for (Correccion c : cs) {
            if (!c.hashAnterior().equals(anteriorC) || !Custodia.hashCorreccion(c).equals(c.hash())) {
                rotaC = c.id();
                break;
            }
            anteriorC = c.hash();
        }
        o.addProperty("registros", registros.size());
        o.addProperty("correcciones", cs.size());
        o.addProperty("valida", roto == null && rotaC == null);
        o.addProperty("registro_alterado", roto);
        o.addProperty("correccion_alterada", rotaC);
        o.addProperty("ultimo_hash", registros.isEmpty() ? Custodia.GENESIS : registros.get(registros.size() - 1).hash());
        return o;
    }
}
