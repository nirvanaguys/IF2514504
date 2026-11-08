-- ============================================================
-- FUNCTION: Hitung Hari Kerja
-- ============================================================
DELIMITER $$
DROP FUNCTION IF EXISTS fn_hitung_hari_kerja$$
CREATE FUNCTION fn_hitung_hari_kerja(
    p_tgl_mulai DATE,
    p_tgl_selesai DATE
)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_tanggal DATE;
    DECLARE v_jumlah_hari INT DEFAULT 0;
    SET v_tanggal = p_tgl_mulai;
    WHILE v_tanggal <= p_tgl_selesai DO
        IF WEEKDAY(v_tanggal) < 5 THEN
            IF NOT EXISTS (
                SELECT 1
                FROM Libur_Nasional
                WHERE Tanggal_Libur = v_tanggal
            ) THEN
                SET v_jumlah_hari = v_jumlah_hari + 1;
            END IF;
        END IF;
        SET v_tanggal =
            DATE_ADD(v_tanggal, INTERVAL 1 DAY);
    END WHILE;
    RETURN v_jumlah_hari;

END$$

DELIMITER ;

-- ============================================================
-- FUNCTION: Sisa Cuti
-- ============================================================
DELIMITER $$
DROP FUNCTION IF EXISTS fn_sisa_cuti$$
CREATE FUNCTION fn_sisa_cuti(
    p_id_pegawai INT
)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_sisa_cuti INT;
    SELECT Sisa_Cuti_Tahunan
    INTO v_sisa_cuti
    FROM Pegawai
    WHERE ID_Pegawai = p_id_pegawai;
    RETURN COALESCE(v_sisa_cuti, 0);

END$$

DELIMITER ;
