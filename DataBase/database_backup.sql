
CREATE DATABASE IF NOT EXISTS sistem_cuti;
USE sistem_cuti;

-- ============================================================
-- TABEL Jenis_Cuti
-- ============================================================
CREATE TABLE Jenis_Cuti (
    ID_Jenis          INT AUTO_INCREMENT PRIMARY KEY,
    Nama_Jenis        VARCHAR(100) NOT NULL,
    Apakah_Potong_Cuti_Tahunan BOOLEAN NOT NULL DEFAULT TRUE
);

-- ============================================================
-- TABEL Pegawai
-- ============================================================
CREATE TABLE Pegawai (
    ID_Pegawai        INT AUTO_INCREMENT PRIMARY KEY,
    Nama_Pegawai      VARCHAR(150) NOT NULL,
    ID_Atasan         INT NULL,
    Role              ENUM('pegawai', 'hrd', 'manajer') NOT NULL DEFAULT 'pegawai',
    Sisa_Cuti_Tahunan INT NOT NULL DEFAULT 0,
    Status_Aktif      BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (ID_Atasan) REFERENCES Pegawai(ID_Pegawai)
        ON DELETE SET NULL ON UPDATE CASCADE
);

-- ============================================================
-- TABEL Pengajuan_Cuti
-- ============================================================
CREATE TABLE Pengajuan_Cuti (
    ID_Pengajuan      INT AUTO_INCREMENT PRIMARY KEY,
    ID_Pegawai        INT NOT NULL,
    ID_Jenis          INT NOT NULL,
    Tgl_Mulai         DATE NOT NULL,
    Tgl_Selesai       DATE NOT NULL,
    Durasi_Hari       INT NOT NULL,
    Status_Pengajuan  ENUM('pending', 'disetujui', 'ditolak', 'dibatalkan')
                      NOT NULL DEFAULT 'pending',
    FOREIGN KEY (ID_Pegawai) REFERENCES Pegawai(ID_Pegawai)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (ID_Jenis) REFERENCES Jenis_Cuti(ID_Jenis)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABEL Approval_Cuti
-- ============================================================
CREATE TABLE Approval_Cuti (
    ID_Approval       INT AUTO_INCREMENT PRIMARY KEY,
    ID_Pengajuan      INT NOT NULL,
    ID_Approver       INT NOT NULL,
    Level_Approval    TINYINT NOT NULL DEFAULT 1,
    Status_Approval   ENUM('disetujui', 'ditolak') NOT NULL,
    Tgl_Approval      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Catatan           VARCHAR(500) NULL,
    FOREIGN KEY (ID_Pengajuan) REFERENCES Pengajuan_Cuti(ID_Pengajuan)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (ID_Approver) REFERENCES Pegawai(ID_Pegawai)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABEL Riwayat_Kuota_Cuti
-- ============================================================
CREATE TABLE Riwayat_Kuota_Cuti (
    ID_Riwayat        INT AUTO_INCREMENT PRIMARY KEY,
    ID_Pegawai        INT NOT NULL,
    Tgl_Perubahan     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Perubahan_Saldo   INT NOT NULL,
    Keterangan        VARCHAR(255) NULL,
    FOREIGN KEY (ID_Pegawai) REFERENCES Pegawai(ID_Pegawai)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- TABEL Libur_Nasional
-- ============================================================
CREATE TABLE Libur_Nasional (
    Tanggal_Libur     DATE PRIMARY KEY,
    Keterangan        VARCHAR(255) NULL
);

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

    -- Cek apakah sudah ada pengajuan pending
    -- dengan tanggal yang bentrok
    IF EXISTS (
        SELECT 1
        FROM Pengajuan_Cuti
        WHERE ID_Pegawai = p_id_pegawai
          AND Status_Pengajuan = 'pending'
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
            'Sudah ada pengajuan cuti pending di rentang tanggal tersebut.';
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
DELIMITER //

CREATE PROCEDURE sp_tambah_pegawai_baru(
    IN p_nama_pegawai VARCHAR(150),
    IN p_id_atasan INT,
    IN p_role ENUM('pegawai','hrd','manajer'),
    IN p_sisa_cuti INT,
    IN p_username VARCHAR(50),
    IN p_password_hash VARCHAR(255)
)
BEGIN
    DECLARE v_id_pegawai INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF p_nama_pegawai IS NULL OR TRIM(p_nama_pegawai) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nama pegawai wajib diisi.';
    END IF;

    IF p_username IS NULL OR TRIM(p_username) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Username wajib diisi.';
    END IF;

    IF p_password_hash IS NULL OR TRIM(p_password_hash) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Password hash wajib diisi.';
    END IF;

    IF p_role IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Role pegawai wajib diisi.';
    END IF;

    IF p_sisa_cuti IS NULL OR p_sisa_cuti < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sisa cuti tidak boleh kosong atau negatif.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Pegawai
        WHERE Username = p_username
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Username sudah digunakan.';
    END IF;

    IF p_id_atasan IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM Pegawai
            WHERE ID_Pegawai = p_id_atasan
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ID Atasan tidak ditemukan.';
        END IF;
    END IF;

    INSERT INTO Pegawai (
        Nama_Pegawai,
        ID_Atasan,
        Role,
        Sisa_Cuti_Tahunan,
        Status_Aktif,
        Username,
        Password_Hash
    )
    VALUES (
        p_nama_pegawai,
        p_id_atasan,
        p_role,
        p_sisa_cuti,
        TRUE,
        TRIM(p_username),
        p_password_hash
    );

    SET v_id_pegawai = LAST_INSERT_ID();

    INSERT INTO Riwayat_Kuota_Cuti (
        ID_Pegawai,
        Perubahan_Saldo,
        Keterangan
    )
    VALUES (
        v_id_pegawai,
        p_sisa_cuti,
        'Kuota awal saat pendaftaran pegawai baru'
    );

    COMMIT;
END //

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

    -- Menampilkan pengajuan bawahan
    SELECT
        pc.ID_Pengajuan,
        p.ID_Pegawai,
        p.Nama_Pegawai,
        jc.Nama_Jenis,
        pc.Tgl_Mulai,
        pc.Tgl_Selesai,
        pc.Durasi_Hari,
        pc.Status_Pengajuan
    FROM Pengajuan_Cuti pc
    JOIN Pegawai p
        ON pc.ID_Pegawai = p.ID_Pegawai
    JOIN Jenis_Cuti jc
        ON pc.ID_Jenis = jc.ID_Jenis
    WHERE (
        p.ID_Atasan = p_id_atasan
        OR EXISTS (
            SELECT 1
            FROM Pegawai h
            WHERE h.ID_Pegawai = p_id_atasan
              AND h.Role = 'hrd'
        )
    )
    ORDER BY pc.ID_Pengajuan DESC;

    COMMIT;

END$$

DELIMITER ;

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
        Durasi_Hari
    INTO
        v_status,
        v_pengaju,
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

    -- Cek apakah jenis cuti memotong kuota
    SELECT
        jc.Apakah_Potong_Cuti_Tahunan
    INTO v_potong
    FROM Pengajuan_Cuti pc
    JOIN Jenis_Cuti jc
        ON pc.ID_Jenis = jc.ID_Jenis
    WHERE pc.ID_Pengajuan = p_id_pengajuan;

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

-- ============================================================
-- VIEW: Sisa Cuti Pegawai
-- ============================================================
CREATE OR REPLACE VIEW v_sisa_cuti_pegawai AS
SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti_Tahunan AS Sisa_Cuti
FROM Pegawai
WHERE Status_Aktif = TRUE;

-- ============================================================
-- VIEW: Daftar Pengajuan Cuti
-- ============================================================
CREATE OR REPLACE VIEW v_daftar_pengajuan_cuti AS
SELECT
    pc.ID_Pengajuan,
    pc.ID_Pegawai,
    p.Nama_Pegawai,
    jc.Nama_Jenis,
    pc.Tgl_Mulai,
    pc.Tgl_Selesai,
    pc.Durasi_Hari,
    pc.Status_Pengajuan
FROM Pengajuan_Cuti pc
JOIN Pegawai p
    ON pc.ID_Pegawai = p.ID_Pegawai
JOIN Jenis_Cuti jc
    ON pc.ID_Jenis = jc.ID_Jenis;

-- ============================================================
-- VIEW: Riwayat Kuota Cuti
-- ============================================================
CREATE OR REPLACE VIEW v_riwayat_kuota_cuti AS
SELECT
    rk.ID_Riwayat,
    rk.ID_Pegawai,
    p.Nama_Pegawai,
    rk.Tgl_Perubahan,
    rk.Perubahan_Saldo,
    rk.Keterangan
FROM Riwayat_Kuota_Cuti rk
JOIN Pegawai p
    ON rk.ID_Pegawai = p.ID_Pegawai;


DELIMITER $$

DROP PROCEDURE IF EXISTS sp_lihat_daftar_pegawai$$
CREATE PROCEDURE sp_lihat_daftar_pegawai()
BEGIN
    SELECT
        ID_Pegawai,
        Nama_Pegawai,
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

    SELECT
        ID_Pengajuan,
        ID_Jenis,
        Tgl_Mulai,
        Tgl_Selesai,
        Durasi_Hari,
        Status_Pengajuan
    FROM Pengajuan_Cuti
    WHERE ID_Pegawai = p_id_pegawai
    ORDER BY ID_Pengajuan DESC;

    COMMIT;
END$$

DELIMITER ;

ALTER TABLE Pegawai
ADD COLUMN Username VARCHAR(50) NULL UNIQUE,
ADD COLUMN Password_Hash VARCHAR(255) NULL;





UPDATE Pegawai
SET Username = CASE ID_Pegawai
    WHEN 1 THEN 'abie'
    WHEN 2 THEN 'ariel'
    WHEN 3 THEN 'budi'
    WHEN 4 THEN 'rina'
    WHEN 5 THEN 'andi'
    WHEN 6 THEN 'siti'
    WHEN 7 THEN 'dina'
END,
Password_Hash = '$2b$10$YCtxZA0Dv1mit7UngS9oR.eEHd.xwxnbWUnQybREUH8xdSZcMVqKW'
WHERE ID_Pegawai BETWEEN 1 AND 7;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Username,
    Role,
    Status_Aktif,
    Password_Hash IS NOT NULL AS Password_Tersedia
FROM Pegawai
ORDER BY ID_Pegawai;

DROP PROCEDURE IF EXISTS sp_tambah_pegawai_baru;





















CALL sp_lihat_pengajuan_pegawai(5);




USE sistem_cuti;
SHOW TABLES;

SHOW FUNCTION STATUS
WHERE Db = 'sistem_cuti';

SHOW PROCEDURE STATUS
WHERE Db = 'sistem_cuti';

SHOW TRIGGERS FROM sistem_cuti;

SHOW FULL TABLES
WHERE Table_type = 'VIEW';

USE sistem_cuti;

INSERT INTO Jenis_Cuti
    (Nama_Jenis, Apakah_Potong_Cuti_Tahunan)
VALUES
    ('Cuti Tahunan', TRUE),
    ('Cuti Khusus', FALSE);

SELECT
    ID_Jenis,
    Nama_Jenis,
    Apakah_Potong_Cuti_Tahunan
FROM Jenis_Cuti;

CALL sp_tambah_pegawai_baru(
    'Budi',
    NULL,
    'manajer',
    12
);

CALL sp_tambah_pegawai_baru(
    'Rina',
    NULL,
    'hrd',
    12
);

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    ID_Atasan,
    Role,
    Sisa_Cuti_Tahunan,
    Status_Aktif
FROM Pegawai;

CALL sp_tambah_pegawai_baru(
    'Andi',
    1,
    'pegawai',
    12
);

CALL sp_tambah_pegawai_baru(
    'Siti',
    1,
    'pegawai',
    12
);

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    ID_Atasan,
    Role,
    Sisa_Cuti_Tahunan,
    Status_Aktif
FROM Pegawai;

SELECT fn_sisa_cuti(3) AS Sisa_Cuti;

SELECT fn_hitung_hari_kerja(
    '2026-10-05',
    '2026-10-09'
) AS Jumlah_Hari_Kerja;

SELECT fn_hitung_hari_kerja(
    '2026-10-03',
    '2026-10-04'
) AS Jumlah_Hari_Kerja;

SELECT
    fn_sisa_cuti(2) AS Sisa_Cuti_Ariel,
    fn_sisa_cuti(5) AS Sisa_Cuti_Andi,
    fn_sisa_cuti(6) AS Sisa_Cuti_Siti;

SELECT
    ID_Jenis,
    Nama_Jenis,
    Apakah_Potong_Cuti_Tahunan
FROM Jenis_Cuti;

CALL sp_buat_pengajuan_cuti(
    5,
    1,
    '2026-10-05',
    '2026-10-07'
);

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    ID_Jenis,
    Tgl_Mulai,
    Tgl_Selesai,
    Durasi_Hari,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pegawai = 5
ORDER BY ID_Pengajuan DESC
LIMIT 1;

CALL sp_buat_pengajuan_cuti(
    5,
    1,
    '2026-10-10',
    '2026-10-07'
);

CALL sp_buat_pengajuan_cuti(
    5,
    1,
    '2026-10-05',
    '2026-10-23'
);

CALL sp_buat_pengajuan_cuti(
    5,
    1,
    '2026-10-06',
    '2026-10-08'
);

CALL sp_batalkan_pengajuan_cuti(1, 5);
SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Tgl_Mulai,
    Tgl_Selesai,
    Durasi_Hari,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 1;

CALL sp_buat_pengajuan_cuti(
    5,
    1,
    '2026-10-12',
    '2026-10-14'
);

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Tgl_Mulai,
    Tgl_Selesai,
    Durasi_Hari,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pegawai = 5
ORDER BY ID_Pengajuan DESC
LIMIT 1;

CALL sp_setujui_pengajuan_cuti(2, 3);

SHOW CREATE PROCEDURE sp_setujui_pengajuan_cuti;
CALL sp_setujui_pengajuan_cuti(
    2,
    3,
    'Test approval manager'
);

CALL sp_setujui_pengajuan_cuti(
    2,
    1,
    'Disetujui oleh HRD'
);

SHOW FUNCTION STATUS
WHERE Db = 'sistem_cuti';

SHOW CREATE PROCEDURE sp_setujui_pengajuan_cuti;

CALL sp_setujui_pengajuan_cuti(
    2,
    1,
    'Disetujui oleh HRD'
);

SHOW TRIGGERS FROM sistem_cuti;
DROP TRIGGER IF EXISTS trg_approval_before_insert;
SHOW TRIGGERS FROM sistem_cuti;

CALL sp_setujui_pengajuan_cuti(
    2,
    1,
    'Disetujui oleh HRD'
);

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Durasi_Hari,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 2;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti_Tahunan
FROM Pegawai
WHERE ID_Pegawai = 5;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti_Tahunan
FROM Pegawai
WHERE ID_Pegawai = 5;

SELECT
    ID_Riwayat,
    ID_Pegawai,
    Perubahan_Saldo,
    Keterangan
FROM Riwayat_Kuota_Cuti
WHERE ID_Pegawai = 5
ORDER BY ID_Riwayat;

SHOW CREATE PROCEDURE sp_setujui_pengajuan_cuti;

UPDATE Pegawai
SET Sisa_Cuti_Tahunan = 9
WHERE ID_Pegawai = 5;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti_Tahunan
FROM Pegawai
WHERE ID_Pegawai = 5;

SELECT
    ID_Approval,
    ID_Pengajuan,
    ID_Approver,
    Level_Approval,
    Status_Approval,
    Catatan
FROM Approval_Cuti
WHERE ID_Pengajuan = 2
ORDER BY ID_Approval;

SELECT
    ID_Riwayat,
    ID_Pegawai,
    Perubahan_Saldo,
    Keterangan
FROM Riwayat_Kuota_Cuti
WHERE ID_Pegawai = 5
ORDER BY ID_Riwayat;

DELETE FROM Riwayat_Kuota_Cuti
WHERE ID_Riwayat IN (8, 9);

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti
FROM v_sisa_cuti_pegawai;

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Nama_Pegawai,
    Nama_Jenis_Cuti,
    Tgl_Mulai,
    Tgl_Selesai,
    Durasi_Hari,
    Status_Pengajuan
FROM v_daftar_pengajuan_cuti
ORDER BY ID_Pengajuan;

DESCRIBE v_daftar_pengajuan_cuti;

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
ORDER BY ID_Pengajuan;

SELECT
    ID_Riwayat,
    ID_Pegawai,
    Nama_Pegawai,
    Perubahan_Saldo,
    Keterangan
FROM v_riwayat_kuota_cuti
ORDER BY ID_Riwayat;

SHOW FUNCTION STATUS
WHERE Db = 'sistem_cuti';

SHOW PROCEDURE STATUS
WHERE Db = 'sistem_cuti';

SHOW TRIGGERS FROM sistem_cuti;

SHOW FULL TABLES
WHERE Table_type = 'VIEW';

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Durasi_Hari,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 3;

UPDATE Pengajuan_Cuti
SET Status_Pengajuan = 'pending'
WHERE ID_Pengajuan = 3;

UPDATE Pengajuan_Cuti
SET Status_Pengajuan = 'disetujui'
WHERE ID_Pengajuan = 3;

DELETE FROM Riwayat_Kuota_Cuti
WHERE ID_Riwayat = 11;

UPDATE Pegawai
SET Sisa_Cuti_Tahunan = Sisa_Cuti_Tahunan + 3
WHERE ID_Pegawai = 5;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti_Tahunan
FROM Pegawai
WHERE ID_Pegawai = 5;

SHOW CREATE PROCEDURE sp_batalkan_pengajuan_cuti;
SHOW CREATE PROCEDURE sp_buat_pengajuan_cuti;
SHOW CREATE PROCEDURE sp_lihat_pengajuan_bawahan;
SHOW CREATE PROCEDURE sp_nonaktifkan_pegawai;
SHOW CREATE PROCEDURE sp_setujui_pengajuan_cuti;
SHOW CREATE PROCEDURE sp_tolak_pengajuan_cuti;
SHOW CREATE PROCEDURE sp_tambah_jenis_cuti;
SHOW CREATE PROCEDURE sp_tambah_sisa_cuti_tahunan;
SHOW CREATE PROCEDURE sp_tambah_pegawai_baru;
SHOW CREATE PROCEDURE sp_tambah_libur_nasional;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    ID_Atasan,
    Role
FROM Pegawai
ORDER BY ID_Pegawai;

UPDATE Pegawai
SET ID_Atasan = 3
WHERE ID_Pegawai = 6;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    ID_Atasan,
    Role
FROM Pegawai
ORDER BY ID_Pegawai;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    ID_Atasan,
    Role,
    Sisa_Cuti_Tahunan,
    Status_Aktif
FROM Pegawai
WHERE Nama_Pegawai = 'Dina';

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Status_Aktif
FROM Pegawai
WHERE Nama_Pegawai = 'Dina';

SELECT
    ID_Jenis,
    Nama_Jenis,
    Apakah_Potong_Cuti_Tahunan
FROM Jenis_Cuti
ORDER BY ID_Jenis DESC;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Sisa_Cuti_Tahunan
FROM Pegawai
WHERE ID_Pegawai = 5;

SELECT
    ID_Riwayat,
    ID_Pegawai,
    Perubahan_Saldo,
    Keterangan
FROM Riwayat_Kuota_Cuti
WHERE ID_Pegawai = 5
ORDER BY ID_Riwayat DESC;

SELECT
    ID_Libur,
    Tanggal_Libur,
    Keterangan
FROM Libur_Nasional
ORDER BY ID_Libur DESC;

DESCRIBE Libur_Nasional;

SELECT
    Tanggal_Libur,
    Keterangan
FROM Libur_Nasional
ORDER BY Tanggal_Libur DESC;

DESCRIBE Riwayat_Kuota_Cut

SELECT
    TABLE_NAME,
    COLUMN_NAME,
    CONSTRAINT_NAME,
    REFERENCED_TABLE_NAME,
    REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE REFERENCED_TABLE_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME = 'Pegawai'
ORDER BY TABLE_NAME, COLUMN_NAM


SELECT ID_Pengajuan, ID_Pegawai, Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 2;

SELECT ID_Pegawai, Sisa_Cuti_Tahunan
FROM Pegawai
WHERE ID_Pegawai = 5;

SELECT ID_Riwayat, ID_Pegawai, Perubahan_Saldo, Keterangan
FROM Riwayat_Kuota_Cuti
WHERE ID_Pegawai = 5
ORDER BY ID_Riwayat DESC
LIMIT 5;

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    ID_Jenis,
    Tgl_Mulai,
    Tgl_Selesai,
    Status_Pengajuan
FROM Pengajuan_Cuti
ORDER BY ID_Pengajuan DESC
LIMIT 5;

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Tgl_Mulai,
    Tgl_Selesai,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 8;

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Status_Pengajuan
FROM Pengajuan_Cuti
ORDER BY ID_Pengajuan DESC;

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 10;

SELECT
    ID_Pengajuan,
    ID_Pegawai,
    Status_Pengajuan
FROM Pengajuan_Cuti
WHERE ID_Pengajuan = 11;

SHOW CREATE PROCEDURE sp_tambah_pegawai_baru;

DESCRIBE Pegawai;
SHOW COLUMNS FROM Pegawai
WHERE Field IN ('Username', 'Password_Hash', 'Role');

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Role,
    Username,
    Password_Hash,
    Status_Aktif
FROM Pegawai
ORDER BY ID_Pegawai DESC
LIMIT 1;

SELECT
    ID_Pegawai,
    Nama_Pegawai,
    Role,
    Username,
    Password_Hash IS NOT NULL AS Password_Tersimpan,
    Status_Aktif
FROM Pegawai
WHERE Username = 'tespegawai01';

select * from pegawai

select * from Jenis_Cuti

call sp_tambah_jenis_cuti( 'cuti natal', 1)
call sp_hapus_jenis_cuti(3)



drop procedure if exists sp_hapus_jenis_cuti;
create procedure sp_hapus_jenis_cuti(
    in p_ID_Jenis int
)

begin
    declare exit handler for sqlexception
    begin
        rollback;
        resignal;
    end;

    start transaction;

    delete from Jenis_Cuti where ID_Jenis = p_ID_Jenis;

    commit;
end

