const express = require("express");
const router = express.Router();
const rateLimit = require("express-rate-limit");
const { verifyToken } = require("../middlewares/authMiddleware");

const { login, register, forgotPassword, resetPassword, updateProfile } = require("../controllers/authController");

const isTestEnv = process.env.NODE_ENV === "test";
const authLimiterMax = Number(process.env.AUTH_RATE_LIMIT_MAX || (isTestEnv ? 1000 : 10));
const resetLimiterMax = Number(process.env.RESET_RATE_LIMIT_MAX || (isTestEnv ? 1000 : 5));

// Giriş ve kayıt: 15 dakikada max 10 deneme (brute force koruması)
const authLimiter = rateLimit({
	windowMs: 15 * 60 * 1000,
	max: authLimiterMax,
	standardHeaders: true,
	legacyHeaders: false,
	message: { message: "Çok fazla deneme yaptınız. 15 dakika sonra tekrar deneyin." }
});

// Şifre sıfırlama: 1 saatte max 5 istek
const resetLimiter = rateLimit({
	windowMs: 60 * 60 * 1000,
	max: resetLimiterMax,
	standardHeaders: true,
	legacyHeaders: false,
	message: { message: "Çok fazla şifre sıfırlama isteği. 1 saat sonra tekrar deneyin." }
});

router.post("/register", authLimiter, register);
router.post("/login", authLimiter, login);
router.post("/forgot-password", resetLimiter, forgotPassword);
router.post("/reset-password", resetLimiter, resetPassword);
router.put("/profile", verifyToken, updateProfile);

module.exports = router;