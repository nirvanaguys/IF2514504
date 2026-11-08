const express = require('express');
const mysql = require('mysql2/promise');

const app = express();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
require('dotenv').config();
app.use(express.json());


app.post('/api/login', async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        success: false,
        message: 'Username dan password wajib diisi.'
      });
    }

    const [rows] = await db.execute(
      `SELECT ID_Pegawai, Nama_Pegawai, Username,
              Password_Hash, Role, Status_Aktif
       FROM Pegawai
       WHERE Username = ?
       LIMIT 1`,
      [username]
    );

    if (rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Username atau password salah.'
      });
    }

    const pegawai = rows[0];

    const passwordValid = await bcrypt.compare(
      password,
      pegawai.Password_Hash || ''
    );

    if (!passwordValid) {
      return res.status(401).json({
        success: false,
        message: 'Username atau password salah.'
      });
    }

    if (!pegawai.Status_Aktif) {
      return res.status(403).json({
        success: false,
        message: 'Akun tidak aktif.'
      });
    }

    if (!process.env.JWT_SECRET) {
      throw new Error('JWT_SECRET belum dikonfigurasi.');
    }

    const token = jwt.sign(
      {
        id_pegawai: pegawai.ID_Pegawai,
        role: pegawai.Role
      },
      process.env.JWT_SECRET,
      { expiresIn: '2h' }
    );

    return res.status(200).json({
      success: true,
      message: 'Login berhasil.',
      token,
      user: {
        id_pegawai: pegawai.ID_Pegawai,
        nama: pegawai.Nama_Pegawai,
        username: pegawai.Username,
        role: pegawai.Role
      }
    });
  } catch (error) {
    console.error('Login error:', error.message);

    return res.status(500).json({
      success: false,
      message: 'Terjadi kesalahan pada server.'
    });
  }
});


function authenticateToken(req, res, next) {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Token autentikasi diperlukan.'
    });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({
        success: false,
        message: 'Token tidak valid atau sudah kedaluwarsa.'
      });
    }

    req.user = user;
    next();
  });
}

function authorizeRoles(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: 'Anda tidak memiliki izin untuk mengakses fitur ini.'
      });
    }

    next();
  };
}


const db = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD !== undefined ? process.env.DB_PASSWORD : '',
    database: process.env.DB_NAME || 'sistem_cuti'
});

app.get('/', (req, res) => {
    res.json({
        message: 'API Sistem Cuti berjalan'
    });
});

