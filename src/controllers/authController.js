const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const db = require("../config/db");
const { sendPasswordResetEmail } = require("../utils/mailer");

// Geliştirme aşamasında admin hesabını koruyoruz.
const admin = {
  email: "admin@test.com",
  name: "Admin",
  password: bcrypt.hashSync("123456", 10)
};

const jwtSecret = process.env.JWT_SECRET || "secretkey123";

db.query(
  `
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL UNIQUE,
      password VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `,
  (err) => {
    if (err) {
      console.error("Failed to ensure users table exists:", err.message);
    }
  }
);

db.query(
  `
    CREATE TABLE IF NOT EXISTS password_resets (
      id INT AUTO_INCREMENT PRIMARY KEY,
      email VARCHAR(255) NOT NULL,
      token VARCHAR(6) NOT NULL,
      expires_at DATETIME NOT NULL,
      used TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `,
  (err) => {
    if (err) {
      console.error("Failed to ensure password_resets table exists:", err.message);
    }
  }
);

const findUserByEmail = (email, callback) => {
  db.query(
    "SELECT id, name, email, password FROM users WHERE email = ? LIMIT 1",
    [email],
    (err, results) => {
      if (err) {
        return callback(err);
      }

      return callback(null, results[0] || null);
    }
  );
};

// POST /register
const register = (req, res) => {
  const { email, password, name } = req.body;
  const normalizedEmail = email?.trim().toLowerCase();
  const normalizedName = name?.trim();

  // Basit validasyon
  if (!normalizedEmail || !password || !normalizedName) {
    return res.status(400).json({
      message: "Email, password ve name gerekli"
    });
  }

  // Email format kontrolü
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    return res.status(400).json({
      message: "Geçersiz email formatı"
    });
  }

  // Password uzunluğu kontrolü
  if (password.length < 6) {
    return res.status(400).json({
      message: "Password en az 6 karakter olmalı"
    });
  }

  if (normalizedEmail === admin.email) {
    return res.status(409).json({
      message: "Bu email zaten kullanımda"
    });
  }

  findUserByEmail(normalizedEmail, (findErr, existingUser) => {
    if (findErr) {
      return res.status(500).json({
        message: "Database error",
        error: findErr.message
      });
    }

    if (existingUser) {
      return res.status(409).json({
        message: "Bu email zaten kullanımda"
      });
    }

    const hashedPassword = bcrypt.hashSync(password, 10);

    db.query(
      "INSERT INTO users (name, email, password) VALUES (?, ?, ?)",
      [normalizedName, normalizedEmail, hashedPassword],
      (insertErr, result) => {
        if (insertErr) {
          return res.status(500).json({
            message: "Kayıt oluşturulamadı",
            error: insertErr.message
          });
        }

        return res.status(201).json({
          message: "Kayıt başarılı",
          user: {
            id: result.insertId,
            email: normalizedEmail,
            name: normalizedName
          }
        });
      }
    );
  });
};

// POST /forgot-password
const forgotPassword = (req, res) => {
  const { email } = req.body;
  const normalizedEmail = email?.trim().toLowerCase();

  if (!normalizedEmail) {
    return res.status(400).json({
      message: "Email gerekli"
    });
  }

  const checkUser = (callback) => {
    if (normalizedEmail === admin.email) {
      return callback(null, true);
    }
    findUserByEmail(normalizedEmail, (err, user) => {
      if (err) return callback(err);
      callback(null, !!user);
    });
  };

  checkUser((err, exists) => {
    if (err) {
      return res.status(500).json({ message: "Database error", error: err.message });
    }

    if (!exists) {
      // Güvenlik: kullanıcı yoksa bile başarı dön (enumeration'ı önle)
      return res.json({ message: "Şifre sıfırlama kodu gönderildi" });
    }

    // 6 haneli sayısal token üret
    const token = String(crypto.randomInt(100000, 999999));
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 dakika

    // Önce bu email'e ait eski tokenları iptal et
    db.query(
      "UPDATE password_resets SET used = 1 WHERE email = ? AND used = 0",
      [normalizedEmail],
      (updateErr) => {
        if (updateErr) {
          return res.status(500).json({ message: "Database error", error: updateErr.message });
        }

        db.query(
          "INSERT INTO password_resets (email, token, expires_at) VALUES (?, ?, ?)",
          [normalizedEmail, token, expiresAt],
          async (insertErr) => {
            if (insertErr) {
              return res.status(500).json({ message: "Database error", error: insertErr.message });
            }

            try {
              await sendPasswordResetEmail(normalizedEmail, token);
            } catch (mailErr) {
              console.error("Email gönderilemedi:", mailErr.message);
              // Email hatası olsa bile token oluşturduk, devam et
            }

            return res.json({ message: "Şifre sıfırlama kodu gönderildi" });
          }
        );
      }
    );
  });
};

