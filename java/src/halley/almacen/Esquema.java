package halley.almacen;

final class Esquema {

    private Esquema() {
    }

    static final String[] SENTENCIAS = {
            """
        CREATE TABLE IF NOT EXISTS fuente (
          id TEXT PRIMARY KEY,
          archivo TEXT NOT NULL,
          tipo TEXT NOT NULL CHECK (tipo IN ('evidencia', 'referencia')))
        """,
            """
        INSERT OR IGNORE INTO fuente (id, archivo, tipo) VALUES
          ('personal', 'personal.csv', 'referencia'), ('estacion', 'estacion.csv', 'referencia'),
          ('tarjetas', 'tarjetas.csv', 'evidencia'), ('radio', 'radio.txt', 'evidencia'),
          ('energia', 'energia.json', 'evidencia'), ('presencia', 'presencia.csv', 'evidencia'),
          ('temperatura', 'temperatura.csv', 'evidencia'), ('bitacora', 'bitacora.txt', 'evidencia')
        """,
            """
        CREATE TABLE IF NOT EXISTS modulo (
          codigo TEXT PRIMARY KEY,
          nombre TEXT NOT NULL)
        """,
            """
        INSERT OR IGNORE INTO modulo (codigo, nombre) VALUES
          ('COM', 'Comedor'), ('DOR', 'Dormitorios'), ('LAB-A', 'Laboratorio A'), ('LAB-B', 'Laboratorio B'),
          ('GEN', 'Generadores'), ('RAD', 'Sala de radio'), ('ALM', 'Almacen'), ('EXT', 'Exterior')
        """,
            """
        CREATE TABLE IF NOT EXISTS persona (
          id TEXT PRIMARY KEY,
          nombre TEXT NOT NULL,
          cargo TEXT NOT NULL,
          tarjeta TEXT NOT NULL UNIQUE)
        """,
            """
        CREATE TABLE IF NOT EXISTS registro (
          id INTEGER PRIMARY KEY,
          fuente_id TEXT NOT NULL REFERENCES fuente(id),
          num INTEGER NOT NULL,
          texto TEXT NOT NULL,
          origen TEXT NOT NULL CHECK (origen IN ('archivo', 'vivo')),
          emisor TEXT,
          seq INTEGER,
          recibido_en TEXT NOT NULL,
          hash_anterior TEXT NOT NULL,
          hash TEXT NOT NULL UNIQUE,
          UNIQUE (emisor, seq))
        """,
            """
        CREATE TABLE IF NOT EXISTS correccion (
          id INTEGER PRIMARY KEY,
          agencia TEXT NOT NULL,
          tipo TEXT NOT NULL CHECK (tipo IN ('desfase_reloj', 'descartar')),
          fuente_id TEXT REFERENCES fuente(id),
          dispositivo TEXT,
          segundos INTEGER,
          registro_id INTEGER REFERENCES registro(id),
          motivo TEXT NOT NULL,
          creada_en TEXT NOT NULL,
          hash_anterior TEXT NOT NULL,
          hash TEXT NOT NULL UNIQUE)
        """,
            """
        CREATE TABLE IF NOT EXISTS version (
          id INTEGER PRIMARY KEY,
          ultimo_registro INTEGER NOT NULL REFERENCES registro(id),
          ultima_correccion INTEGER NOT NULL,
          hechos_original TEXT NOT NULL,
          hechos_corregida TEXT NOT NULL,
          deducciones_original TEXT NOT NULL,
          deducciones_corregida TEXT NOT NULL,
          creada_en TEXT NOT NULL)
        """,
            """
        CREATE TABLE IF NOT EXISTS evento (
          version_id INTEGER NOT NULL REFERENCES version(id),
          modo TEXT NOT NULL CHECK (modo IN ('original', 'corregida')),
          id TEXT NOT NULL,
          registro_id INTEGER NOT NULL REFERENCES registro(id),
          ts INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          persona_id TEXT REFERENCES persona(id),
          modulo TEXT REFERENCES modulo(codigo),
          descripcion TEXT NOT NULL,
          json TEXT NOT NULL,
          PRIMARY KEY (version_id, modo, id))
        """,
            """
        CREATE TABLE IF NOT EXISTS problema (
          id INTEGER PRIMARY KEY,
          version_id INTEGER NOT NULL REFERENCES version(id),
          modo TEXT NOT NULL,
          registro_id INTEGER NOT NULL REFERENCES registro(id),
          tipo TEXT NOT NULL,
          motivo TEXT NOT NULL,
          usado INTEGER NOT NULL)
        """,
            """
        CREATE TABLE IF NOT EXISTS investigador (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL UNIQUE)
        """,
            """
        CREATE TABLE IF NOT EXISTS consulta (
          id INTEGER PRIMARY KEY,
          investigador_id INTEGER NOT NULL REFERENCES investigador(id),
          tipo TEXT NOT NULL,
          parametros TEXT NOT NULL,
          modo TEXT NOT NULL CHECK (modo IN ('original', 'corregida')),
          version_id INTEGER NOT NULL REFERENCES version(id),
          creada_en TEXT NOT NULL)
        """,
            """
        CREATE TABLE IF NOT EXISTS respuesta (
          consulta_id INTEGER PRIMARY KEY REFERENCES consulta(id),
          estado TEXT NOT NULL,
          json TEXT NOT NULL,
          hash TEXT NOT NULL,
          hechos_hash TEXT NOT NULL)
        """,
            "CREATE INDEX IF NOT EXISTS evento_registro ON evento (version_id, modo, registro_id)",
            "CREATE INDEX IF NOT EXISTS problema_version ON problema (version_id, modo)",
            inmutable("registro"), borrado("registro"),
            inmutable("correccion"), borrado("correccion"),
            inmutable("version"), borrado("version"),
            inmutable("consulta"), borrado("consulta"),
            inmutable("respuesta"), borrado("respuesta"),
    };

    private static String inmutable(String tabla) {
        return "CREATE TRIGGER IF NOT EXISTS " + tabla + "_sin_cambios BEFORE UPDATE ON " + tabla
                + " BEGIN SELECT RAISE(ABORT, '" + tabla + " es de solo lectura'); END";
    }

    private static String borrado(String tabla) {
        return "CREATE TRIGGER IF NOT EXISTS " + tabla + "_sin_borrado BEFORE DELETE ON " + tabla
                + " BEGIN SELECT RAISE(ABORT, '" + tabla + " no se puede borrar'); END";
    }
}
