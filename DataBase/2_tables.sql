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
    Username          VARCHAR(50) NOT NULL UNIQUE,
    Password_Hash     VARCHAR(255) NOT NULL,
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
 