// POST /reset-password
const resetPassword = (req, res) => {
  const { email, token, newPassword } = req.body;
  const normalizedEmail = email?.trim().toLowerCase();

  if (!normalizedEmail || !token || !newPassword) {
    return res.status(400).json({
      message: "Email, token ve yeni şifre gerekli"
    });
  }

  if (newPassword.length < 6) {
    return res.status(400).json({
      message: "Şifre en az 6 karakter olmalı"
    });
  }

  db.query(
    `SELECT * FROM password_resets
     WHERE email = ? AND token = ? AND used = 0 AND expires_at > NOW()
     ORDER BY created_at DESC LIMIT 1`,
    [normalizedEmail, token.trim()],
    (err, results) => {
      if (err) {
        return res.status(500).json({ message: "Database error", error: err.message });
      }

      if (results.length === 0) {
        return res.status(400).json({ message: "Geçersiz veya süresi dolmuş kod" });
      }

      const resetId = results[0].id;
      const hashedPassword = bcrypt.hashSync(newPassword, 10);

      // Admin şifresini bellekte güncelliyoruz (geliştirme ortamı için)
      if (normalizedEmail === admin.email) {
        admin.password = hashedPassword;
        db.query("UPDATE password_resets SET used = 1 WHERE id = ?", [resetId]);
        return res.json({ message: "Şifre başarıyla güncellendi" });
      }

      db.query(
        "UPDATE users SET password = ? WHERE email = ?",
        [hashedPassword, normalizedEmail],
        (updateErr) => {
          if (updateErr) {
            return res.status(500).json({ message: "Database error", error: updateErr.message });
          }

          db.query("UPDATE password_resets SET used = 1 WHERE id = ?", [resetId]);
          return res.json({ message: "Şifre başarıyla güncellendi" });
        }
      );
    }
  );
};

// POST /login
const login = (req, res) => {
  const { email, password } = req.body;
  const normalizedEmail = email?.trim().toLowerCase();

  if (!normalizedEmail || !password) {
    return res.status(400).json({
      message: "Email ve password gerekli"
    });
  }

  if (normalizedEmail === admin.email) {
    const isMatch = bcrypt.compareSync(password, admin.password);

    if (!isMatch) {
      return res.status(401).json({
        message: "Invalid password"
      });
    }

    const token = jwt.sign(
      { role: "admin", email: admin.email, name: admin.name },
      jwtSecret,
      { expiresIn: "1h" }
    );

    return res.json({
      message: "Login successful",
      token,
      user: {
        email: admin.email,
        name: admin.name,
        role: "admin"
      }
    });
  }

  findUserByEmail(normalizedEmail, (err, user) => {
    if (err) {
      return res.status(500).json({
        message: "Database error",
        error: err.message
      });
    }

    if (!user) {
      return res.status(401).json({
        message: "Invalid email"
      });
    }

    const isMatch = bcrypt.compareSync(password, user.password);

    if (!isMatch) {
      return res.status(401).json({
        message: "Invalid password"
      });
    }

    const token = jwt.sign(
      { role: "user", userId: user.id, email: user.email, name: user.name },
      jwtSecret,
      { expiresIn: "1h" }
    );

    return res.json({
      message: "Login successful",
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: "user"
      }
    });
  });
};

// PUT /auth/profile
const updateProfile = (req, res) => {
  const userEmailFromToken = req.user?.email;
  const userRole = req.user?.role;
  const { name, currentPassword, newPassword } = req.body;

  if (!userEmailFromToken) {
    return res.status(400).json({ message: "Token içinde email bulunamadı" });
  }

  const normalizedName = typeof name === "string" ? name.trim() : "";
  const wantsNameChange = normalizedName.length > 0;
  const wantsPasswordChange = typeof newPassword === "string" && newPassword.trim().length > 0;

  if (!wantsNameChange && !wantsPasswordChange) {
    return res.status(400).json({ message: "Güncellenecek bir alan gönderilmedi" });
  }

  if (wantsPasswordChange) {
    if (!currentPassword || typeof currentPassword !== "string") {
      return res.status(400).json({ message: "Şifre değişikliği için mevcut şifre gerekli" });
    }

    if (newPassword.trim().length < 6) {
      return res.status(400).json({ message: "Yeni şifre en az 6 karakter olmalı" });
    }
  }

  if (userRole === "admin" && userEmailFromToken === admin.email) {
    if (wantsPasswordChange) {
      const isMatch = bcrypt.compareSync(currentPassword, admin.password);
      if (!isMatch) {
        return res.status(401).json({ message: "Mevcut şifre yanlış" });
      }
      admin.password = bcrypt.hashSync(newPassword.trim(), 10);
    }

    if (wantsNameChange) {
      admin.name = normalizedName;
    }

    return res.json({
      message: "Profil güncellendi",
      user: {
        email: admin.email,
        name: admin.name,
        role: "admin"
      }
    });
  }

  findUserByEmail(userEmailFromToken, (findErr, user) => {
    if (findErr) {
      return res.status(500).json({ message: "Database error", error: findErr.message });
    }

    if (!user) {
      return res.status(404).json({ message: "Kullanıcı bulunamadı" });
    }

    if (wantsPasswordChange) {
      const isMatch = bcrypt.compareSync(currentPassword, user.password);
      if (!isMatch) {
        return res.status(401).json({ message: "Mevcut şifre yanlış" });
      }
    }

    const fields = [];
    const values = [];

    if (wantsNameChange) {
      fields.push("name = ?");
      values.push(normalizedName);
    }

    if (wantsPasswordChange) {
      fields.push("password = ?");
      values.push(bcrypt.hashSync(newPassword.trim(), 10));
    }

    values.push(user.id);

    db.query(
      `UPDATE users SET ${fields.join(", ")} WHERE id = ?`,
      values,
      (updateErr) => {
        if (updateErr) {
          return res.status(500).json({ message: "Profil güncellenemedi", error: updateErr.message });
        }

        return res.json({
          message: "Profil güncellendi",
          user: {
            id: user.id,
            email: user.email,
            name: wantsNameChange ? normalizedName : user.name,
            role: "user"
          }
        });
      }
    );
  });
};

module.exports = { login, register, forgotPassword, resetPassword, updateProfile };