-- ============================================================
-- PROCEDURE: Membuat Pengajuan Cuti
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_buat_pengajuan_cuti$$

CREATE PROCEDURE sp_buat_pengajuan_cuti(
    IN p_id_pegawai INT,
    IN p_id_jenis INT,
    IN p_tgl_mulai DATE,
    IN p_tgl_selesai DATE
)
BEGIN
    DECLARE v_durasi INT;
    DECLARE v_potong BOOLEAN;
    DECLARE v_sisa INT;

    -- Jika terjadi error, semua perubahan dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek pegawai aktif
    IF NOT EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE ID_Pegawai = p_id_pegawai
          AND Status_Aktif = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pegawai tidak aktif atau tidak ditemukan.';
    END IF;

    -- Cek jenis cuti
    IF NOT EXISTS (
        SELECT 1
        FROM Jenis_Cuti
        WHERE ID_Jenis = p_id_jenis
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Jenis cuti tidak valid.';
    END IF;

    -- Cek tanggal
    IF p_tgl_mulai > p_tgl_selesai THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Tanggal mulai harus sebelum tanggal selesai.';
    END IF;

    -- Hitung hari kerja
    SET v_durasi =
        fn_hitung_hari_kerja(
            p_tgl_mulai,
            p_tgl_selesai
        );

    -- Minimal harus ada 1 hari kerja
    IF v_durasi = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Tidak ada hari kerja dalam rentang tanggal tersebut.';
    END IF;

    -- Cek apakah jenis cuti memotong kuota tahunan
    SELECT Apakah_Potong_Cuti_Tahunan
    INTO v_potong
    FROM Jenis_Cuti
    WHERE ID_Jenis = p_id_jenis;

    IF v_potong = TRUE THEN

        SELECT Sisa_Cuti_Tahunan
        INTO v_sisa
        FROM Pegawai
        WHERE ID_Pegawai = p_id_pegawai;

        IF v_sisa < v_durasi THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Sisa cuti tidak mencukupi.';
        END IF;

    END IF;

    -- Cek apakah sudah ada pengajuan pending atau disetujui
    -- dengan tanggal yang bentrok
    IF EXISTS (
        SELECT 1
        FROM Pengajuan_Cuti
        WHERE ID_Pegawai = p_id_pegawai
          AND Status_Pengajuan IN ('pending', 'disetujui')
          AND (
                p_tgl_mulai BETWEEN Tgl_Mulai AND Tgl_Selesai
                OR
                p_tgl_selesai BETWEEN Tgl_Mulai AND Tgl_Selesai
                OR
                Tgl_Mulai BETWEEN p_tgl_mulai AND p_tgl_selesai
              )
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Sudah ada pengajuan cuti yang pending atau disetujui di rentang tanggal tersebut.';
    END IF;

    -- Simpan pengajuan
    INSERT INTO Pengajuan_Cuti (
        ID_Pegawai,
        ID_Jenis,
        Tgl_Mulai,
        Tgl_Selesai,
        Durasi_Hari,
        Status_Pengajuan
    )
    VALUES (
        p_id_pegawai,
        p_id_jenis,
        p_tgl_mulai,
        p_tgl_selesai,
        v_durasi,
        'pending'
    );

    COMMIT;

END$$

DELIMITER ;

-- ============================================================
-- PROCEDURE: Tambah Pegawai
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_tambah_pegawai_baru$$

CREATE PROCEDURE sp_tambah_pegawai_baru(
    IN p_nama_pegawai VARCHAR(150),
    IN p_id_atasan INT,
    IN p_role ENUM('pegawai','hrd','manajer'),
    IN p_sisa_cuti INT,
    IN p_username VARCHAR(50),
    IN p_password_hash VARCHAR(255)
)
BEGIN

    -- Jika terjadi error, transaction dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek sisa cuti
    IF p_sisa_cuti < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Sisa cuti tidak boleh negatif.';
    END IF;

    -- Cek username duplikat
    IF EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE Username = p_username
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Username sudah digunakan.';
    END IF;

    -- Cek atasan jika diberikan
    IF p_id_atasan IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM Pegawai
            WHERE ID_Pegawai = p_id_atasan
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'ID Atasan tidak ditemukan.';
        END IF;

    END IF;

    -- Tambahkan pegawai baru
    INSERT INTO Pegawai (
        Nama_Pegawai,
        Username,
        Password_Hash,
        ID_Atasan,
        Role,
        Sisa_Cuti_Tahunan,
        Status_Aktif
    )
    VALUES (
        p_nama_pegawai,
        p_username,
        p_password_hash,
        p_id_atasan,
        p_role,
        p_sisa_cuti,
        TRUE
    );

    -- Catat kuota awal pegawai
    INSERT INTO Riwayat_Kuota_Cuti (
        ID_Pegawai,
        Perubahan_Saldo,
        Keterangan
    )
    VALUES (
        LAST_INSERT_ID(),
        p_sisa_cuti,
        'Kuota awal saat pendaftaran pegawai baru'
    );

    COMMIT;

END$$

DELIMITER ;

-- ============================================================
-- PROCEDURE: Lihat Pengajuan Bawahan
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_lihat_pengajuan_bawahan$$

CREATE PROCEDURE sp_lihat_pengajuan_bawahan(
    IN p_id_atasan INT
)
BEGIN

    -- Jika terjadi error, transaction dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek apakah atasan adalah manajer atau HRD aktif
    IF NOT EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE ID_Pegawai = p_id_atasan
          AND Role IN ('manajer', 'hrd')
          AND Status_Aktif = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Manajer atau HRD tidak ditemukan atau tidak aktif.';
    END IF;

    -- Menampilkan pengajuan bawahan dengan memanfaatkan View v_daftar_pengajuan_cuti
    -- Menggunakan subquery IN/EXISTS untuk menghindari explicit JOIN ganda
    SELECT
        v.ID_Pengajuan,
        v.ID_Pegawai,
        v.Nama_Pegawai,
        v.Nama_Jenis,
        v.Tgl_Mulai,
        v.Tgl_Selesai,
        v.Durasi_Hari,
        v.Status_Pengajuan
    FROM v_daftar_pengajuan_cuti v
    WHERE (
        v.ID_Pegawai IN (
            SELECT p.ID_Pegawai
            FROM Pegawai p
            WHERE p.ID_Atasan = p_id_atasan
        )
        OR EXISTS (
            SELECT 1
            FROM Pegawai h
            WHERE h.ID_Pegawai = p_id_atasan
              AND h.Role = 'hrd'
        )
    )
    ORDER BY v.ID_Pengajuan DESC;

    COMMIT;

END$$

DELIMITER ;
-- ============================================================
-- PROCEDURE: Membatalkan Pengajuan
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_batalkan_pengajuan_cuti$$

CREATE PROCEDURE sp_batalkan_pengajuan_cuti(
    IN p_id_pengajuan INT,
    IN p_id_pegawai INT
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_pengaju INT;
    DECLARE v_durasi INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT
        Status_Pengajuan,
        ID_Pegawai,
        Durasi_Hari
    INTO
        v_status,
        v_pengaju,
        v_durasi
    FROM Pengajuan_Cuti
    WHERE ID_Pengajuan = p_id_pengajuan;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Pengajuan tidak ditemukan.';
    END IF;

    IF v_pengaju <> p_id_pegawai THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Anda tidak berhak membatalkan pengajuan ini.';
    END IF;

    IF v_status = 'pending' THEN

        UPDATE Pengajuan_Cuti
        SET Status_Pengajuan = 'dibatalkan'
        WHERE ID_Pengajuan = p_id_pengajuan;

    ELSEIF v_status = 'disetujui' THEN

        UPDATE Pegawai
        SET Sisa_Cuti_Tahunan = Sisa_Cuti_Tahunan + v_durasi
        WHERE ID_Pegawai = p_id_pegawai;

        INSERT INTO Riwayat_Kuota_Cuti
        (
            ID_Pegawai,
            Perubahan_Saldo,
            Keterangan
        )
        VALUES
        (
            p_id_pegawai,
            v_durasi,
            CONCAT(
                'Kuota dikembalikan +',
                v_durasi,
                ' - pengajuan #',
                p_id_pengajuan,
                ' dibatalkan'
            )
        );

        UPDATE Pengajuan_Cuti
        SET Status_Pengajuan = 'dibatalkan'
        WHERE ID_Pengajuan = p_id_pengajuan;

    ELSE

        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pengajuan tidak dapat dibatalkan.';

    END IF;

    COMMIT;

END$$

DELIMITER ;

-- ============================================================
-- PROCEDURE: Menyetujui Pengajuan
-- Manager ATAU HRD
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_setujui_pengajuan_cuti$$

CREATE PROCEDURE sp_setujui_pengajuan_cuti(
    IN p_id_pengajuan INT,
    IN p_id_approver INT,
    IN p_catatan VARCHAR(500)
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_pengaju INT;
    DECLARE v_durasi INT;
    DECLARE v_id_jenis INT;
    DECLARE v_potong BOOLEAN;
    DECLARE v_role VARCHAR(20);
    DECLARE v_sisa INT;

    -- Jika terjadi error, semua perubahan dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek pengajuan
    SELECT
        Status_Pengajuan,
        ID_Pegawai,
        ID_Jenis,
        Durasi_Hari
    INTO
        v_status,
        v_pengaju,
        v_id_jenis,
        v_durasi
    FROM Pengajuan_Cuti
    WHERE ID_Pengajuan = p_id_pengajuan;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pengajuan tidak ditemukan.';
    END IF;

    -- Pengajuan harus masih pending
    IF v_status <> 'pending' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pengajuan tidak berstatus pending.';
    END IF;

    -- Cek approver aktif
    SELECT Role
    INTO v_role
    FROM Pegawai
    WHERE ID_Pegawai = p_id_approver
      AND Status_Aktif = TRUE;

    IF v_role IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Approver tidak ditemukan atau tidak aktif.';
    END IF;

    -- Hanya manager atau HRD yang boleh menyetujui
    IF v_role NOT IN ('manajer', 'hrd') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Hanya manajer atau HRD yang dapat menyetujui.';
    END IF;

    -- Manager harus merupakan atasan langsung
    IF v_role = 'manajer' THEN

        IF NOT EXISTS (
            SELECT 1
            FROM Pegawai
            WHERE ID_Pegawai = v_pengaju
              AND ID_Atasan = p_id_approver
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Manager bukan atasan langsung pegawai.';
        END IF;

    END IF;

    -- Cek apakah jenis cuti memotong kuota tanpa JOIN langsung
    SELECT Apakah_Potong_Cuti_Tahunan
    INTO v_potong
    FROM Jenis_Cuti
    WHERE ID_Jenis = v_id_jenis;

    IF v_potong = TRUE THEN

        -- Ambil sisa kuota
        SELECT Sisa_Cuti_Tahunan
        INTO v_sisa
        FROM Pegawai
        WHERE ID_Pegawai = v_pengaju;

        -- Cek kuota cukup
        IF v_sisa < v_durasi THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Sisa cuti tidak mencukupi.';
        END IF;

        -- Kurangi kuota
        UPDATE Pegawai
        SET Sisa_Cuti_Tahunan =
            Sisa_Cuti_Tahunan - v_durasi
        WHERE ID_Pegawai = v_pengaju;

        -- Simpan riwayat perubahan kuota
        INSERT INTO Riwayat_Kuota_Cuti (
            ID_Pegawai,
            Perubahan_Saldo,
            Keterangan
        )
        VALUES (
            v_pengaju,
            -v_durasi,
            CONCAT(
                'Kuota dipotong - pengajuan #',
                p_id_pengajuan,
                ' disetujui'
            )
        );

    END IF;

    -- Simpan data approval
    INSERT INTO Approval_Cuti (
        ID_Pengajuan,
        ID_Approver,
        Level_Approval,
        Status_Approval,
        Catatan
    )
    VALUES (
        p_id_pengajuan,
        p_id_approver,
        1,
        'disetujui',
        p_catatan
    );

    -- Ubah status pengajuan
    UPDATE Pengajuan_Cuti
    SET Status_Pengajuan = 'disetujui'
    WHERE ID_Pengajuan = p_id_pengajuan;

    COMMIT;

END$$

DELIMITER ;
-- ============================================================
-- PROCEDURE: Menolak Pengajuan
-- Manager ATAU HRD
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_tolak_pengajuan_cuti$$

CREATE PROCEDURE sp_tolak_pengajuan_cuti(
    IN p_id_pengajuan INT,
    IN p_id_approver INT,
    IN p_catatan VARCHAR(500)
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_pengaju INT;
    DECLARE v_role VARCHAR(20);

    -- Jika terjadi error, transaction dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek pengajuan
    SELECT
        Status_Pengajuan,
        ID_Pegawai
    INTO
        v_status,
        v_pengaju
    FROM Pengajuan_Cuti
    WHERE ID_Pengajuan = p_id_pengajuan;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pengajuan tidak ditemukan.';
    END IF;

    -- Pengajuan harus masih pending
    IF v_status <> 'pending' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pengajuan tidak berstatus pending.';
    END IF;

    -- Cek approver aktif
    SELECT Role
    INTO v_role
    FROM Pegawai
    WHERE ID_Pegawai = p_id_approver
      AND Status_Aktif = TRUE;

    IF v_role IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Approver tidak ditemukan atau tidak aktif.';
    END IF;

    -- Hanya manager atau HRD
    IF v_role NOT IN ('manajer', 'hrd') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Hanya manajer atau HRD yang dapat menolak.';
    END IF;

    -- Manager harus merupakan atasan langsung
    IF v_role = 'manajer' THEN

        IF NOT EXISTS (
            SELECT 1
            FROM Pegawai
            WHERE ID_Pegawai = v_pengaju
              AND ID_Atasan = p_id_approver
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Manager bukan atasan langsung pegawai.';
        END IF;

    END IF;

    -- Simpan data approval
    INSERT INTO Approval_Cuti (
        ID_Pengajuan,
        ID_Approver,
        Level_Approval,
        Status_Approval,
        Catatan
    )
    VALUES (
        p_id_pengajuan,
        p_id_approver,
        1,
        'ditolak',
        p_catatan
    );

    -- Ubah status pengajuan
    UPDATE Pengajuan_Cuti
    SET Status_Pengajuan = 'ditolak'
    WHERE ID_Pengajuan = p_id_pengajuan;

    COMMIT;

END$$

DELIMITER ;
-- ============================================================
-- PROCEDURE: Nonaktifkan Pegawai
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_nonaktifkan_pegawai$$

CREATE PROCEDURE sp_nonaktifkan_pegawai(
    IN p_id_pegawai INT
)
BEGIN

    -- Jika terjadi error, transaction dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek apakah pegawai ditemukan
    IF NOT EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE ID_Pegawai = p_id_pegawai
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pegawai tidak ditemukan.';
    END IF;

    -- Menonaktifkan pegawai
    UPDATE Pegawai
    SET Status_Aktif = FALSE
    WHERE ID_Pegawai = p_id_pegawai;

    COMMIT;

END$$

DELIMITER ;
-- ===========================================================
-- PROCEDURE: Tambah Jenis Cuti
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_tambah_jenis_cuti$$

CREATE PROCEDURE sp_tambah_jenis_cuti(
    IN p_nama VARCHAR(100),
    IN p_potong BOOLEAN
)
BEGIN

    -- Jika terjadi error, transaction dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek apakah jenis cuti sudah ada
    IF EXISTS (
        SELECT 1
        FROM Jenis_Cuti
        WHERE Nama_Jenis = p_nama
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Jenis cuti sudah ada.';
    END IF;

    -- Tambahkan jenis cuti
    INSERT INTO Jenis_Cuti (
        Nama_Jenis,
        Apakah_Potong_Cuti_Tahunan
    )
    VALUES (
        p_nama,
        p_potong
    );

    COMMIT;

END$$

DELIMITER ;
-- ============================================================
-- PROCEDURE: Tambah Sisa Cuti Tahunan
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_tambah_sisa_cuti_tahunan$$

CREATE PROCEDURE sp_tambah_sisa_cuti_tahunan(
    IN p_id_pegawai INT,
    IN p_jumlah INT,
    IN p_ket VARCHAR(255)
)
BEGIN

    -- Jika terjadi error, transaction dibatalkan
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Cek apakah pegawai ditemukan
    IF NOT EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE ID_Pegawai = p_id_pegawai
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Pegawai tidak ditemukan.';
    END IF;

    -- Tambahkan sisa cuti
    UPDATE Pegawai
    SET Sisa_Cuti_Tahunan =
        Sisa_Cuti_Tahunan + p_jumlah
    WHERE ID_Pegawai = p_id_pegawai;

    -- Catat perubahan kuota
    INSERT INTO Riwayat_Kuota_Cuti (
        ID_Pegawai,
        Perubahan_Saldo,
        Keterangan
    )
    VALUES (
        p_id_pegawai,
        p_jumlah,
        p_ket
    );

    COMMIT;

END$$

DELIMITER ;
-- ============================================================
-- PROCEDURE: Tambah Libur Nasional
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_tambah_libur_nasional$$

CREATE PROCEDURE sp_tambah_libur_nasional(
    IN p_tgl DATE,
    IN p_ket VARCHAR(255)
)
BEGIN

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM Libur_Nasional
        WHERE Tanggal_Libur = p_tgl
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Tanggal libur sudah ada.';
    END IF;

    INSERT INTO Libur_Nasional (
        Tanggal_Libur,
        Keterangan
    )
    VALUES (
        p_tgl,
        p_ket
    );

    COMMIT;

END$$

DELIMITER ;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_lihat_daftar_pegawai$$
CREATE PROCEDURE sp_lihat_daftar_pegawai()
BEGIN
    SELECT
        ID_Pegawai,
        Nama_Pegawai,
        Username,
        ID_Atasan,
        Role,
        Sisa_Cuti_Tahunan,
        Status_Aktif
    FROM Pegawai
    ORDER BY ID_Pegawai;
END$$

DELIMITER ;


DELIMITER $$

DROP PROCEDURE IF EXISTS sp_lihat_riwayat_kuota_cuti$$
CREATE PROCEDURE sp_lihat_riwayat_kuota_cuti(
    IN p_id_pegawai INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    IF NOT EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE ID_Pegawai = p_id_pegawai
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Pegawai tidak ditemukan.';
    END IF;

    SELECT
        ID_Riwayat,
        ID_Pegawai,
        Tgl_Perubahan,
        Perubahan_Saldo,
        Keterangan
    FROM Riwayat_Kuota_Cuti
    WHERE ID_Pegawai = p_id_pegawai
    ORDER BY Tgl_Perubahan DESC, ID_Riwayat DESC;

    COMMIT;
END$$

DELIMITER ;

-- ============================================================
-- PROCEDURE: Lihat Riwayat Pengajuan Pegawai Sendiri
-- ============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_lihat_pengajuan_pegawai$$
CREATE PROCEDURE sp_lihat_pengajuan_pegawai(
    IN p_id_pegawai INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE ID_Pegawai = p_id_pegawai
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Pegawai tidak ditemukan.';
    END IF;

    -- Mengambil pengajuan cuti pegawai berdasarkan view v_daftar_pengajuan_cuti
    SELECT
        ID_Pengajuan,
        ID_Pegawai,
        Nama_Pegawai,
        Nama_Jenis,
        Tgl_Mulai,
        Tgl_Selesai,
        Durasi_Hari,
        Status_Pengajuan
    FROM v_daftar_pengajuan_cuti
    WHERE ID_Pegawai = p_id_pegawai
    ORDER BY ID_Pengajuan DESC;

    COMMIT;
END$$

DELIMITER ;