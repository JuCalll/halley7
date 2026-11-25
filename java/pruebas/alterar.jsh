import java.sql.*;
    var con = DriverManager.getConnection("jdbc:sqlite:trabajo/prueba/halley.db");
    var st = con.createStatement();
    try { st.execute("UPDATE registro SET texto = 'cambiado' WHERE id = 1"); } catch (SQLException e) { System.out.println("UPDATE: " + e.getMessage()); }
    try { st.execute("DELETE FROM correccion"); } catch (SQLException e) { System.out.println("DELETE: " + e.getMessage()); }
    st.execute("DROP TRIGGER registro_sin_cambios");
    st.execute("UPDATE registro SET texto = '2041-06-14T01:39:47,JS-01,P7,GEN,ALM,OK' WHERE id = 1");
    con.close();
    var a = new halley.almacen.AlmacenSqlite(java.nio.file.Path.of("trabajo/prueba/halley.db"));
    System.out.println(a.verificarCustodia());
    /exit