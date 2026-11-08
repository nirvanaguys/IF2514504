
-- ============================================================
-- TRIGGER: Validasi dan Hitung Durasi Pengajuan
-- ============================================================
DELIMITER $$

DROP TRIGGER IF EXISTS trg_pengajuan_before_insert$$
CREATE TRIGGER trg_pengajuan_before_insert
BEFORE INSERT ON Pengajuan_Cuti
FOR EACH ROW
BEGIN
    IF NEW.Tgl_Mulai > NEW.Tgl_Selesai THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Tanggal mulai tidak boleh setelah tanggal selesai.';
    END IF;
    SET NEW.Durasi_Hari =
        fn_hitung_hari_kerja(
            NEW.Tgl_Mulai,
            NEW.Tgl_Selesai
        );
    IF NEW.Durasi_Hari = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Rentang tanggal tidak memiliki hari kerja.';
    END IF;

END$$

DELIMITER ;

-- ============================================================
-- TRIGGER: Cegah Sisa Cuti Negatif
-- ============================================================
DELIMITER $$

DROP TRIGGER IF EXISTS trg_pegawai_before_update$$
CREATE TRIGGER trg_pegawai_before_update
BEFORE UPDATE ON Pegawai
FOR EACH ROW
BEGIN

    IF NEW.Sisa_Cuti_Tahunan < 0 THEN

        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Sisa cuti tidak boleh negatif.';

    END IF;
END$$

DELIMITER ;

-- ============================================================
-- TRIGGER: Batalkan Pengajuan Saat Pegawai Dinonaktifkan
-- ============================================================
DELIMITER $$

DROP TRIGGER IF EXISTS trg_pegawai_after_update$$
CREATE TRIGGER trg_pegawai_after_update
AFTER UPDATE ON Pegawai
FOR EACH ROW
BEGIN
    IF OLD.Status_Aktif = TRUE
       AND NEW.Status_Aktif = FALSE THEN
        UPDATE Pengajuan_Cuti
        SET Status_Pengajuan = 'dibatalkan'
        WHERE ID_Pegawai = NEW.ID_Pegawai
          AND Status_Pengajuan = 'pending';
    END IF;
END$$

DELIMITER ;
