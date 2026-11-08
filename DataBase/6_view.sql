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