app.get('/api/test-db', async (req, res) => {
    try {
        const [rows] = await db.query('SELECT DATABASE() AS nama_database');

        res.json({
            success: true,
            database: rows[0].nama_database
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

app.get('/api/cuti/sisa', async (req, res) => {
    try {
        const [rows] = await db.query(`
            SELECT
                ID_Pegawai,
                Nama_Pegawai,
                Sisa_Cuti
            FROM v_sisa_cuti_pegawai
        `);

        res.json({
            success: true,
            data: rows
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

app.get('/api/cuti/sisa-saya'   ,
  authenticateToken,
  async (req, res) => {
    try {
        const idPegawai = req.user.id_pegawai;
        const [rows] = await db.query(
            `SELECT fn_sisa_cuti(?) AS Sisa_Cuti`,
            [idPegawai]
        );

        res.json({
            success: true,
            ID_Pegawai: Number(idPegawai),
            Sisa_Cuti: rows[0].Sisa_Cuti
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

app.post('/api/cuti/pengajuan', authenticateToken, async (req, res) => {
    try {
       const {
        id_jenis,
        tgl_mulai,
        tgl_selesai
    } = req.body;

const id_pegawai = req.user.id_pegawai;

        const [result] = await db.query(
            `CALL sp_buat_pengajuan_cuti(?, ?, ?, ?)`,
            [
                id_pegawai,
                id_jenis,
                tgl_mulai,
                tgl_selesai
            ]
        );

        res.json({
            success: true,
            message: 'Pengajuan cuti berhasil dibuat',
            data: result
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});

app.get('/api/cuti', async (req, res) => {
    try {
        const [rows] = await db.query(`
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
            ORDER BY ID_Pengajuan DESC
        `);

        const data = rows.map(row => ({
            ...row,
            Tgl_Mulai: row.Tgl_Mulai
                ? row.Tgl_Mulai.toISOString().split('T')[0]
                : null,
            Tgl_Selesai: row.Tgl_Selesai
                ? row.Tgl_Selesai.toISOString().split('T')[0]
                : null
        }));

        res.json({
            success: true,
            data: data
        });

    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

app.post('/api/cuti/approve',authenticateToken,authorizeRoles ('manajer','hrd'), async (req, res) => {
    try {
       const {
     id_pengajuan,
     catatan
    } = req.body;

const id_approver = req.user.id_pegawai;

        const [result] = await db.query(
            `CALL sp_setujui_pengajuan_cuti(?, ?, ?)`,
            [
                id_pengajuan,
                id_approver,
                catatan
            ]
        );

        res.json({
            success: true,
            message: 'Pengajuan cuti berhasil disetujui',
            data: result
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});

app.get('/api/cuti/riwayat/:id', async (req, res) => {
    try {
        const idPegawai = req.params.id;

        const [rows] = await db.query(`
            SELECT
                ID_Riwayat,
                ID_Pegawai,
                Perubahan_Saldo,
                Keterangan
            FROM v_riwayat_kuota_cuti
            WHERE ID_Pegawai = ?
        `, [idPegawai]);

        res.json({
            success: true,
            data: rows
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

app.post('/api/cuti/cancel', authenticateToken, async (req, res) => {
    try {
        const { id_pengajuan } = req.body;
        const id_pegawai = req.user.id_pegawai;

        const [result] = await db.query(
            `CALL sp_batalkan_pengajuan_cuti(?, ?)`,
            [
                id_pengajuan,
                id_pegawai
            ]
        );

        res.json({
            success: true,
            message: 'Pengajuan cuti berhasil dibatalkan',
            data: result
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});


app.get('/api/cuti/bawahan',authenticateToken,authorizeRoles('manajer', 'hrd'),async (req, res) => {
    try {
      const idAtasan = Number(req.user.id_pegawai);
      if (!Number.isInteger(idAtasan) || idAtasan <= 0) {
        return res.status(400).json({
          success: false,
          message: 'ID atasan tidak valid.'
        });
      }

      const [rows] = await db.query(
        'CALL sp_lihat_pengajuan_bawahan(?)',
        [idAtasan]
      );

      const data = (rows[0] || []).map(row => ({
        ...row,
        Tgl_Mulai: row.Tgl_Mulai
          ? row.Tgl_Mulai.toISOString().split('T')[0]
          : null,
        Tgl_Selesai: row.Tgl_Selesai
          ? row.Tgl_Selesai.toISOString().split('T')[0]
          : null
      }));

      res.json({
        success: true,
        data
      });
    } catch (error) {
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
);


app.post('/api/cuti/reject',authenticateToken,authorizeRoles('manajer','hrd'), async (req, res) => {
    try {
       const {
    id_pengajuan,
    catatan
} = req.body;

const id_approver = req.user.id_pegawai;

        const [result] = await db.query(
            'CALL sp_tolak_pengajuan_cuti(?, ?, ?)',
            [
                id_pengajuan,
                id_approver,
                catatan
            ]
        );

        res.json({
            success: true,
            message: 'Pengajuan cuti berhasil ditolak',
            data: result
        });

    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});



app.post('/api/tambah/pegawai',authenticateToken,authorizeRoles('hrd'),async (req, res) => {
        try {
            const {
                nama_pegawai,
                id_atasan,
                role,
                sisa_cuti,
                username,
                password
            } = req.body;

            if (
                !nama_pegawai ||
                !username ||
                !password ||
                !['pegawai', 'manajer', 'hrd'].includes(role)
            ) {
                return res.status(400).json({
                    success: false,
                    message: 'Nama, username, password, dan role yang valid wajib diisi.'
                });
            }

            if (
                typeof username !== 'string' ||
                username.trim().length > 50
            ) {
                return res.status(400).json({
                    success: false,
                    message: 'Username maksimal 50 karakter.'
                });
            }

            if (typeof password !== 'string' || password.length < 8) {
                return res.status(400).json({
                    success: false,
                    message: 'Password minimal 8 karakter.'
                });
            }

            const passwordHash = await bcrypt.hash(password, 10);

            const [result] = await db.query(
                'CALL sp_tambah_pegawai_baru(?, ?, ?, ?, ?, ?)',
                [
                    nama_pegawai,
                    id_atasan ?? null,
                    role,
                    sisa_cuti,
                    username.trim(),
                    passwordHash
                ]
            );

            res.status(201).json({
                success: true,
                message: 'Pegawai dan akun login berhasil dibuat.',
                data: result
            });

        } catch (error) {
            if (error.sqlState === '45000' || error.code === 'ER_DUP_ENTRY') {
                return res.status(400).json({
                    success: false,
                    message: error.message
                });
            }

            console.error('Gagal menambahkan pegawai:', error.message);

            res.status(500).json({
                success: false,
                message: 'Terjadi kesalahan saat menambahkan pegawai.'
            });
        }
    }
);



app.patch('/api/pegawai/:id/nonaktif',authenticateToken,authorizeRoles('hrd'),
    async (req, res) => {
        try {
            const idPegawai = Number(req.params.id);

            if (!Number.isInteger(idPegawai) || idPegawai <= 0) {
                return res.status(400).json({
                    success: false,
                    message: 'ID pegawai tidak valid.'
                });
            }

            const [result] = await db.query(
                'CALL sp_nonaktifkan_pegawai(?)',
                [idPegawai]
            );

            res.json({
                success: true,
                message: 'Pegawai berhasil dinonaktifkan.',
                data: result
            });

        } catch (error) {
            res.status(400).json({
                success: false,
                message: error.message
            });
        }
    }
);


app.post('/api/jenis-cuti',authenticateToken,authorizeRoles('hrd'), async (req, res) => {
    try {
        const { nama, potong } = req.body;

        const [result] = await db.query(
            'CALL sp_tambah_jenis_cuti(?, ?)',
            [nama, potong]
        );

        res.json({
            success: true,
            message: 'Jenis cuti berhasil ditambahkan',
            data: result
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});

app.post('/api/cuti/tambah-kuota',authenticateToken,authorizeRoles('hrd'), async (req, res) => {
    try {
        const { id_pegawai, jumlah, keterangan } = req.body;

        const [result] = await db.query(
            'CALL sp_tambah_sisa_cuti_tahunan(?, ?, ?)',
            [id_pegawai, jumlah, keterangan]
        );

        res.json({
            success: true,
            message: 'Sisa cuti tahunan berhasil ditambahkan',
            data: result
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});

app.post('/api/libur',authenticateToken,authorizeRoles('hrd'), async (req, res) => {
    try {
        const { tanggal, keterangan } = req.body;

        const [result] = await db.query(
            'CALL sp_tambah_libur_nasional(?, ?)',
            [tanggal, keterangan]
        );

        res.json({
            success: true,
            message: 'Hari libur nasional berhasil ditambahkan',
            data: result
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});

app.get('/api/pegawai', async (req, res) => {
    try {
        const [result] = await db.query(
            'CALL sp_lihat_daftar_pegawai()'
        );

        res.json({
            success: true,
            data: result[0]
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});


app.get('/api/cuti/riwayat-kuota/:id', async (req, res) => {
  try {
    const idPegawai = Number(req.params.id);

    if (!Number.isInteger(idPegawai) || idPegawai <= 0) {
      return res.status(400).json({
        success: false,
        message: 'ID pegawai tidak valid.'
      });
    }

    const [result] = await db.query(
      'CALL sp_lihat_riwayat_kuota_cuti(?)',
      [idPegawai]
    );

    res.json({
      success: true,
      data: result[0] || []
    });
  } catch (error) {
    const status = error.sqlState === '45000' ? 404 : 500;

    res.status(status).json({
      success: false,
      message: error.message
    });
  }
});


app.get('/api/cuti/pegawai/:id', authenticateToken, async (req, res) => {
  try {
    const idPegawai = Number(req.user.id_pegawai);

    if (!Number.isInteger(idPegawai) || idPegawai <= 0) {
      return res.status(400).json({
        success: false,
        message: 'ID pegawai tidak valid.'
      });
    }

    const [result] = await db.query(
      'CALL sp_lihat_pengajuan_pegawai(?)',
      [idPegawai]
    );

    res.json({
      success: true,
      data: result[0] || []
    });
  } catch (error) {
    const status = error.sqlState === '45000' ? 404 : 500;

    res.status(status).json({
      success: false,
      message: error.message
    });
  }
});

app.listen(3000, () => {
    console.log('Server berjalan di http://localhost:3000');
});